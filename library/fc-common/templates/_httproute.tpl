{{- /* The app's routing on the Gateway. One behaviour, one place: every app
       chart includes this rather than carrying its own copy, because six copies
       is how the fcone one came to be missing the hostname splitting.

       Called with a dict, since a library template cannot reach the chart's own
       helpers:

         {{- include "fc.httproute" (dict "ctx" . "fullname" (include "<chart>.fullname" .) "labels" (include "<chart>.labels" .)) }}
*/ -}}
{{- define "fc.httproute" -}}
{{- /* An app's routing on the Gateway, owned by the app, in the same shape as
       the ingress block. The argocd repo's gateway chart keeps the Gateway, its
       listeners and its wildcard certificate; everything specific to one app
       lives here, so onboarding an app needs no commit to the argocd repo.

       Same model as fcone's httproute.yaml minus BackendTLSPolicy: these
       backends serve plain HTTP, so TLS ends at the Gateway exactly as it
       ended at nginx. */}}
{{- if .ctx.Values.httpRoute.enabled }}
{{- /* Two sources claiming one hostname make external-dns see two owners and
       the records flap between nginx and the gateway address. Retiring the
       Ingress and enabling the route belong in the same change. */}}
{{- if .ctx.Values.ingress.enabled }}{{ fail "ingress.enabled and httpRoute.enabled are both on, so the Ingress and the HTTPRoute would both claim these hostnames; turn ingress.enabled off in the same change that enables the route" }}{{ end }}
{{- $fullName := .fullname }}
{{- $port := .ctx.Values.httpRoute.port | default .ctx.Values.service.port }}
{{- if not $port }}{{ fail "httpRoute.enabled needs a backend port: set httpRoute.port, or service.port for the whole chart" }}{{ end }}
{{- /* parentRefs is a cross-namespace reference into the argocd repo's gateway
       chart, so nothing here can confirm the Gateway exists. An empty field is
       the one failure visible from here: it silently attaches to nothing. */}}
{{- $gw := .ctx.Values.httpRoute.gateway }}
{{- if or (not $gw.name) (not $gw.namespace) (not $gw.sectionName) }}{{ fail "httpRoute.gateway needs name, namespace and sectionName; they must match the Gateway the argocd repo deploys (release fc-gw in namespace fc-gateway, listener https)" }}{{ end }}
{{- /* One app, one route is the common case and stays the plain form: hostnames
       and rules at the top of the block.

       Two things break that. A route accepts at most 16 hostnames, which is a
       limit of the API and nothing to do with how an app thinks about its
       names, so the template splits a longer list itself rather than making
       someone keep buckets in values and remember which has room. And rules
       apply to every hostname on their route, so hostnames that need different
       paths cannot share one: those go in httpRoute.routes, where the name
       says what distinguishes them.

       Neither case is a reason to move hostnames back into the argocd repo. */}}
{{- $routes := .ctx.Values.httpRoute.routes | default list }}
{{- if $routes }}
{{- if .ctx.Values.httpRoute.hostnames }}{{ fail "httpRoute.hostnames and httpRoute.routes are both set; move those hostnames into a routes entry so one place lists them" }}{{ end }}
{{- if .ctx.Values.httpRoute.rules }}{{ fail "httpRoute.rules and httpRoute.routes are both set; rules belong to a route, so move them into the routes entry they apply to" }}{{ end }}
{{- else }}
{{- if not .ctx.Values.httpRoute.hostnames }}{{ fail "httpRoute.enabled needs at least one entry in httpRoute.hostnames, or a httpRoute.routes entry carrying them" }}{{ end }}
{{- $routes = list (dict "hostnames" .ctx.Values.httpRoute.hostnames "rules" (.ctx.Values.httpRoute.rules | default list)) }}
{{- end }}
{{- /* Flattened first so the split is settled before anything renders: a route
       is one entry here, or several when its hostnames do not fit. A list that
       fits keeps the plain name, so the suffix appears only where a split
       actually happened and adding the 17th hostname is what renames it. */}}
{{- $rendered := list }}
{{- range $r := $routes }}
{{- if not $r.hostnames }}{{ fail "every httpRoute.routes entry needs its own hostnames" }}{{ end }}
{{- $base := $fullName }}
{{- if $r.name }}{{ $base = printf "%s-%s" $fullName $r.name }}{{ end }}
{{- $chunks := chunk 16 $r.hostnames }}
{{- range $ci, $hosts := $chunks }}
{{- $rname := $base }}
{{- if gt (len $chunks) 1 }}{{ $rname = printf "%s-%d" $base (add1 $ci) }}{{ end }}
{{- $rendered = append $rendered (dict "name" $rname "hostnames" $hosts "route" $r) }}
{{- end }}
{{- end }}
{{- $seen := dict }}
{{- range $e := $rendered }}
{{- if hasKey $seen $e.name }}{{ fail (printf "two routes would both be named %s; give each httpRoute.routes entry a distinct name, and at most one entry no name at all" $e.name) }}{{ end }}
{{- $_ := set $seen $e.name true }}
{{- end }}
{{- range $i, $e := $rendered }}
{{- $r := $e.route }}
{{- if $i }}
---
{{- end }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $e.name }}
  labels:
    {{- $.labels | nindent 4 }}
spec:
  parentRefs:
    - name: {{ $gw.name }}
      namespace: {{ $gw.namespace }}
      sectionName: {{ $gw.sectionName }}
  hostnames:
    {{- range $e.hostnames }}
    - {{ . | quote }}
    {{- end }}
  rules:
    {{- /* No rules means the whole site, which is what most apps want. */}}
    {{- range $rule := ($r.rules | default (list dict)) }}
    {{- /* A rule overrides its route, which overrides the block default.
           default reads an empty map or string as unset, so an override that
           clears an inherited value has to be found with hasKey. */}}
    {{- $headers := $.ctx.Values.httpRoute.requestHeaders }}
    {{- if hasKey $r "requestHeaders" }}{{- $headers = $r.requestHeaders }}{{- end }}
    {{- if hasKey $rule "requestHeaders" }}{{- $headers = $rule.requestHeaders }}{{- end }}
    {{- $timeout := $.ctx.Values.httpRoute.timeout }}
    {{- if hasKey $r "timeout" }}{{- $timeout = $r.timeout }}{{- end }}
    {{- if hasKey $rule "timeout" }}{{- $timeout = $rule.timeout }}{{- end }}
    - matches:
        - path:
            type: PathPrefix
            value: {{ $rule.path | default "/" | quote }}
      {{- if or $headers $rule.rewritePrefix }}
      filters:
        {{- if $headers }}
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              {{- range $name, $value := $headers }}
              - name: {{ $name | quote }}
                value: {{ $value | quote }}
              {{- end }}
        {{- end }}
        {{- if $rule.rewritePrefix }}
        {{- /* Replaces nginx's rewrite-target: drops the matched prefix so an
               app served under a subpath still receives the paths it expects. */}}
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: {{ $rule.rewritePrefix | quote }}
        {{- end }}
      {{- end }}
      backendRefs:
        - name: {{ $fullName }}
          port: {{ $port }}
      {{- if $timeout }}
      timeouts:
        request: {{ $timeout | quote }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end }}
{{- end -}}

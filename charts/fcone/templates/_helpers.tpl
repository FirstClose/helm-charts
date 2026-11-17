{{/*
Expand the name of the chart.
*/}}
{{- define "fconet.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "fconet.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "fconet.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fconet.labels" -}}
helm.sh/chart: {{ include "fconet.chart" . }}
{{ include "fconet.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "fconet.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fconet.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "fconet.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "fconet.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The configMap data, with the IIS host bindings derived from httpRoute.hostnames
and every httpRoute.extraRoutes entry's.

Those WEBSITE- entries drive two things inside the container: the HTTPS binding
IIS creates for each hostname, and the loop that binds the certificate to those
bindings. An app whose route names a host it has no WEBSITE- entry for therefore
serves the image's own self-signed certificate and fails backend verification,
silently and only at the gateway. Deriving both from one list removes that
failure mode.

An explicit env.configMap entry always wins, so an app that already names its
bindings by hand keeps them exactly as they are.
*/}}
{{- define "fconet.envConfigMap" -}}
{{- $cm := dict }}
{{- if and .Values.env .Values.env.configMap }}
{{- $cm = deepCopy .Values.env.configMap }}
{{- end }}
{{- if and .Values.httpRoute .Values.httpRoute.enabled .Values.httpRoute.manageWebsiteBindings }}
{{- $derived := dict }}
{{- range (include "fconet.httpRouteHostnames" . | fromJsonArray) }}
{{- /* Wildcard labels are dropped before the key is taken: "*" is legal in a
       hostname but not in a ConfigMap key or an env var name, so *.foo.com
       would otherwise render WEBSITE-* and the API server would reject both
       objects. The binding value stays the full hostname, which IIS accepts as
       a wildcard host header. */}}
{{- $key := printf "WEBSITE-%s" ((without (splitList "." .) "*") | first) }}
{{- /* The key is only the leading label, so two hostnames differing further
       right collapse onto it. Silently keeping the first put the second back
       in exactly the state this helper exists to prevent: routed by the
       gateway, bound by nothing, serving the image's self-signed certificate.
       Refusing to render is the only outcome that stays visible. */}}
{{- if hasKey $derived $key }}{{ fail (printf "httpRoute.hostnames %s and %s both derive %s, so only one would get an IIS binding and the other would fail backend TLS at the gateway; name that one by hand in env.configMap" (get $derived $key) . $key) }}{{ end }}
{{- $_ := set $derived $key . }}
{{- if not (hasKey $cm $key) }}
{{- $_ := set $cm $key . }}
{{- end }}
{{- end }}
{{- end }}
{{- toYaml $cm -}}
{{- end }}

{{/*
Every hostname the app answers on: httpRoute.hostnames followed by each
extraRoutes entry's, as a JSON list (fromJsonArray to read it). The IIS
bindings and the backend certificate are derived from this, so a name served
only by an extra route still gets its binding and its SAN.

Also where extraRoutes is checked, because every consumer passes through it.
*/}}
{{- define "fconet.httpRouteHostnames" -}}
{{- $all := list }}
{{- range .Values.httpRoute.hostnames }}
{{- $all = append $all . }}
{{- end }}
{{- $names := list }}
{{- range .Values.httpRoute.extraRoutes }}
{{- if not .name }}{{ fail "every httpRoute.extraRoutes entry needs a name; it becomes the suffix of the HTTPRoute's name" }}{{ end }}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" .name) }}{{ fail (printf "httpRoute.extraRoutes name %q must be lowercase letters, digits and dashes" .name) }}{{ end }}
{{- if has .name $names }}{{ fail (printf "httpRoute.extraRoutes name %s is used twice, so both would render the same HTTPRoute" .name) }}{{ end }}
{{- $names = append $names .name }}
{{- if not .hostnames }}{{ fail (printf "httpRoute.extraRoutes %s needs at least one hostname" .name) }}{{ end }}
{{- range .hostnames }}
{{- /* The same name on two routes would put it on both Gateways, the very
       thing a separate route exists to avoid. */}}
{{- if has . $all }}{{ fail (printf "hostname %s appears on more than one route in httpRoute; each name belongs to exactly one Gateway" .) }}{{ end }}
{{- $all = append $all . }}
{{- end }}
{{- end }}
{{- toJson $all -}}
{{- end }}

{{/*
One HTTPRoute to the app's Service. Takes a dict: root (the chart context),
name, gateway (name, namespace, sectionName), hostnames and rules. The main
route and every extraRoutes entry render through this, so they cannot drift.
*/}}
{{- define "fconet.httpRoute" -}}
{{- $root := .root }}
{{- $fullName := include "fconet.fullname" $root }}
{{- $port := $root.Values.httpRoute.port | default $root.Values.service.port }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .name }}
  labels:
    {{- include "fconet.labels" $root | nindent 4 }}
spec:
  parentRefs:
    - name: {{ .gateway.name }}
      namespace: {{ .gateway.namespace }}
      sectionName: {{ .gateway.sectionName }}
  hostnames:
    {{- range .hostnames }}
    - {{ . | quote }}
    {{- end }}
  rules:
    {{- /* No rules means the whole site, which is what most apps want. */}}
    {{- range $rule := (.rules | default (list dict)) }}
    {{- $headers := $root.Values.httpRoute.requestHeaders }}
    {{- if hasKey $rule "requestHeaders" }}{{- $headers = $rule.requestHeaders }}{{- end }}
    {{- $timeout := $root.Values.httpRoute.timeout }}
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
        {{- /* Drops the matched prefix so an app served under a subpath still
               receives the paths it expects. */}}
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

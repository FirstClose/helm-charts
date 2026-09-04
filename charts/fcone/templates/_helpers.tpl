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
The configMap data, with the IIS host bindings derived from httpRoute.hostnames.

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
{{- range .Values.httpRoute.hostnames }}
{{- $key := printf "WEBSITE-%s" ((splitList "." .) | first) }}
{{- if not (hasKey $cm $key) }}
{{- $_ := set $cm $key . }}
{{- end }}
{{- end }}
{{- end }}
{{- toYaml $cm -}}
{{- end }}

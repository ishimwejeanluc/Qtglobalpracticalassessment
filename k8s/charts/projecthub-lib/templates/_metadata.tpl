{{/*
Naming and labels. Every service chart sets .Values.component (api, frontend, ...).
Resource names = release name (e.g. release "projecthub-api" -> Deployment "projecthub-api").
*/}}

{{- define "projecthub-lib.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "projecthub-lib.component" -}}
{{- required "component must be set in the chart's values.yaml" .Values.component -}}
{{- end }}

{{/* Selector labels: stable, never change on a live release */}}
{{- define "projecthub-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ include "projecthub-lib.component" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "projecthub-lib.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "projecthub-lib.selectorLabels" . }}
app.kubernetes.io/part-of: projecthub
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* repository:tag - the tag defaults to the chart's appVersion */}}
{{- define "projecthub-lib.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end }}

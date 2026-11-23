{{/*
Pod and container building blocks shared by every workload (PSA "restricted" compliant).
*/}}

{{/* Pod security context: numeric non-root user, RuntimeDefault seccomp */}}
{{- define "projecthub-lib.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: {{ .Values.securityContext.uid }}
runAsGroup: {{ .Values.securityContext.gid | default .Values.securityContext.uid }}
fsGroup: {{ .Values.securityContext.gid | default .Values.securityContext.uid }}
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{/* Container security context: no privilege escalation, no capabilities, read-only root */}}
{{- define "projecthub-lib.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
{{- end }}

{{/* Dedicated ServiceAccount, API token not mounted (no pod calls the Kubernetes API) */}}
{{- define "projecthub-lib.podIdentity" -}}
serviceAccountName: {{ include "projecthub-lib.fullname" . }}
automountServiceAccountToken: false
{{- end }}

{{/* Best-effort spread of replicas across nodes */}}
{{- define "projecthub-lib.topologySpread" -}}
{{- if .Values.topologySpread }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        {{- include "projecthub-lib.selectorLabels" . | nindent 8 }}
{{- end }}
{{- end }}

{{/* Zero-downtime rolling updates */}}
{{- define "projecthub-lib.rollingUpdate" -}}
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
{{- end }}

{{/* Probes from values: only the ones that are set */}}
{{- define "projecthub-lib.probes" -}}
{{- with .Values.probes.startup }}
startupProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.probes.readiness }}
readinessProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.probes.liveness }}
livenessProbe:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

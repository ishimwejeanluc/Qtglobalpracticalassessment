{{/*
Complete resources that every service chart renders the same way.
Each service chart has a one-line template file per resource that includes these.
*/}}

{{- define "projecthub-lib.serviceAccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "projecthub-lib.fullname" . }}
  labels:
    {{- include "projecthub-lib.labels" . | nindent 4 }}
automountServiceAccountToken: false
{{- end }}

{{/* PodDisruptionBudget - values: pdb.enabled, pdb.minAvailable */}}
{{- define "projecthub-lib.pdb" -}}
{{- if .Values.pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "projecthub-lib.fullname" . }}
  labels:
    {{- include "projecthub-lib.labels" . | nindent 4 }}
spec:
  minAvailable: {{ .Values.pdb.minAvailable }}
  selector:
    matchLabels:
      {{- include "projecthub-lib.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end }}

{{/*
Ingress NetworkPolicy - values:
  networkPolicy.enabled
  networkPolicy.port            port the pods accept traffic on
  networkPolicy.from            list of allowed sources; empty list = any source
    - component: edge           pods of another ProjectHub service (same namespace)
    - namespace: envoy-gateway-system   every pod of a namespace
The namespace-wide default-deny policy lives in k8s/namespace.yaml.
*/}}
{{- define "projecthub-lib.networkPolicy" -}}
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "projecthub-lib.fullname" . }}-ingress
  labels:
    {{- include "projecthub-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "projecthub-lib.selectorLabels" . | nindent 6 }}
  policyTypes: [Ingress]
  ingress:
    - ports:
        - protocol: TCP
          port: {{ .Values.networkPolicy.port }}
      {{- with .Values.networkPolicy.from }}
      from:
        {{- range . }}
        {{- if .namespace }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .namespace }}
        {{- else }}
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: {{ .component }}
              app.kubernetes.io/part-of: projecthub
        {{- end }}
        {{- end }}
      {{- end }}
{{- end }}
{{- end }}

{{/* ClusterIP Service on a named port - values: service.port */}}
{{- define "projecthub-lib.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "projecthub-lib.fullname" . }}
  labels:
    {{- include "projecthub-lib.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "projecthub-lib.selectorLabels" . | nindent 4 }}
  ports:
    - name: {{ .Values.service.portName | default "http" }}
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.portName | default "http" }}
{{- end }}

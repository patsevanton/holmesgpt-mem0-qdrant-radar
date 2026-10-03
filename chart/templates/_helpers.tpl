{{- define "bench-apps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "bench-apps.labels" -}}
helm.sh/chart: {{ include "bench-apps.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "bench-apps.image" -}}
{{- printf "%s/%s:%s" .registry .repository .tag -}}
{{- end }}

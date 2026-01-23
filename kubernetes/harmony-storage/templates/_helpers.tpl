{{/*
Expand the name of the chart.
*/}}
{{- define "harmony-storage.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "harmony-storage.fullname" -}}
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
{{- define "harmony-storage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "harmony-storage.labels" -}}
helm.sh/chart: {{ include "harmony-storage.chart" . }}
{{ include "harmony-storage.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "harmony-storage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "harmony-storage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validate global platform value
*/}}
{{- define "harmony-storage.validatePlatform" -}}
{{- if not .Values.global.platform }}
{{- fail "global.platform is required. Please set it to 'aws', 'azure', or 'gcp'." }}
{{- end }}
{{- if not (or (eq .Values.global.platform "aws") (eq .Values.global.platform "azure") (eq .Values.global.platform "gcp")) }}
{{- fail (printf "global.platform '%s' is not supported. Supported values are 'aws', 'azure', or 'gcp'." .Values.global.platform) }}
{{- end }}
{{- end }}

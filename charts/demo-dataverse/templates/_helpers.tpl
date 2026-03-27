{{/*
Expand the name of the chart.
*/}}
{{- define "demo-dataverse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "demo-dataverse.fullname" -}}
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
{{- define "demo-dataverse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "demo-dataverse.labels" -}}
helm.sh/chart: {{ include "demo-dataverse.chart" . }}
{{ include "demo-dataverse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "demo-dataverse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-dataverse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service / CLI label query for the main Dataverse pods only. Pods also set component=primary;
Deployment matchLabels stay name+instance only so upgrades do not hit immutable selector changes.
*/}}
{{- define "demo-dataverse.primarySelectorLabels" -}}
{{ include "demo-dataverse.selectorLabels" . }}
app.kubernetes.io/component: primary
{{- end }}

{{/*
Labels for the optional in-chart standalone Solr Deployment/Service (must NOT match demo-dataverse.selectorLabels
or the main Deployment ReplicaSet will count Solr pods).
*/}}
{{- define "demo-dataverse.internalSolrLabels" -}}
helm.sh/chart: {{ include "demo-dataverse.chart" . }}
app.kubernetes.io/name: {{ include "demo-dataverse.name" . }}-solr
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: internal-solr
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "demo-dataverse.internalSolrSelectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-dataverse.name" . }}-solr
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: internal-solr
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "demo-dataverse.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "demo-dataverse.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

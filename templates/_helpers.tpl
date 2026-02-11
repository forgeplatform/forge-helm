{{/* Common labels */}}
{{- define "forge.labels" -}}
app.kubernetes.io/name: forge
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: forge-platform
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Selector labels for a given component (component name passed as second arg) */}}
{{- define "forge.selectorLabels" -}}
app.kubernetes.io/name: forge
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Component labels = common labels + component */}}
{{- define "forge.componentLabels" -}}
{{ include "forge.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Namespace */}}
{{- define "forge.namespace" -}}
{{- .Values.namespace.name | default "forge" -}}
{{- end }}

{{/*
Common backend env vars (forge-init, forge-web, forge-task)
Wraps DB, Redis, secrets, OTel, admin into one block to avoid drift.
*/}}
{{- define "forge.backendEnv" -}}
- name: DATABASE_HOST
  value: forge-postgres
- name: DATABASE_PORT
  value: "5432"
- name: DATABASE_USER
  value: {{ .Values.postgres.user | quote }}
- name: DATABASE_NAME
  value: {{ .Values.postgres.database | quote }}
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forge-secrets
      key: postgresPassword
- name: POSTGRES_USER
  value: {{ .Values.postgres.user | quote }}
- name: POSTGRES_DB
  value: {{ .Values.postgres.database | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forge-secrets
      key: postgresPassword
- name: REDIS_HOST
  value: forge-redis
- name: REDIS_PORT
  value: "6379"
- name: FORGE_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: forge-secrets
      key: forgeSecretKey
- name: FORGE_BROADCAST_WEBSOCKET_SECRET
  valueFrom:
    secretKeyRef:
      name: forge-secrets
      key: forgeBroadcastWebsocketSecret
- name: FORGE_ADMIN_USER
  value: {{ .Values.forge.admin.user | quote }}
- name: FORGE_ADMIN_EMAIL
  value: {{ .Values.forge.admin.email | quote }}
- name: FORGE_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forge-secrets
      key: forgeAdminPassword
- name: FORGE_ALLOWED_HOSTS
  value: {{ .Values.forge.allowedHosts | quote }}
- name: FORGE_CSRF_TRUSTED_ORIGINS
  value: {{ .Values.forge.csrfTrustedOrigins | quote }}
- name: FORGE_COOKIE_SECURE
  value: {{ .Values.forge.cookieSecure | default "true" | quote }}
- name: FORGE_NODE_NAME
  value: {{ .Values.forge.node.name | quote }}
- name: FORGE_NODE_TYPE
  value: {{ .Values.forge.node.type | quote }}
- name: TENANCY_ENABLED
  value: {{ .Values.forge.tenancyEnabled | quote }}
- name: OTEL_ENABLED
  value: {{ .Values.forge.otel.enabled | quote }}
- name: OTEL_EXPORTER_ENDPOINT
  value: {{ .Values.forge.otel.endpoint | quote }}
- name: OTEL_SERVICE_NAME
  value: {{ .Values.forge.otel.serviceName | quote }}
- name: OTEL_TRACES_SAMPLER
  value: {{ .Values.forge.otel.tracesSampler | quote }}
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ .Values.forge.otel.tracesSamplerArg | quote }}
{{- end }}

{{/*
Common backend volume mounts (settings, scripts, receptor, persistent data).
Used by forge-init, forge-web, forge-task.
*/}}
{{- define "forge.backendVolumeMounts" -}}
- name: settings
  mountPath: /etc/tower/settings.py
  subPath: settings.py
  readOnly: true
- name: settings
  mountPath: /etc/tower/conf.d/database.py
  subPath: database.py
  readOnly: true
- name: settings
  mountPath: /etc/tower/conf.d/redis_settings.py
  subPath: redis_settings.py
  readOnly: true
- name: settings
  mountPath: /etc/tower/conf.d/secret_key.py
  subPath: secret_key.py
  readOnly: true
- name: settings
  mountPath: /etc/tower/conf.d/websocket_secret.py
  subPath: websocket_secret.py
  readOnly: true
- name: settings
  mountPath: /etc/tower/conf.d/custom_settings.py
  subPath: custom_settings.py
  readOnly: true
- name: receptor
  mountPath: /etc/receptor/receptor.conf
  subPath: receptor.conf
  readOnly: true
- name: forge-projects
  mountPath: /var/lib/awx/projects
- name: forge-receptor
  mountPath: /var/run/awx-receptor
{{- end }}

{{/*
Common backend volumes (settings + scripts ConfigMaps + emptyDirs for shared paths)
*/}}
{{- define "forge.backendVolumes" -}}
- name: settings
  configMap:
    name: forge-settings
- name: receptor
  configMap:
    name: forge-receptor
- name: forge-projects
  emptyDir: {}
- name: forge-receptor
  emptyDir: {}
{{- end }}

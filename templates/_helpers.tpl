{{/* Common labels */}}
{{- define "forail.labels" -}}
app.kubernetes.io/name: forail
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: forail-platform
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* Selector labels for a given component (component name passed as second arg) */}}
{{- define "forail.selectorLabels" -}}
app.kubernetes.io/name: forail
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Component labels = common labels + component */}}
{{- define "forail.componentLabels" -}}
{{ include "forail.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Namespace */}}
{{- define "forail.namespace" -}}
{{- .Values.namespace.name | default "forail" -}}
{{- end }}

{{/*
Common backend env vars (forail-init, forail-web, forail-task)
Wraps DB, Redis, secrets, OTel, admin into one block to avoid drift.
*/}}
{{- define "forail.backendEnv" -}}
- name: DATABASE_HOST
  value: forail-postgres
- name: DATABASE_PORT
  value: "5432"
- name: DATABASE_USER
  value: {{ .Values.postgres.user | quote }}
- name: DATABASE_NAME
  value: {{ .Values.postgres.database | quote }}
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forail-secrets
      key: postgresPassword
- name: POSTGRES_USER
  value: {{ .Values.postgres.user | quote }}
- name: POSTGRES_DB
  value: {{ .Values.postgres.database | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forail-secrets
      key: postgresPassword
- name: REDIS_HOST
  value: forail-redis
- name: REDIS_PORT
  value: "6379"
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forail-secrets
      key: redisPassword
- name: FORAIL_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: forail-secrets
      key: forailSecretKey
- name: FORAIL_BROADCAST_WEBSOCKET_SECRET
  valueFrom:
    secretKeyRef:
      name: forail-secrets
      key: forailBroadcastWebsocketSecret
- name: FORAIL_ADMIN_USER
  value: {{ .Values.forail.admin.user | quote }}
- name: FORAIL_ADMIN_EMAIL
  value: {{ .Values.forail.admin.email | quote }}
- name: FORAIL_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: forail-secrets
      key: forailAdminPassword
{{- $ns := include "forail.namespace" . }}
- name: FORAIL_ALLOWED_HOSTS
  {{- /*
    In-cluster consumers reach the API through the forail-web Service, so their
    Host header is the Service DNS name, never the ingress host. Django answers
    400 ("The request could not be understood by the server.") for any Host not
    listed, which broke the documented forail-operator install
    (--set forail.url=http://forail-web.<ns>.svc.cluster.local:8013). These four
    names are cluster-internal and derived from the release, so appending them
    keeps needtofix M9 tight while making in-cluster access work by default.
  */}}
  value: {{ printf "%s,forail-web,forail-web.%s,forail-web.%s.svc,forail-web.%s.svc.cluster.local" .Values.forail.allowedHosts $ns $ns $ns | quote }}
- name: FORAIL_CSRF_TRUSTED_ORIGINS
  value: {{ .Values.forail.csrfTrustedOrigins | quote }}
- name: FORAIL_COOKIE_SECURE
  value: {{ .Values.forail.cookieSecure | default "true" | quote }}
- name: FORAIL_NODE_NAME
  value: {{ .Values.forail.node.name | quote }}
- name: FORAIL_NODE_TYPE
  value: {{ .Values.forail.node.type | quote }}
{{- if and (has .Values.forail.node.type (list "hybrid" "execution")) (not .Values.task.privileged) }}
{{- fail "forail.node.type=hybrid runs jobs through podman inside the task pod, which needs --set task.privileged=true --set task.hostCgroup=true. Without them podman fails on the overlay mount and every job stays Pending. Either set both, or use the default forail.node.type=control, which runs jobs as separate Kubernetes pods and needs no privileges." }}
{{- end }}
{{- if and .Values.forail.tenancyEnabled (not .Values.forail.tenancy.rls) }}
{{- fail "forail.tenancyEnabled=true requires forail.tenancy.rls=true — without row-level security the tenancy features run with no boundary behind them. Set --set forail.tenancy.rls=true, or turn tenancy off." }}
{{- end }}
- name: TENANCY_ENABLED
  value: {{ .Values.forail.tenancyEnabled | quote }}
- name: TENANCY_RLS_ENABLED
  value: {{ and .Values.forail.tenancyEnabled .Values.forail.tenancy.rls | quote }}
- name: TENANCY_STRICT_ISOLATION_ENABLED
  value: {{ and .Values.forail.tenancyEnabled .Values.forail.tenancy.strictIsolation | quote }}
- name: TENANCY_RATE_LIMITING_ENABLED
  value: {{ and .Values.forail.tenancyEnabled .Values.forail.tenancy.rateLimiting | quote }}
- name: OTEL_ENABLED
  value: {{ .Values.forail.otel.enabled | quote }}
- name: OTEL_EXPORTER_ENDPOINT
  value: {{ .Values.forail.otel.endpoint | quote }}
- name: OTEL_SERVICE_NAME
  value: {{ .Values.forail.otel.serviceName | quote }}
- name: OTEL_TRACES_SAMPLER
  value: {{ .Values.forail.otel.tracesSampler | quote }}
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ .Values.forail.otel.tracesSamplerArg | quote }}
# Namespace the container-group scheduler launches automation job pods into
# (AWX_CONTAINER_GROUP_DEFAULT_NAMESPACE reads MY_POD_NAMESPACE). Bind it to
# the release namespace via the downward API so jobs run where the pod RBAC
# in rbac.yaml is granted, not the cluster "default" namespace.
- name: MY_POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- end }}

{{/*
Name of the ServiceAccount the web/task/init pods run as. When
serviceAccount.create is false, fall back to the namespace "default" account.
*/}}
{{- define "forail.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
default
{{- end -}}
{{- end }}

{{/*
Common backend volume mounts (settings, scripts, receptor, persistent data).
Used by forail-init, forail-web, forail-task.
*/}}
{{- define "forail.backendVolumeMounts" -}}
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
- name: forail-projects
  mountPath: /var/lib/awx/projects
- name: forail-receptor
  mountPath: /var/run/awx-receptor
{{- end }}

{{/*
Common backend volumes (settings + scripts ConfigMaps + emptyDirs for shared paths)
*/}}
{{- define "forail.backendVolumes" -}}
- name: settings
  configMap:
    name: forail-settings
- name: receptor
  configMap:
    name: forail-receptor
- name: forail-projects
  emptyDir: {}
- name: forail-receptor
  emptyDir: {}
{{- end }}

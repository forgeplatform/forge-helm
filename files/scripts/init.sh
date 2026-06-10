#!/bin/bash
set -e

echo "==> Waiting for database..."
until forail-manage check_db --skip-checks 2>/dev/null; do
    echo "    Database not ready, retrying in 3s..."
    sleep 3
done
echo "==> Database is ready."

echo "==> Running migrations..."
forail-manage migrate --skip-checks --noinput

echo "==> Creating/updating admin user..."
# Create the superuser if it does not exist.
forail-manage createsuperuser --skip-checks --noinput \
    --username "${FORAIL_ADMIN_USER:-admin}" \
    --email "${FORAIL_ADMIN_EMAIL:-admin@example.com}" 2>/dev/null || true

# Always reset the password to match the env var.
forail-manage update_password --skip-checks \
    --username "${FORAIL_ADMIN_USER:-admin}" \
    --password "${FORAIL_ADMIN_PASSWORD:?FORAIL_ADMIN_PASSWORD is required}"

echo "==> Provisioning instance..."
NODE_NAME="${FORAIL_NODE_NAME:-$(hostname)}"
NODE_TYPE="${FORAIL_NODE_TYPE:-hybrid}"

forail-manage provision_instance --skip-checks \
    --hostname="${NODE_NAME}" \
    --node_type="${NODE_TYPE}"

# provision_instance only inserts if missing — it does not update an
# already-registered instance. forail-web auto-registers itself as
# 'control' on first startup before this Job runs, so without this
# explicit ORM update the cluster ends up with node_type=control and
# refuses to execute jobs (it can only orchestrate). Force-set the
# requested type so launches stay on this instance via the local
# Receptor work command instead of routing to a ContainerGroup.
forail-manage shell -c "
from forail.main.models import Instance
i = Instance.objects.filter(hostname='${NODE_NAME}').first()
if i and i.node_type != '${NODE_TYPE}':
    i.node_type = '${NODE_TYPE}'
    i.save(update_fields=['node_type'])
    print('Updated', i.hostname, 'node_type ->', i.node_type)
else:
    print('Instance node_type already', i.node_type if i else 'missing')
"

echo "==> Registering queues..."
forail-manage register_queue --skip-checks --queuename=controlplane --instance_percent=100
forail-manage register_queue --skip-checks --queuename=default      --instance_percent=100

# A post_migrate signal in forail auto-creates the 'default' InstanceGroup
# as is_container_group=true when running in k8s. Without a working
# ContainerGroup that resolves to a local Receptor work type, every job
# launch errors with 'unknown work type kubernetes-incluster-auth'.
# Flip it back to a regular IG so register_queue's instance assignment
# above is honored and jobs run via the local work command.
forail-manage shell -c "
from forail.main.models import InstanceGroup
ig = InstanceGroup.objects.filter(name='default').first()
if ig and ig.is_container_group:
    ig.is_container_group = False
    ig.pod_spec_override = ''
    ig.save(update_fields=['is_container_group', 'pod_spec_override'])
    print('default IG: is_container_group -> False')
else:
    print('default IG already non-container or missing')
"

echo "==> Creating preload data..."
forail-manage create_preload_data --skip-checks 2>/dev/null || true

echo "==> Registering default execution environments..."
forail-manage register_default_execution_environments --skip-checks

echo "==> Setting CSRF trusted origins..."
CSRF_ORIGINS="${FORAIL_CSRF_TRUSTED_ORIGINS:-https://localhost,https://localhost:8043}"
forail-manage shell -c "
from forail.conf.models import Setting
origins = '${CSRF_ORIGINS}'.split(',')
Setting.objects.update_or_create(key='CSRF_TRUSTED_ORIGINS', defaults={'value': origins})
print('CSRF_TRUSTED_ORIGINS set to:', origins)
"

echo "==> Clearing AWX isolation show paths..."
# upstream forail/settings/production.py hardcodes two CentOS CA-trust
# bind mounts (/etc/pki/ca-trust and /usr/share/pki). These paths do
# not exist on our Ubuntu-based forail-backend image so podman dies with
# 'mounting overlay failed "/usr/share/pki": no such file or directory'
# the instant an EE container tries to start. AWX_ISOLATION_SHOW_PATHS
# is DB-backed (editable in admin UI), so we blank it here. Operators
# that need custom CA trust can repopulate it from the UI with paths
# that actually exist inside the forail-backend image.
forail-manage shell -c "
from forail.conf.models import Setting
Setting.objects.update_or_create(key='AWX_ISOLATION_SHOW_PATHS', defaults={'value': []})
print('AWX_ISOLATION_SHOW_PATHS set to []')
"

echo "==> Initialization complete."

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
# Fallback is hybrid for the compose deployment, which runs jobs through
# podman on the host VM. The Helm chart always sets this explicitly, and
# defaults it to control.
NODE_TYPE="${FORAIL_NODE_TYPE:-hybrid}"

forail-manage provision_instance --skip-checks \
    --hostname="${NODE_NAME}" \
    --node_type="${NODE_TYPE}"

echo "==> Registering queues..."
forail-manage register_queue --skip-checks --queuename=controlplane --instance_percent=100
forail-manage register_queue --skip-checks --queuename=default      --instance_percent=100

# What the 'default' instance group has to look like depends on where jobs run,
# and register_queue does not reliably leave either shape behind.
#
# NODE_TYPE=control (the chart default): jobs run as separate pods, submitted to
#   receptor as the "kubernetes-incluster-auth" work type, which is configured in
#   receptor.conf and backed by the namespaced pod RBAC. The group must be a
#   ContainerGroup and must NOT contain this instance -- a container group
#   dispatches to Kubernetes, not to a member node.
#
# NODE_TYPE=hybrid / execution (compose, or a k8s install that opted into
#   podman-in-pod): this node runs jobs itself through the local receptor work
#   command, so the group must be a regular instance group that contains it.
#   Both halves matter -- a regular group with no execution-capable member
#   accepts launches and never runs them, and the job sits in "pending" with
#   nothing but "not enough available capacity" to go on.
#
# Membership also has to be asserted on every run, not just at creation: on an
# UPGRADE the group already exists, so register_queue prints "Instance Group
# already registered" and assigns nothing.
#
# node_type is re-asserted as a backstop. The real fix is in the backend -- the
# task pod re-runs provision_instance on every start and used to re-register as
# 'control' unconditionally, undoing whatever this Job set; it now honours
# FORAIL_NODE_TYPE. Keep the assertion so a newer chart paired with an older
# backend image still converges.
forail-manage shell -c "
from forail.main.models import Instance, InstanceGroup
from django.conf import settings

node_type = '${NODE_TYPE}'
runs_jobs_locally = node_type in ('hybrid', 'execution')

ig = InstanceGroup.objects.filter(name='default').first()
if not ig:
    print('default IG missing — register_queue did not create it')
else:
    i = Instance.objects.filter(hostname='${NODE_NAME}').first()
    if i and i.node_type != node_type:
        i.node_type = node_type
        i.save(update_fields=['node_type'])
        print('instance node_type ->', i.node_type)

    if runs_jobs_locally:
        if ig.is_container_group:
            ig.is_container_group = False
            ig.pod_spec_override = ''
            ig.save(update_fields=['is_container_group', 'pod_spec_override'])
            print('default IG: is_container_group -> False')
        if not i:
            print('instance ${NODE_NAME} missing — cannot assign to default IG')
        elif not ig.instances.filter(pk=i.pk).exists():
            ig.instances.add(i)
            print('default IG: added', i.hostname)
        else:
            print('default IG already contains', i.hostname)
    else:
        if not ig.is_container_group:
            ig.is_container_group = True
            ig.pod_spec_override = settings.DEFAULT_EXECUTION_QUEUE_POD_SPEC_OVERRIDE
            ig.save(update_fields=['is_container_group', 'pod_spec_override'])
            print('default IG: is_container_group -> True')
        # A container group dispatches to Kubernetes; a member instance here
        # would make the scheduler try to run the job on this node instead.
        if i and ig.instances.filter(pk=i.pk).exists():
            ig.instances.remove(i)
            print('default IG: removed member', i.hostname, '(container group)')
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

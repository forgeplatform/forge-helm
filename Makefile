CHART      := forail
NAMESPACE  ?= forail
RELEASE    ?= forail
DEPLOY_DIR ?= ../forail-deploy
DIST       := dist

.PHONY: lint
lint:
	helm lint .

.PHONY: template
template:
	helm template $(RELEASE) . -n $(NAMESPACE)

.PHONY: package
package:
	@mkdir -p $(DIST)
	helm package . -d $(DIST)

.PHONY: install
install:
	helm install $(RELEASE) . -n $(NAMESPACE) --create-namespace

.PHONY: upgrade
upgrade:
	helm upgrade $(RELEASE) . -n $(NAMESPACE)

.PHONY: uninstall
uninstall:
	helm uninstall $(RELEASE) -n $(NAMESPACE)

# Sync the static config files in files/ from the upstream forail-deploy
# repo (cloned as a sibling at $(DEPLOY_DIR)). Run after upstream config
# changes.
.PHONY: sync-from-deploy
sync-from-deploy:
	@test -d $(DEPLOY_DIR) || { echo "ERROR: $(DEPLOY_DIR) not found — clone forail-deploy alongside forail-helm"; exit 1; }
	cp $(DEPLOY_DIR)/settings/*.py             files/settings/
	cp $(DEPLOY_DIR)/scripts/*.sh              files/scripts/
	cp $(DEPLOY_DIR)/receptor/receptor.conf    files/receptor/
	cp $(DEPLOY_DIR)/otel/config.yaml          files/otel/
	cp $(DEPLOY_DIR)/settings/nginx-internal.conf files/nginx/
	@echo "Sync complete. Review with 'git diff'."

.PHONY: clean
clean:
	rm -rf $(DIST) Chart.lock charts/

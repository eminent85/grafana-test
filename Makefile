SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
KUSTOMIZE ?= $(KUBECTL) kustomize
OVERLAY ?= platform/overlays/production

.PHONY: help render local-render preflight validate bootstrap local-bootstrap status diff clean
help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\n"} /^[a-zA-Z_-]+:.*?## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

render: ## Render operator and platform manifests into build/
	@mkdir -p build
	$(KUSTOMIZE) operator/base > build/operator.yaml
	$(KUSTOMIZE) $(OVERLAY) > build/platform.yaml

local-render: ## Render the single-node Rancher Desktop manifests
	@mkdir -p build
	$(KUSTOMIZE) operator/overlays/local > build/operator-local.yaml
	$(KUSTOMIZE) platform/overlays/local > build/platform-local.yaml

preflight: render ## Fail if required production values are unresolved
	./scripts/preflight.sh build/platform.yaml

validate: preflight ## Run local structural and schema checks
	./scripts/validate.sh

bootstrap: preflight ## Install operator, wait, then install Argo CD
	$(KUBECTL) apply --server-side --force-conflicts -f build/operator.yaml
	$(KUBECTL) rollout status deployment/argocd-operator-controller-manager -n argocd-operator-system --timeout=5m
	$(KUBECTL) apply --server-side -f build/platform.yaml
	./scripts/status.sh

local-bootstrap: local-render ## Install the single-node local operator and Argo CD
	$(KUBECTL) apply --server-side --force-conflicts -f build/operator-local.yaml
	$(KUBECTL) rollout status deployment/argocd-operator-controller-manager -n argocd-operator-system --timeout=5m
	$(KUBECTL) apply --server-side -f build/platform-local.yaml
	./scripts/status.sh

status: ## Wait for the operator and Argo CD control plane
	./scripts/status.sh

diff: preflight ## Show server-side differences without applying them
	-$(KUBECTL) diff --server-side -f build/operator.yaml
	-$(KUBECTL) diff --server-side -f build/platform.yaml

clean: ## Remove generated local files
	rm -rf build

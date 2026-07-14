SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
KUSTOMIZE ?= $(KUBECTL) kustomize
OVERLAY ?= platform/overlays/production

.PHONY: help render local-render preflight local-preflight validate local-validate bootstrap local-bootstrap status local-status diff local-diff clean
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

local-preflight: local-render ## Fail if the local manifests are unsafe or incomplete
	./scripts/preflight.sh build/platform-local.yaml

validate: preflight ## Run local structural and schema checks
	./scripts/validate.sh

local-validate: local-preflight ## Validate the Rancher Desktop manifests
	./scripts/validate.sh local

bootstrap: preflight ## Install operator, wait, then install Argo CD
	$(KUBECTL) apply --server-side --force-conflicts -f build/operator.yaml
	$(KUBECTL) rollout status deployment/argocd-operator-controller-manager -n argocd-operator-system --timeout=5m
	$(KUBECTL) apply --server-side -f build/platform.yaml
	./scripts/status.sh

local-bootstrap: local-preflight ## Install local Argo CD and its GitOps bootstrap resources
	$(KUBECTL) apply --server-side --force-conflicts -f build/operator-local.yaml
	$(KUBECTL) rollout status deployment/argocd-operator-controller-manager -n argocd-operator-system --timeout=5m
	$(KUBECTL) apply --server-side -f build/platform-local.yaml
	./scripts/status.sh local

status: ## Wait for the operator and Argo CD control plane
	./scripts/status.sh

local-status: ## Wait for local Argo CD and the Git-managed smoke application
	./scripts/status.sh local

diff: preflight ## Show server-side differences without applying them
	-$(KUBECTL) diff --server-side -f build/operator.yaml
	-$(KUBECTL) diff --server-side -f build/platform.yaml

local-diff: local-preflight ## Show Rancher Desktop server-side differences
	-@if $(KUBECTL) get namespace argocd-operator-system >/dev/null 2>&1; then \
		$(KUBECTL) diff --server-side -f build/operator-local.yaml; \
	else \
		echo "operator diff unavailable until the first bootstrap creates argocd-operator-system"; \
	fi
	-@if $(KUBECTL) get crd argocds.argoproj.io >/dev/null 2>&1; then \
		$(KUBECTL) diff --server-side -f build/platform-local.yaml; \
	else \
		echo "platform diff unavailable until the first bootstrap installs the Argo CD CRDs"; \
	fi

clean: ## Remove generated local files
	rm -rf build

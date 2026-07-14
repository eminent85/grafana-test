#!/usr/bin/env bash
set -euo pipefail

mode="${1:-production}"
if [[ "${mode}" != "production" && "${mode}" != "local" ]]; then
  echo "error: status mode must be 'production' or 'local'" >&2
  exit 1
fi

kubectl wait --for=condition=Established crd/argocds.argoproj.io --timeout=2m
kubectl rollout status deployment/argocd-operator-controller-manager -n argocd-operator-system --timeout=5m
kubectl wait --for=condition=Reconciled argocd/platform -n argocd --timeout=10m
kubectl wait --for=jsonpath='{.status.phase}'=Available argocd/platform -n argocd --timeout=10m

kubectl get argocd,pods,ingress -n argocd

if kubectl api-resources --api-group=external-secrets.io -o name | grep -qx 'externalsecrets.external-secrets.io'; then
  kubectl get externalsecret -n argocd
fi

if [[ "${mode}" == "local" ]]; then
  for _ in $(seq 1 60); do
    if kubectl get application/gitops-smoke -n argocd >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done

  kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/gitops-smoke -n argocd --timeout=10m
  kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/gitops-smoke -n argocd --timeout=10m
  kubectl get applicationset,application,appproject -n argocd
  kubectl get configmap/gitops-smoke -n gitops-smoke
fi

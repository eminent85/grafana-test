#!/usr/bin/env bash
set -euo pipefail

kubectl wait --for=condition=Established crd/argocds.argoproj.io --timeout=2m
kubectl rollout status deployment/argocd-operator-controller-manager -n argocd-operator-system --timeout=5m
kubectl wait --for=condition=Reconciled argocd/platform -n argocd --timeout=10m
kubectl wait --for=jsonpath='{.status.phase}'=Available argocd/platform -n argocd --timeout=10m

kubectl get argocd,pods,ingress,externalsecret -n argocd

#!/usr/bin/env bash
set -euo pipefail

mode="${1:-production}"
case "${mode}" in
  production)
    manifests=(build/operator.yaml build/platform.yaml)
    ;;
  local)
    manifests=(build/operator-local.yaml build/platform-local.yaml)
    ;;
  *)
    echo "error: validation mode must be 'production' or 'local'" >&2
    exit 1
    ;;
esac

required=(kubectl)
for command in "${required[@]}"; do
  command -v "${command}" >/dev/null || { echo "error: ${command} is required" >&2; exit 1; }
done

kubectl kustomize operator/base >/dev/null
kubectl kustomize operator/overlays/local >/dev/null
kubectl kustomize platform/base >/dev/null
kubectl kustomize platform/overlays/local >/dev/null
kubectl kustomize platform/overlays/production >/dev/null

if [[ "${mode}" == "local" ]]; then
  local_manifest="build/platform-local.yaml"
  required_local_values=(
    "https://github.com/eminent85/grafana-test.git"
    "path: clusters/local/*"
    "namespace: gitops-smoke"
    "clusterResourceWhitelist: []"
    "argocd.argoproj.io/managed-by: argocd"
  )
  for value in "${required_local_values[@]}"; do
    grep -Fq -- "${value}" "${local_manifest}" || {
      echo "error: local render is missing required value: ${value}" >&2
      exit 1
    }
  done

  if grep -Fq -- "namespace: '*'" "${local_manifest}"; then
    echo "error: local AppProject must not permit arbitrary destination namespaces" >&2
    exit 1
  fi
fi

if command -v yamllint >/dev/null; then
  yamllint operator platform clusters .github/workflows
else
  echo "warning: yamllint not installed; skipping YAML style validation" >&2
fi

if command -v kubeconform >/dev/null; then
  schema_args=(-schema-location default)
  if command -v yq >/dev/null; then
    mkdir -p .cache/schemas
    yq -o=json '.spec.versions[] | select(.name == "v1beta1") | .schema.openAPIV3Schema' \
      vendor/argocd-operator/crd/bases/argoproj.io_argocds.yaml > .cache/schemas/argocd-argoproj.io-v1beta1.json
    yq -o=json '.spec.versions[] | select(.name == "v1alpha1") | .schema.openAPIV3Schema' \
      vendor/argocd-operator/crd/bases/argoproj.io_applicationsets.yaml > .cache/schemas/applicationset-argoproj.io-v1alpha1.json
    yq -o=json '.spec.versions[] | select(.name == "v1alpha1") | .schema.openAPIV3Schema' \
      vendor/argocd-operator/crd/bases/argoproj.io_appprojects.yaml > .cache/schemas/appproject-argoproj.io-v1alpha1.json
    schema_args+=(-schema-location "file://${PWD}/.cache/schemas/{{.ResourceKind}}-{{.Group}}-{{.ResourceAPIVersion}}.json")
  else
    echo "warning: yq not installed; vendored custom-resource schemas will be skipped" >&2
  fi
  kubeconform -strict -summary -ignore-missing-schemas \
    "${schema_args[@]}" \
    "${manifests[@]}"
else
  echo "warning: kubeconform not installed; skipping schema validation" >&2
fi

if command -v conftest >/dev/null && [[ "${mode}" == "production" ]]; then
  conftest test "${manifests[@]}" --policy policy
elif command -v conftest >/dev/null; then
  echo "info: production policy checks do not apply to the intentionally non-TLS local ingress" >&2
else
  echo "warning: conftest not installed; skipping policy checks" >&2
fi

echo "validation passed"

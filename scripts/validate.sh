#!/usr/bin/env bash
set -euo pipefail

required=(kubectl)
for command in "${required[@]}"; do
  command -v "${command}" >/dev/null || { echo "error: ${command} is required" >&2; exit 1; }
done

kubectl kustomize operator/base >/dev/null
kubectl kustomize operator/overlays/local >/dev/null
kubectl kustomize platform/base >/dev/null
kubectl kustomize platform/overlays/local >/dev/null
kubectl kustomize platform/overlays/production >/dev/null

if command -v yamllint >/dev/null; then
  yamllint operator platform .github/workflows
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
    build/operator.yaml build/platform.yaml
else
  echo "warning: kubeconform not installed; skipping schema validation" >&2
fi

if command -v conftest >/dev/null; then
  conftest test build/operator.yaml build/platform.yaml --policy policy
else
  echo "warning: conftest not installed; skipping policy checks" >&2
fi

echo "validation passed"

# Argo CD Operator production template

This repository bootstraps an HA Argo CD control plane on a generic Kubernetes cluster with the community Argo CD
Operator. It intentionally separates the privileged bootstrap layer from the applications Argo CD manages.

## Architecture

The deployment has two ownership boundaries:

1. `operator/base/` installs the pinned operator CRDs and controller into `argocd-operator-system`. The operator watches only
   the `argocd` namespace.
2. `platform/` creates an `ArgoCD` instance, OIDC and repository secret integrations, restricted RBAC, ingresses,
   monitoring resources, and a root ApplicationSet. Production uses HA components; the Rancher Desktop overlay uses
   single replicas.

The production root ApplicationSet discovers `clusters/production/*`; the Rancher Desktop overlay discovers
`clusters/local/*` from `https://github.com/eminent85/grafana-test.git`. Do **not** put this repository's operator or
platform bootstrap packages below either path. Allowing Argo CD to prune its own operator creates an unsafe circular
dependency.

## Prerequisites

- Kubernetes 1.29 or newer with at least three schedulable worker nodes
- `kubectl` 1.29 or newer
- An ingress controller capable of HTTP and gRPC ingress
- cert-manager and a production `ClusterIssuer`
- External Secrets Operator and an existing `ClusterSecretStore`
- Prometheus Operator CRDs (`ServiceMonitor` and `PrometheusRule`)
- DNS records for the UI and gRPC hostnames
- An OIDC confidential client whose callback URI is `https://<ui-host>/auth/callback`

The operator webhook certificate uses a namespace-local self-signed cert-manager `Issuer`; the public UI certificate uses
the adopter-supplied `ClusterIssuer`.

## Configure

Edit `platform/overlays/production/production-config.yaml` and replace every `CHANGE_ME_*` value. Required inputs are:

| Setting | Purpose |
| --- | --- |
| UI and gRPC hosts | Public DNS names for browser and CLI traffic |
| Ingress class and ClusterIssuer | Public routing and certificate issuance |
| OIDC issuer/client ID/groups | Login and admin/read-only authorization |
| ClusterSecretStore and remote keys | OIDC and Git credential retrieval |
| Git URL, revision, root path | ApplicationSet source and discovery root |

The OIDC ExternalSecret merges `oidc.clientSecret` into the operator-created `platform-secret`. `creationPolicy: Merge`
means External Secrets will retry until that Secret exists; this avoids competing ownership of the operator's Secret.
The repository ExternalSecret creates an Argo CD repository credential Secret directly.

Resource requests are conservative production starting points, not capacity guarantees. Measure reconciliation duration,
repository render memory, API throttling, and Redis saturation, then tune the `ArgoCD` resource for your fleet size.

## Validate and deploy

```bash
make render
make preflight
make validate
make diff
make bootstrap
```

`make bootstrap` applies the operator first, waits for its controller, applies the platform package, and waits for the
`ArgoCD` resource to become available. Server-side apply is used for CRDs. Inspect current state later with `make status`.

### Rancher Desktop

For the single-node K3s cluster supplied by Rancher Desktop, use the local workflow:

```bash
make local-validate
make local-diff
make local-bootstrap
make local-status
```

The local overlay disables Redis HA, production PDBs, OIDC, External Secrets, Prometheus integration, and TLS. It exposes
the UI through Traefik at `http://argocd.localhost` and keeps the local admin account enabled for development. Do not use
the local overlay in a shared or production cluster.

The local root ApplicationSet anonymously polls the public `main` branch every three minutes and generates one Argo CD
Application for every Kustomize package below `clusters/local/`. Generated Applications prune resources removed from Git
and self-heal live drift. The initial `clusters/local/gitops-smoke` package writes a ConfigMap into the `gitops-smoke`
namespace and provides an end-to-end reconciliation check.

The operator, Argo CD instance, AppProject, ApplicationSet, and managed Namespace definitions remain bootstrap-owned and
must be applied with `make local-bootstrap` after they change. Argo CD owns only the contents below `clusters/local/`.
This avoids asking Argo CD to prune its own controller or operator.

### Add a local workload namespace

The local Argo CD instance is intentionally namespace-scoped. To onboard another namespace:

1. Add a Namespace manifest to `platform/overlays/local/` with the label `argocd.argoproj.io/managed-by: argocd`.
2. Add the namespace to the comma-separated `WATCH_NAMESPACE` allowlist in `operator/overlays/local/local-operator.yaml`.
3. Add that exact namespace to `AppProject/platform-workloads` in `local-gitops.yaml`; never add a wildcard destination.
4. Add a same-named package below `clusters/local/`, because the directory basename becomes the Application and namespace.
5. Merge and push the Git change, then run `make local-bootstrap` once to establish the namespace and its operator-managed
   RBAC. Subsequent changes inside that package reconcile automatically from Git.

The local cluster still requires cert-manager because the operator uses a namespace-local certificate for its webhook:

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.0 --namespace cert-manager --create-namespace \
  --set crds.enabled=true --set prometheus.enabled=false --wait
```

`make validate` and `make local-validate` always perform deterministic Kustomize renders. They additionally run `yamllint`
and `kubeconform` when installed. Production validation also runs `conftest`; the intentionally non-TLS local ingress is
excluded from the production-only policy. CI installs these tools and validates both overlays on every change.

## Identity and break-glass access

The local `admin` account is disabled and unauthenticated users receive `role:none`. OIDC groups are mapped explicitly to
`role:admin` and `role:readonly`. Validate group claims in a non-production environment before the first production cutover.

For break-glass recovery:

1. Make a reviewed, time-bounded Git change setting `spec.disableAdmin: false`.
2. Apply the platform overlay externally and obtain/reset the initial admin password with the Argo CD CLI.
3. Repair OIDC or RBAC.
4. Restore `disableAdmin: true`, apply, and confirm the admin login is rejected.
5. Record the incident and rotate any credentials exposed during recovery.

Do not keep a dormant admin password as a standing bypass.

## Upgrades and rollback

Operator inputs are vendored under `vendor/argocd-operator`; provenance and the archive checksum are in
`dependencies.yaml`. Renovate may open image updates, but control-plane changes are never auto-merged.

For every upgrade:

1. Read both operator and bundled Argo CD upgrade notes, including every skipped minor release.
2. Replace the vendored directories from the signed/tagged upstream archive and update the version, digest, URL, and
   checksum together.
3. Render and review the complete CRD/RBAC diff. Never downgrade CRDs blindly.
4. Run the disposable-cluster test in `docs/testing.md` and verify existing Applications and ApplicationSets.
5. Upgrade operator CRDs/controller before changing the `ArgoCD` custom resource.

Rollback the custom resource and controller image only when the installed CRDs remain backward compatible. If not, restore
to a fresh cluster from Git and the latest verified export rather than editing CRD schemas in place.

## Disaster recovery and removal

Git is the source of truth for projects, applications, and configuration. Back up external secret values in the secret
backend and schedule `ArgoCDExport` resources to provider-owned durable storage as described in `docs/disaster-recovery.md`.

To remove the installation, first disable/remove workload ApplicationSets without pruning business workloads, then delete
the `ArgoCD` resource and wait for its managed resources to disappear. Remove the operator last. CRD deletion is a separate,
explicit step because it deletes all corresponding custom resources cluster-wide.

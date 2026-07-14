# Argo CD Operator GitOps bootstrap

[![validate](https://github.com/eminent85/grafana-test/actions/workflows/validate.yaml/badge.svg)](https://github.com/eminent85/grafana-test/actions/workflows/validate.yaml)

This repository installs the community Argo CD Operator and uses it to create an Argo CD control plane. It provides two
Kustomize profiles:

- A configurable, high-availability production template for a generic Kubernetes cluster.
- A working single-node Rancher Desktop profile that continuously reconciles this repository's `clusters/local/*`
  packages from GitHub.

The design deliberately separates privileged bootstrap resources from workloads managed by Argo CD. The operator, Argo CD
custom resource, root AppProject, root ApplicationSet, and approved Namespace definitions are applied externally. Argo CD
owns only the workload packages discovered below `clusters/<environment>/`.

## Scope and ownership

| Layer | Contents | Owner | Update mechanism |
| --- | --- | --- | --- |
| Operator | Vendored CRDs, controller, cluster RBAC, conversion webhook, certificate, and availability settings | Bootstrap administrator | `make bootstrap` or `make local-bootstrap` |
| Platform | Argo CD instance, ingress, identity, repository integration, AppProject, ApplicationSet, PDBs, and monitoring options | Bootstrap administrator and Argo CD Operator | Bootstrap command, then operator reconciliation |
| Workloads | Kustomize packages below `clusters/<environment>/*` | Argo CD | Automated Git polling, sync, self-heal, and prune |
| Secrets | OIDC and repository credentials in production | External Secrets Operator and the external secret backend | External secret refresh |

The root ApplicationSet creates one Application per immediate child directory. The directory basename becomes both the
Application name and its destination namespace. Generated Applications use server-side apply, create approved namespaces
when permitted, retry transient failures, self-heal live drift, and prune resources removed from Git. `allowEmpty: false`
prevents an empty render from deleting an entire Application.

Do not place `operator/` or `platform/` below an ApplicationSet discovery path. Allowing Argo CD to prune its own operator
or control plane creates a circular dependency and complicates recovery.

## Deployment profiles

| Capability | Production template | Rancher Desktop |
| --- | --- | --- |
| Kubernetes topology | Three or more schedulable workers | Single-node K3s |
| Operator | Two replicas with preferred anti-affinity and a PDB | One replica; watches only `argocd` and `gitops-smoke` |
| Argo CD | HA Redis, three server and repo replicas, two notification replicas, production PDBs | Single replicas, non-HA Redis, no production PDBs |
| Authentication | OIDC groups; built-in admin disabled | Built-in admin enabled; no OIDC |
| Repository | Configurable repository and revision with External Secrets credentials | Public `https://github.com/eminent85/grafana-test.git`, branch `main`, anonymous access |
| Application discovery | Configurable path, default template `clusters/production/*` | `clusters/local/*`, polled every three minutes |
| Authorization | Template starts broad and must be narrowed for its adopters | Only the `gitops-smoke` namespace; no cluster-resource whitelist |
| Ingress | Separate TLS HTTP and gRPC ingresses | Traefik HTTP ingress at `http://argocd.localhost` |
| Observability | Prometheus integration and monitoring enabled | Disabled |
| External Secrets | Required for OIDC and Git credentials | Removed from the rendered profile |

Strict TLS verification between Argo CD components and the operator-generated repo-server certificate is disabled only in
the local profile because that self-signed certificate does not contain the generated Kubernetes Service DNS name. HTTPS
certificate verification for GitHub remains enabled.

## Repository layout

| Path | Purpose |
| --- | --- |
| `operator/base/` | Production operator assembly and patches for namespace scope, resources, availability, and webhook TLS |
| `operator/overlays/local/` | Single-replica operator plus the exact local namespace watch allowlist |
| `platform/base/` | Argo CD custom resource, namespace, ExternalSecrets, AppProject, ApplicationSet, and PDBs |
| `platform/overlays/production/` | Required production endpoints, OIDC, secret-store, and Git substitutions |
| `platform/overlays/local/` | Traefik/local-admin settings, production-resource removals, local project restrictions, and namespace bootstrap |
| `clusters/local/gitops-smoke/` | Git-managed ConfigMap used for end-to-end reconciliation, drift, and prune tests |
| `vendor/argocd-operator/` | Pinned upstream operator manifests used without OLM |
| `dependencies.yaml` | Kubernetes minimum, cert-manager chart, operator source/checksum, and image digest provenance |
| `policy/production.rego` | Conftest rules rejecting mutable `latest` images, plaintext `Secret.stringData`, and non-TLS ingresses |
| `scripts/` and `Makefile` | Rendering, preflight, validation, diff, bootstrap, and readiness workflows |
| `docs/` | Production adoption suggestions, acceptance tests, and disaster-recovery guidance |
| `.github/workflows/validate.yaml` | Pull-request and `main` validation for production and local renders |
| `renovate.json` | Dependency discovery; operator upgrades require review and end-to-end testing |

Generated manifests are written to the ignored `build/` directory. Schema files generated during validation are written to
the ignored `.cache/` directory.

## What is not included

- No Grafana workload is deployed; the repository name does not describe its current contents.
- No production workload package is checked in under `clusters/production/`; the production ApplicationSet targets the
  repository and path supplied by its adopter.
- OLM is not installed or used. The pinned operator manifests are applied directly with Kustomize.
- Production prerequisites, DNS, OIDC clients, secret-backend values, and public certificates are not provisioned here.
- The local profile polls Git. It does not expose an ApplicationSet webhook or install Argo CD Image Updater.
- Multi-cluster registration, application-specific policies, provider-specific backups, and secret-store backups remain
  adopter responsibilities.

## Versions and prerequisites

The pinned dependency record currently specifies:

- Kubernetes 1.29 or newer.
- cert-manager v1.21.0.
- Argo CD Operator v0.15.0-1, with its source archive checksum and controller image pinned by digest.

All profiles require Bash, GNU Make, GNU grep, `kubectl`, and cert-manager because the scripts use Bash/GNU grep and the
operator conversion webhook uses a namespace-local self-signed cert-manager `Issuer` and `Certificate`. Installation
requires cluster-admin or equivalent privileges for CRDs, namespaces, cluster RBAC, and the operator controller. Every Make
target uses the current kubeconfig context; no target selects or changes a context for you.

Production additionally requires:

- At least three schedulable worker nodes.
- An ingress controller capable of separate HTTP and gRPC ingresses.
- A production cert-manager `ClusterIssuer` and public DNS for both endpoints.
- External Secrets Operator and an existing `ClusterSecretStore`.
- Prometheus Operator CRDs, including `ServiceMonitor` and `PrometheusRule`.
- An OIDC confidential client with callback URI `https://<ui-host>/auth/callback`.
- An external secret backend containing the OIDC client secret and Git credentials.

This repository does not install those production prerequisites. For Rancher Desktop, install cert-manager if it is not
already present:

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.0 --namespace cert-manager --create-namespace \
  --set crds.enabled=true --set prometheus.enabled=false --wait
```

## Production configuration and deployment

Replace every `CHANGE_ME_*` value in `platform/overlays/production/production-config.yaml`:

| Setting | Purpose |
| --- | --- |
| UI and gRPC hosts | Public browser and CLI endpoints |
| Ingress class and ClusterIssuer | Routing and public certificate issuance |
| OIDC issuer, client ID, and groups | Login and admin/read-only role mapping |
| ClusterSecretStore and remote keys | Retrieval of OIDC and Git secrets |
| Git URL, revision, and root path | ApplicationSet source and directory discovery |

The OIDC ExternalSecret merges `oidc.clientSecret` into the operator-created `platform-secret`; External Secrets retries
until that Secret exists. The repository ExternalSecret owns a labeled Argo CD repository Secret. No credentials belong in
Git or rendered manifests.

Render, validate, review, and deploy:

```bash
make render
make preflight
make validate
make diff
make bootstrap
make status
```

`make preflight` fails on unresolved placeholders or likely plaintext credentials. `make bootstrap` applies the operator
CRDs and controller first, waits for its rollout, applies the platform with server-side apply, and waits for the Argo CD
resource to reconcile and become Available.

The production AppProject in this template permits every destination namespace and cluster resource so adopters can model
their required platform workloads. This Argo CD policy does not grant Kubernetes RBAC. The production operator watches only
`argocd` by default, so adopters must choose and configure a namespace permission model before enabling workloads: either
extend an explicit namespace watch/label allowlist as the local profile does, or deliberately configure a cluster-scoped
Argo CD instance. Narrow the AppProject lists, split projects by trust boundary, and review the
[production adoption suggestions](docs/suggestions.md) before using the profile with untrusted repositories or teams.

Production also retains strict TLS verification between Argo CD components and the repo server. A generic-cluster adopter
must provide a repo-server certificate trusted by the components and valid for the generated Kubernetes Service DNS name.
The local profile's `verifytls: false` override is a development compromise, not a production default.

Resource requests are conservative starting points rather than capacity guarantees. Measure reconciliation duration,
repository-render memory, API throttling, controller queues, and Redis saturation before adjusting replicas, processors, or
sharding.

## Rancher Desktop workflow

The checked-in local profile is intended for the `rancher-desktop` context and is configured for the public `main` branch.
Confirm the active context before any diff or bootstrap command:

```bash
kubectl config current-context
```

Continue only when it prints `rancher-desktop`:

```bash
make local-validate
make local-diff
make local-bootstrap
make local-status
```

The first `local-diff` reports that server-side diff is unavailable until the bootstrap namespaces and Argo CD CRDs exist.
After bootstrap it shows ordinary server-side changes. `local-bootstrap` is idempotent and uses force-conflicts for the
bootstrap-owned fields that Kubernetes controllers may default.

The local ApplicationSet discovers `clusters/local/gitops-smoke`. Its ConfigMap proves that the ApplicationSet can read the
public repository and that Argo CD can render and sync into the allowlisted namespace. `make local-status` waits for the
operator, Argo CD control plane, generated Application, and smoke ConfigMap.

The local operator, Argo CD instance, AppProject, ApplicationSet, and Namespace remain bootstrap-owned. Re-run
`make local-bootstrap` after changing them. Changes confined to `clusters/local/gitops-smoke/` reconcile automatically after
they are pushed to `main`.

### Add a local workload namespace

The local profile deliberately uses a named namespace allowlist. To add another workload:

1. Add a Namespace manifest under `platform/overlays/local/` with label `argocd.argoproj.io/managed-by: argocd`.
2. Add the namespace to `resources` in the local platform Kustomization.
3. Add the namespace to the comma-separated `WATCH_NAMESPACE` value in `operator/overlays/local/local-operator.yaml`.
4. Add the exact namespace to `AppProject/platform-workloads` in `platform/overlays/local/local-gitops.yaml`; do not use a
   wildcard.
5. Add a same-named Kustomize package below `clusters/local/` because its basename becomes the Application and namespace.
6. Push the change and run `make local-bootstrap` once to create the namespace and operator-managed Roles and RoleBindings.

Subsequent changes within the workload package are Git-managed. Namespace approval and RBAC remain explicit bootstrap
operations.

## Validation and CI

`make validate` checks the production render; `make local-validate` checks Rancher Desktop. Both always perform deterministic
Kustomize renders and preflight checks. When installed, the validation script also runs:

- `yamllint` over operator, platform, workload, and workflow YAML.
- `kubeconform` with schemas extracted from the vendored Argo CD CRDs.
- `conftest` against the production render. The intentionally non-TLS local ingress is excluded from production-only policy.

GitHub Actions pins kubectl 1.34.2, kubeconform 0.7.0, conftest 0.62.0, yq 4.47.2, and yamllint 1.37.1. It replaces production
placeholders only in generated CI output, then validates both profiles on pull requests and pushes to `main`.

The complete [disposable-production and Rancher Desktop acceptance scenarios](docs/testing.md) cover identity, repository
access, health, self-healing, pruning, namespace denial, failover, secret rotation, and upgrade/rollback behavior.

## Identity and security model

Production disables the built-in `admin` account, assigns unauthenticated users `role:none`, and maps configured OIDC groups
to `role:admin` and `role:readonly`. Validate actual group claims in a non-production environment before cutover.

The local profile enables built-in admin for development but retains `role:none` as the default RBAC policy. It must not be
used as a shared or production control plane.

For production break-glass access:

1. Make a reviewed, time-bounded change setting `spec.disableAdmin: false`.
2. Apply the production platform overlay externally and obtain or reset the admin password with the Argo CD CLI.
3. Repair OIDC or RBAC.
4. Restore `disableAdmin: true`, reapply, and confirm admin authentication is rejected.
5. Record the incident and rotate credentials exposed during recovery.

Do not keep a dormant admin password as a standing bypass. Additional production hardening intentionally left to adopters—
including NetworkPolicies, admission controls, image mirroring, workload identity, alert routing, and sync windows—is listed
in the [production adoption suggestions](docs/suggestions.md).

## Upgrades, recovery, and removal

Operator inputs are vendored under `vendor/argocd-operator/`; version, archive checksum, source URL, and image digest are
recorded in `dependencies.yaml`. Renovate can propose image changes but cannot auto-merge Argo CD control-plane upgrades.

For every upgrade:

1. Read the operator and bundled Argo CD upgrade notes, including skipped minor versions.
2. Replace the vendored inputs from the tagged upstream release and update all provenance fields together.
3. Render and review the full CRD and RBAC diff; do not blindly downgrade CRDs.
4. Run the applicable [disposable-cluster acceptance test](docs/testing.md).
5. Upgrade operator CRDs/controller before changing the `ArgoCD` resource.

Rollback the custom resource and controller only when installed CRDs remain backward compatible. Otherwise restore to a
fresh cluster from Git and a verified export instead of editing CRD schemas in place.

The [recovery model](docs/disaster-recovery.md) uses Git for declarative state, the external backend for credentials, and
scheduled `ArgoCDExport` data copied to encrypted provider-owned storage outside the cluster. This repository does not
implement provider-specific export scheduling, object-storage transfer, or secret-backend backups.

For removal, first disable or remove workload ApplicationSets without pruning business workloads. Delete the `ArgoCD`
resource and wait for operator-managed components to disappear, then remove the operator. CRD deletion is a separate,
explicit operation because it deletes every corresponding custom resource cluster-wide.

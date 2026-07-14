# Disposable-cluster acceptance test

Use a three-node disposable cluster that resembles production and install cert-manager, External Secrets Operator,
Prometheus Operator, and the selected ingress controller first.

1. Configure the production overlay with test DNS, OIDC, secret store, and a repository containing one
   `clusters/production/sample` Kustomize package.
2. Run `make validate`, `make bootstrap`, and `make status`.
3. Confirm two operator replicas run on different nodes and all Argo CD pods are ready.
4. Confirm the server, repo server, ApplicationSet controller, notifications controller, Redis HA pods, PDBs,
   ServiceMonitors, and PrometheusRules exist.
5. Log in through OIDC as an administrator and reader. Confirm the reader cannot sync, update, or delete applications.
   Confirm local admin authentication fails.
6. Log in with the CLI through the gRPC hostname and confirm certificate validation succeeds.
7. Confirm the sample Application is created, synced, and healthy. Modify a live managed object and confirm self-healing.
8. Add then remove a disposable manifest in Git and confirm creation and foreground pruning. Never use business workloads
   for prune testing.
9. Drain one worker node. Confirm PDBs retain quorum and the UI, repository rendering, reconciliation, and Redis remain
   available.
10. Rotate the Git and OIDC credentials in the external backend and confirm External Secrets refreshes them without a
    plaintext Git change.
11. Test the proposed operator/Argo CD upgrade, observe reconciliation through completion, then exercise the documented
    rollback while the cluster remains disposable.

Acceptance requires no unresolved placeholders, mutable operator image, plaintext credential, deprecated API warning,
unavailable control-plane endpoint, or unintended prune.

## Rancher Desktop GitOps acceptance test

Use the `rancher-desktop` context and keep the bootstrap boundary separate from Git-managed workloads.

1. Push the proposed `clusters/local/gitops-smoke` package and local overlay changes to `main`.
2. Run `make local-validate`, review `make local-diff`, and run `make local-bootstrap`.
3. Confirm `Application/gitops-smoke` is `Synced` and `Healthy`, then confirm `ConfigMap/gitops-smoke` exists in its
   namespace. `make local-status` performs these checks.
4. Change the ConfigMap value in Git and confirm the cluster receives it within two three-minute polling intervals.
5. Patch the live ConfigMap and confirm self-healing restores the Git value.
6. Add a disposable second ConfigMap in one commit, remove it in a later commit, and confirm foreground pruning deletes it.
7. Submit an Application that targets a namespace absent from the AppProject allowlist and confirm Argo CD rejects it.

Acceptance requires anonymous repository access, an operator cache limited to approved namespaces, no cluster-resource
permission, no wildcard destination namespace, and no Argo CD ownership of operator or control-plane bootstrap resources.

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


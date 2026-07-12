# Production adoption suggestions

- Replace the broad AppProject destination and cluster-resource wildcard with per-team projects and least-privilege
  allowlists before onboarding untrusted repositories.
- Add Kubernetes NetworkPolicies after mapping the ingress, DNS, Kubernetes API, Git, OIDC, Redis, and Prometheus traffic
  required by your chosen CNI. A generic deny policy is deliberately omitted because incorrect egress rules can stop all
  reconciliation.
- Configure admission policy to require signed images, non-root containers, read-only root filesystems, and approved
  registries across application namespaces.
- Mirror operator and Argo CD images into a controlled registry and pin every image by digest for restricted or regulated
  environments.
- Use workload identity for external-secret backend access and short-lived Git credentials where the provider supports it.
- Add alert routing for reconciliation errors, out-of-sync applications, unavailable replicas, Redis failures, certificate
  expiry, ExternalSecret failures, and unusually long repository rendering.
- Establish sync windows, change freezes, and manual approval for high-risk namespaces. Automated pruning should be enabled
  only where repository ownership and review controls are mature.
- Track API server load and controller queue depth as the number of clusters and resources grows; add sharding only after
  measuring a bottleneck.


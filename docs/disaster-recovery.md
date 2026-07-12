# Disaster recovery

## Backup model

- Keep all Applications, ApplicationSets, AppProjects, RBAC, and Argo CD configuration in reviewed Git.
- Back up OIDC, Git, notification, signing, and repository credentials in the external secret backend with independent
  retention and audit controls.
- Create a scheduled `ArgoCDExport` for the `platform` instance and copy the resulting export to encrypted, versioned,
  provider-owned object storage. The storage transfer mechanism is intentionally provider-specific and is not included in
  this generic template.
- Test restore quarterly and before control-plane upgrades.

## Restore procedure

1. Provision a compatible cluster and prerequisite controllers.
2. Restore external secret backend access, but do not expose application credentials to bootstrap automation.
3. Apply `operator/base`, wait for its controller, then apply the configured platform overlay.
4. Restore the latest verified `ArgoCDExport` only if state not represented in Git is required.
5. Verify OIDC/RBAC and repository access before enabling the root ApplicationSet.
6. Enable workload reconciliation in waves and inspect every prune proposal.
7. Rotate control-plane credentials after the recovery and record recovery point/time objectives.

An export is not a substitute for Git or external-secret backups. Keep backups outside the managed cluster and validate
that the restore tooling can read them without relying on the failed cluster.

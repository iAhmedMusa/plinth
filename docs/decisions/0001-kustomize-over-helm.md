# 0001. Kustomize over Helm for environment overlays

## Context

`k8s/` needs to run the same application across four environments
(local, staging, production, ci) that differ only in namespace, image
tag source, and (for production) replica count.

## Decision

Use Kustomize: one `base/` plus a thin overlay per environment
(`k8s/overlays/{local,staging,production,ci}`). No Helm chart exists
anywhere in this repo.

## Alternatives considered

- **Helm charts with per-env values files.** A templating engine gives
  loops, conditionals, and a packaged/versioned release unit. Rejected
  because none of that power is needed here — the differences between
  environments are a handful of scalar values (namespace, tag, replica
  count), not structural. Helm would also add a templating language on
  top of plain YAML and a release-state concept (`helm upgrade`,
  `helm rollback`) this repo doesn't otherwise need.
- **Separate, duplicated manifests per environment.** No abstraction at
  all. Rejected outright — four copies of every Deployment/Service
  drift the moment one is edited and the others aren't.

## Consequences

Overlays stay plain, diffable YAML — `kubectl kustomize <overlay>` shows
exactly what will be applied, with no template rendering step to reason
about. The tradeoff is Kustomize's weaker expressiveness: no loops, no
conditionals, no packaging/versioning story. If per-environment
differences ever grow past simple patches (e.g. genuinely different
resource sets per environment, not just different values), Kustomize's
patch-based model gets harder to read than a templated one, and that
would be the point to revisit this decision.

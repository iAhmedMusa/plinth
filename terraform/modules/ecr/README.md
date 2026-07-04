# ecr module

## Purpose

One ECR repository per app image (backend, frontend), immutable tags,
scan-on-push, a lifecycle policy that bounds storage growth.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Prefix applied to every repository name | (required) |
| `repository_names` | Short names, full name is `name_prefix-<name>` | `["backend", "frontend"]` |
| `tags` | Common tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `repository_urls` | Map of short name -> repository URL |
| `repository_arns` | Map of short name -> repository ARN |

## Design notes

- **`IMMUTABLE` tag mutability** is the direct ECR equivalent of the
  pipeline's existing no-`latest` policy on Docker Hub (docs/ci-cd.md,
  section 3): a tag can never be overwritten once pushed, so it always
  points at exactly one image, forever — no floating tag can silently
  change under a running deployment.
- **`scan_on_push`** runs Amazon's own image scanning on every push, in
  addition to (not instead of) the Trivy scan already in the pipeline —
  belt and suspenders, and it catches drift if the pipeline scan step is
  ever skipped or misconfigured.
- **Lifecycle policy** keeps the last 20 tagged (`v*`) images — enough
  history to roll back several releases — and expires untagged images
  after 7 days, since those are dangling layers from superseded builds
  that nothing running ever references.

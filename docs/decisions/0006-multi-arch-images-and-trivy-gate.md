# 0006. Multi-arch images + Trivy gate in the release path

## Context

The release pipeline needs to build and publish production images, and
should catch known vulnerabilities before they ship rather than after.

## Decision

`build-and-push` uses `docker/build-push-action` with
`platforms: linux/amd64,linux/arm64` (via `docker/setup-qemu-action` +
buildx), so every published image runs on either architecture. Each
image is immediately scanned with `aquasecurity/trivy-action`
(`severity: "CRITICAL,HIGH"`), with results uploaded as a build
artifact. The scan runs with `exit-code: "0"` — report-only, it never
blocks a release.

## Alternatives considered

- **amd64-only builds.** Faster, simpler CI (no QEMU emulation
  overhead). Rejected because it's a portability problem that only
  surfaces later — if this ever deploys to arm64 nodes (Graviton, for
  cost), the image silently doesn't run there, discovered at deploy
  time instead of build time.
- **Trivy with `exit-code: "1"` (hard-block on any CRITICAL/HIGH
  finding).** Rejected *for now*, specifically because there is no
  maintained `.trivyignore` allowlist yet. A hard gate without a triage
  process either blocks every release on some unavoidable base-image
  CVE, or trains people to route around it — worse than an honest
  report-only gate.

## Consequences

Multi-arch roughly doubles build time (two platforms, one emulated via
QEMU) for a repo with no current arm64 deployment target — a cost paid
now to avoid a portability surprise later. The scan is currently
advisory: a finding is visible in the uploaded artifact but does not
stop a bad image from shipping. Turning this into a real gate is a
two-part follow-up, not a one-line flag flip: `exit-code: "1"` plus a
maintained `.trivyignore` for accepted findings, tracked as an open item
rather than silently assumed to already exist.

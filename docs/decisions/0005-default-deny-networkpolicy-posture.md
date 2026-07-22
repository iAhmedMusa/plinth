# 0005. Default-deny NetworkPolicy posture

## Context

The security-group boundary (ADR-0003) only answers "which machines" —
every pod on an EKS node shares that node's network identity, so an SG
rule alone can't stop a compromised frontend pod from opening a
connection to the database if nothing else is in the way.

## Decision

`k8s/base/network-policies.yaml` applies `default-deny-ingress` (an
empty `podSelector`, `Ingress` only) to every pod in the namespace, then
layers explicit allow rules on top: `ingress-nginx` → frontend:3000
only, frontend → backend:8080 only, backend → postgres:5432 only. A
pod gets exactly the ingress this file grants it and nothing else.

## Alternatives considered

- **Allow-all with targeted deny rules where needed.** Rejected because
  it fails open: a new Service or pod added later is reachable from
  everything in the namespace until someone remembers to add a deny
  rule for it. Default-deny fails closed instead — a forgotten policy
  means a new component can't be reached by anything, a much safer
  failure mode to discover in testing.
- **A service mesh (Istio/Linkerd) with mTLS-based authorization.**
  More powerful — identity-based rather than label-based, encrypts
  pod-to-pod traffic. Rejected as a new control-plane dependency not
  justified at this scale; label-based NetworkPolicy already gives the
  isolation this app needs without a sidecar-per-pod operational cost.

## Consequences

Every new component needs an explicit allow rule before it can be
reached by anything — more YAML upfront, but no silent gaps as the
manifest set grows. Egress is deliberately left unrestricted (the
comment at the top of `network-policies.yaml` explains why): writing
egress rules too would mean carving out DNS and any external call
(image registry, AWS APIs) for every pod, a real maintenance cost that
isn't justified by this app's actual threat model. A stricter posture
that also default-denies egress is the natural next step if this ever
needs to defend against a compromised pod exfiltrating data outward,
not just being reached from elsewhere.

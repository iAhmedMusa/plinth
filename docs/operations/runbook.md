# Runbook

Fifteen real-world failure scenarios. Each entry follows the same shape:
**Symptom → Triage commands → Likely causes → Fix → Prevention.**

---

## 1. Pods stuck in `CrashLoopBackOff`

**Symptom:** A pod repeatedly restarts and never reaches `Ready`.

**Triage commands:**
```bash
kubectl logs <pod-name> --previous   # logs from the crashed container
kubectl describe pod <pod-name>      # last state + exit code
```

**Likely causes:**
- Application fails to start (missing env var, bad DATABASE_URL, port
  conflict).
- Readiness probe fires before the app is ready — the container starts,
  fails the probe, gets restarted before it can serve.
- OOMKilled: the container exceeded its memory limit (`describe` shows
  `Reason: OOMKilled`). Increase `resources.limits.memory` or fix a
  memory leak.

**Fix:** Read the logs first. The exit code tells you everything — exit 1
is an application error, exit 137 is SIGKILL (OOM or manual kill).

**Prevention:** Run the app's own smoke tests (`pytest`, `npm run build`)
in CI before every deploy, and keep `readinessProbe.initialDelaySeconds`
generous enough for real startup time rather than tuning it against a
warm local machine.

---

## 2. Pods in `ImagePullBackOff`

**Symptom:** A pod stays `Pending`/`ImagePullBackOff` and never starts.

**Triage commands:**
```bash
kubectl describe pod <pod-name> | grep -A5 "Events"
```

**Likely causes:**
- Typo in the image name or tag (e.g. `plinth-backend:0.1.0`
  vs `plinth-backend:0.1.O`).
- Image doesn't exist in the registry — the tag was never pushed, or
  the CI pipeline that builds it hasn't run yet.
- `imagePullSecrets` missing or misconfigured for private registries.

**Fix:** Verify the image exists:
```bash
docker manifest inspect <registry>/<image>:<tag>
```

**Prevention:** Images are already tagged with immutable semver + short
SHA (never `latest`) — always verify with `docker manifest inspect`
before merging an overlay change that references a new tag, not after.

---

## 3. Application is unreachable from the browser

**Symptom:** The frontend URL times out or returns a connection error.

**Triage commands (in order):**
```bash
kubectl get ingress                     # is the Ingress object created?
kubectl get pods -n ingress-nginx       # is the controller running?
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=50
curl -H "Host: plinth.localtest.me" http://<ingress-ip>/   # direct hit
```

**Likely causes:**
- Ingress controller not installed or not ready — apply the
  ingress-nginx manifest and wait for the pod to become `Ready`.
- Host header mismatch — the browser sends a host that doesn't match
  any Ingress rule.
- Ingress class annotation missing (`ingressClassName: nginx`).

**Fix:** Work backwards from the Ingress object: does the controller see
it? Does the controller's nginx config include your host? Does DNS
resolve the host to the ingress IP?

**Prevention:** `kubectl apply -k <overlay> --dry-run=client` in CI
catches a missing ingress class or host mismatch before it ever reaches
a real cluster.

---

## 4. Backend returns 502 Bad Gateway

**Symptom:** The frontend loads but every API call returns 502.

**Triage commands:**
```bash
kubectl logs deploy/frontend --tail=50   # Next.js proxy logs
kubectl logs deploy/backend --tail=50    # backend app logs
kubectl get svc backend                  # does the Service exist?
kubectl get endpoints backend            # does it have ready addresses?
```

**Likely causes:**
- Backend pod is not `Ready` (failing health checks) — the Service has
  no endpoints, so the frontend's proxy gets connection refused.
- Backend port mismatch — Service `targetPort` doesn't match the
  container's `containerPort`.
- NetworkPolicy blocking the frontend→backend path.

**Fix:** Check `kubectl get endpoints backend` first. If empty, the
backend pods aren't passing readiness probes — fix the probe config or
the app itself.

**Prevention:** Keep readiness probes strict (fail fast on a broken
dependency) so an unready backend pod never gets a Service endpoint in
the first place — a lenient probe just delays this exact symptom.

---

## 5. Database connection timeout

**Symptom:** The backend logs connection timeouts to `db`/RDS.

**Triage commands:**
```bash
kubectl exec deploy/backend -- python -c "
import socket
s = socket.create_connection(('db', 5432), timeout=5)
print('connected')
" 2>&1 || echo "TIMEOUT"
```

**Likely causes:**
- Database pod not running (`kubectl get pods -l app.kubernetes.io/name=postgres`).
- `DATABASE_URL` env var points to the wrong host/port.
- Security group (cloud) or NetworkPolicy (cluster) blocking port 5432.
- Database container is healthy but the application tries to connect
  before the database is ready.

**Fix:** Test connectivity from inside the backend pod. If the socket
connects but authentication fails, the credentials are wrong. If the
socket times out, it's a network/availability issue.

**Prevention:** Compose's `depends_on: condition: service_healthy` and
the backend's own readiness probe already sequence startup — don't
relax either one to "fix" a slow environment; fix the environment.

---

## 6. SSL certificate errors in the browser

**Symptom:** The browser shows an invalid/expired certificate warning.

**Triage commands:**
```bash
kubectl get certificate -A               # cert-manager objects
kubectl describe certificate <name>      # issuance status
kubectl logs -n cert-manager deploy/cert-manager --tail=50
```

**Likely causes:**
- cert-manager not installed or not configured with a ClusterIssuer.
- DNS not pointing to the ingress — Let's Encrypt can't reach the
  domain to complete the HTTP-01 challenge.
- Rate limiting — too many certificate requests for the same domain.
- Expired certificate — cert-manager's renewal failed silently.

**Fix:** Check `kubectl describe certificate` — the `Status` field tells
you exactly what went wrong. For Let's Encrypt, the challenge pod
(`kubectl get pods -n cert-manager`) must complete successfully.

**Prevention:** Alert on `Certificate` resources sitting in `Ready:
False` for more than ~10 minutes, instead of waiting for a user to
report the browser warning.

---

## 7. CI pipeline fails at the build step

**Symptom:** The `test-backend`/`test-frontend` or build job fails.

**Triage commands:**
- Open the failed GitHub Actions run and read the step output.

**Likely causes:**
- `npm ci` fails because `package-lock.json` is out of sync with
  `package.json` — run `npm install` locally and commit the lock file.
- Docker build fails because a file referenced in `COPY` or `ADD` is
  missing — check `.dockerignore` isn't excluding something the
  Dockerfile needs.
- Build cache miss causes the build to time out on large dependencies.

**Fix:** Reproduce locally first:
```bash
docker build --no-cache ./backend
docker build --no-cache ./frontend
```

**Prevention:** Commit `package-lock.json` alongside every
`package.json` change; treat lockfile drift as a merge-blocking CI
failure rather than something to `npm install` around later.

---

## 8. CI pipeline fails at the deploy step

**Symptom:** The `deploy-staging` job fails after build-and-push succeeds.

**Triage commands:**
```bash
# In the GitHub Actions log, look for:
kubectl apply -k k8s/overlays/ci --dry-run=client -o yaml
```

**Likely causes:**
- `kustomize edit set image` references a repository name that doesn't
  match what was pushed (case sensitivity, missing namespace prefix).
- The kind cluster creation failed silently — ingress-nginx install
  times out.
- The namespace in the overlay doesn't match what `kubectl rollout
  status` expects.

**Fix:** The pipeline's "Dump diagnostics on failure" step (running in
the `deploy-staging` job) dumps pod status, describe, and logs. Start
there.

**Prevention:** Keep "Dump diagnostics on failure" wired to every deploy
job — a failure that already explains itself is the cheapest kind to
fix.

---

## 9. Secrets accidentally pushed to GitHub

**Symptom:** A credential, token, or key shows up in a commit diff.

**Immediate response:**

1. **Rotate the secret immediately** — don't wait, don't investigate
   first. If it's a Docker Hub token, revoke and regenerate. If it's a
   cloud key, disable it.
2. **Check if the secret was accessed** — GitHub audit log, Docker Hub
   activity log, CloudTrail for AWS keys.
3. **Revert the commit** — `git revert <commit>` (don't force-push to
   hide history; that's worse).
4. **Add the secret to `.gitignore`** so it can't be re-added.
5. **Scan for other secrets** — run `git log -p --all -- '*.env' '*.yaml'
   '*.yml'` to check for other accidental exposures.

**Prevention:** Use `gitleaks` or `trufflehog` as a pre-commit hook and
in CI. This repo already has `.env` in `.gitignore` — enforce it with a
CI check that fails if any `.env` file is tracked.

---

## 10. Pod evicted by node pressure (OOMKilled / disk pressure)

**Symptom:** A pod disappears and reschedules elsewhere with no crash
loop in its own logs.

**Triage commands:**
```bash
kubectl get pods --field-selector=status.phase=Failed -o wide
kubectl describe node <node-name> | grep -A10 "Conditions"
kubectl top pods                        # current memory usage
```

**Likely causes:**
- Container memory limit too low — the app legitimately needs more
  than allocated.
- Node running too many pods — no headroom for scheduling.
- Memory leak — usage grows until the limit is hit.

**Fix:** Check `kubectl top pods` to see actual vs. limit usage. If
actual usage is close to the limit, increase the request/limit. If it's
a leak, fix the code.

**Prevention:** Right-size requests/limits from `kubectl top pods`
history before raising replica counts — set limits from observed data,
not a guess, so this doesn't happen in the first place.

---

## 11. Terraform plan shows unwanted resource replacement

**Symptom:** `terraform plan` shows `-/+` (destroy and recreate) on a
resource you only meant to update.

**Triage commands:**
```bash
terraform plan -var-file=envs/production.tfvars 2>&1 | grep -E "(-/\+|~)"
```

**Likely causes:**
- A resource attribute changed that is `ForceNew` (e.g. EKS cluster
  `name`, RDS `engine`).
- A provider upgrade changed `ForceNew` behavior on a previously-mutable
  field.
- A resource was renamed in the Terraform config — Terraform sees
  delete+create instead of in-place update.
- Drift from manual changes made outside Terraform (console clicks).

**Fix:** Read the plan output carefully — it names the specific field
that forces replacement. If it's a rename, use `terraform state mv`. If
it's drift, import the manual change or revert it.

**Prevention:** `prevent_destroy` (already set on EKS and RDS) is the
backstop, not the first line of defense — always read the `-/+` lines in
plan output before approving an apply, in CI or by hand.

---

## 12. Kustomize overlay applies wrong image tag

**Symptom:** A newly deployed pod is running an unexpected image
version.

**Triage commands:**
```bash
kubectl kustomize k8s/overlays/staging | grep "image:"
kubectl kustomize k8s/overlays/production | grep "image:"
```

**Likely causes:**
- The overlay's `kustomization.yaml` `images:` transformer references
  the wrong repository or tag.
- CI's `kustomize edit set image` command targets the wrong overlay
  directory.
- Base manifest uses a hardcoded image instead of the `PLACEHOLDER`
  convention — the overlay transformer can't rewrite it.

**Fix:** Always verify with `kubectl kustomize <overlay> | grep
image:` before applying. The base manifests use
`PLACEHOLDER/plinth-{backend,frontend}:0.0.0` — never edit these
directly; the overlay rewrites them.

**Prevention:** `kubectl kustomize <overlay> | grep image:` is already
a cheap check point — never skip it before merging an overlay change.

---

## 13. Frontend build fails with "BACKEND_URL" not set

**Symptom:** `npm run build` (or the CI build step) fails during the
Next.js build.

**Triage commands:**
```bash
cd frontend && npm run build 2>&1 | head -20
```

**Likely causes:**
- The `BACKEND_URL` env var isn't passed during `docker build` or `npm
  run build`.
- The Next.js `rewrites()` function in `next.config.ts` reads
  `BACKEND_URL` at build time — if it's missing, the build fails
  because the rewrite destination can't be resolved.

**Fix:** Pass `BACKEND_URL` as a build arg or env var at build time:
```bash
docker build --build-arg BACKEND_URL=http://backend:8080 ./frontend
```

**Prevention:** `BACKEND_URL` is a required build-arg with no default —
this fails fast in CI, at build time, instead of silently at runtime
with a broken rewrite. Keep it required.

---

## 14. RDS connection works from one pod but not another

**Symptom:** The backend connects fine; a different pod (frontend,
debug pod) cannot reach the database at all.

**Triage commands:**
```bash
kubectl exec deploy/backend -- env | grep DATABASE_URL
kubectl exec deploy/frontend -- env | grep DATABASE_URL 2>&1 || echo "NOT SET"
kubectl get networkpolicy -o wide
```

**Likely causes:**
- The non-backend pod isn't allowed by the NetworkPolicy — the
  `allow-frontend-to-backend-and-backend-to-postgres` policy only
  admits port 5432 from pods labeled `app.kubernetes.io/name: backend`.
- Security group allows the node but the pod's egress goes through a
  different network path.

**Fix:** This is the intended behavior — only the backend should reach
the database. If the backend pod itself can't connect, check the
NetworkPolicy's `from` rules and the pod labels.

**Prevention:** This is the NetworkPolicy working as designed —
document it as expected so on-call doesn't "fix" it by widening the
policy to any pod in the namespace.

---

## 15. Monitoring / alerts not firing

**Symptom:** A known problem occurred but no CloudWatch alarm or
in-cluster alert fired.

**Triage commands:**
```bash
# CloudWatch
aws logs describe-log-groups --log-group-name-prefix="/aws/eks"
aws cloudwatch describe-alarms --alarm-name-prefix="plinth"

# In-cluster (if using Prometheus)
kubectl get servicemonitor -A
kubectl logs deploy/prometheus --tail=50
```

**Likely causes:**
- CloudWatch log group doesn't exist — the EKS cluster's
  `enabled_cluster_log_types` doesn't include the log type you're
  filtering for.
- Alarm thresholds are too permissive — pods restart but the alarm
  doesn't trigger because the metric doesn't cross the threshold.
- ServiceMonitor selector doesn't match Prometheus's pod selector.

**Fix:** Verify the log group exists and has data flowing. For alarms,
check `aws cloudwatch list-metrics --namespace ContainerInsights` to
confirm metrics are being published before tuning thresholds.

**Prevention:** Validate a new alarm against
`aws cloudwatch list-metrics` at the moment you create it, not after
the first incident where you needed it and discovered it was silent.

---

## Quick reference: diagnostic commands

```bash
# Pod status overview
kubectl get pods -A -o wide

# Recent events (sorted by time)
kubectl get events -A --sort-by=.lastTimestamp | tail -30

# Resource usage
kubectl top nodes
kubectl top pods -A

# Network troubleshooting
kubectl exec deploy/backend -- curl -s http://backend:8080/health
kubectl exec deploy/frontend -- wget -qO- http://backend:8080/health

# Terraform state inspection
terraform state list
terraform state show <resource>

# CI pipeline logs
gh run view <run-id> --log
```

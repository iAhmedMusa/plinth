# Troubleshooting

Fifteen real-world failure scenarios with short, practical answers. Each
answer follows the same shape: what to check first, the commands to run,
and the root-cause pattern behind the symptom.

---

## 1. Pods stuck in `CrashLoopBackOff`

**Check:**

```bash
kubectl logs <pod-name> --previous   # logs from the crashed container
kubectl describe pod <pod-name>      # last state + exit code
```

**Common causes:**
- Application fails to start (missing env var, bad DATABASE_URL, port
  conflict).
- Readiness probe fires before the app is ready — the container starts,
  fails the probe, gets restarted before it can serve.
- OOMKilled: the container exceeded its memory limit (`describe` shows
  `Reason: OOMKilled`). Increase `resources.limits.memory` or fix a
  memory leak.

**Fix:** Read the logs first. The exit code tells you everything — exit 1
is an application error, exit 137 is SIGKILL (OOM or manual kill), exit
1 is almost always a code bug or missing configuration.

---

## 2. Pods in `ImagePullBackOff`

**Check:**

```bash
kubectl describe pod <pod-name> | grep -A5 "Events"
```

**Common causes:**
- Typo in the image name or tag (e.g. `plinth-backend:0.1.0`
  vs `plinth-backend:0.1.0`).
- Image doesn't exist in the registry — the tag was never pushed, or
  the CI pipeline that builds it hasn't run yet.
- `imagePullSecrets` missing or misconfigured for private registries.

**Fix:** Verify the image exists:
```bash
docker manifest inspect <registry>/<image>:<tag>
```

---

## 3. Application is unreachable from the browser

**Check (in order):**

```bash
kubectl get ingress                     # is the Ingress object created?
kubectl get pods -n ingress-nginx       # is the controller running?
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=50
curl -H "Host: devops.localtest.me" http://<ingress-ip>/   # direct hit
```

**Common causes:**
- Ingress controller not installed or not ready — apply the
  ingress-nginx manifest and wait for the pod to become `Ready`.
- Host header mismatch — the browser sends a host that doesn't match
  any Ingress rule.
- Ingress class annotation missing (`ingressClassName: nginx`).

**Fix:** Work backwards from the Ingress object: does the controller see
it? Does the controller's nginx config include your host? Does DNS
resolve the host to the ingress IP?

---

## 4. Backend returns 502 Bad Gateway

**Check:**

```bash
kubectl logs deploy/frontend --tail=50   # Next.js proxy logs
kubectl logs deploy/backend --tail=50    # backend app logs
kubectl get svc backend                  # does the Service exist?
kubectl get endpoints backend            # does it have ready addresses?
```

**Common causes:**
- Backend pod is not `Ready` (failing health checks) — the Service has
  no endpoints, so the frontend's proxy gets connection refused.
- Backend port mismatch — Service `targetPort` doesn't match the
  container's `containerPort`.
- NetworkPolicy blocking the frontend→backend path.

**Fix:** Check `kubectl get endpoints backend` first. If empty, the
backend pods aren't passing readiness probes — fix the probe config or
the app itself.

---

## 5. Database connection timeout

**Check:**

```bash
kubectl exec deploy/backend -- python -c "
import socket
s = socket.create_connection(('db', 5432), timeout=5)
print('connected')
" 2>&1 || echo "TIMEOUT"
```

**Common causes:**
- Database pod not running (`kubectl get pods -l app.kubernetes.io/name=postgres`).
- `DATABASE_URL` env var points to the wrong host/port.
- Security group (cloud) or NetworkPolicy (cluster) blocking port 5432.
- Database container is healthy but the application tries to connect
  before the database is ready — the `depends_on` condition in compose
  or the readiness probe should prevent this, but timing can still
  slip.

**Fix:** Test connectivity from inside the backend pod. If the socket
connects but authentication fails, the credentials are wrong. If the
socket times out, it's a network/availability issue.

---

## 6. SSL certificate errors in the browser

**Check:**

```bash
kubectl get certificate -A               # cert-manager objects
kubectl describe certificate <name>      # issuance status
kubectl logs -n cert-manager deploy/cert-manager --tail=50
```

**Common causes:**
- cert-manager not installed or not configured with a ClusterIssuer.
- DNS not pointing to the ingress — Let's Encrypt can't reach the
  domain to complete the HTTP-01 challenge.
- Rate limiting — too many certificate requests for the same domain.
- Expired certificate — cert-manager's renewal failed silently.

**Fix:** Check `kubectl describe certificate` — the `Status` field tells
you exactly what went wrong. For Let's Encrypt, the challenge pod
(`kubectl get pods -n cert-manager`) must complete successfully.

---

## 7. CI pipeline fails at the build step

**Check:**
- Open the failed GitHub Actions run and read the step output.

**Common causes:**
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

---

## 8. CI pipeline fails at the deploy step

**Check:**

```bash
# In the GitHub Actions log, look for:
kubectl apply -k k8s/overlays/ci --dry-run=client -o yaml
```

**Common causes:**
- `kustomize edit set image` references a repository name that doesn't
  match what was pushed (case sensitivity, missing namespace prefix).
- The kind cluster creation failed silently — ingress-nginx install
  times out.
- The namespace in the overlay doesn't match what `kubectl rollout
  status` expects.

**Fix:** The pipeline's "Dump diagnostics on failure" step (if running
in staging) dumps pod status, describe, and logs. Start there.

---

## 9. Secrets accidentally pushed to GitHub

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

**Check:**

```bash
kubectl get pods --field-selector=status.phase=Failed -o wide
kubectl describe node <node-name> | grep -A10 "Conditions"
kubectl top pods                        # current memory usage
```

**Common causes:**
- Container memory limit too low — the app legitimately needs more
  than allocated.
- Node running too many pods — no headroom for scheduling.
- Memory leak — usage grows until the limit is hit.

**Fix:** Check `kubectl top pods` to see actual vs. limit usage. If
actual usage is close to the limit, increase the request/limit. If it's
a leak, fix the code.

---

## 11. Terraform plan shows unwanted resource replacement

**Check:**

```bash
terraform plan -var-file=envs/production.tfvars 2>&1 | grep -E "(-/\+|~)"
```

**Common causes:**
- A resource attribute changed that is `ForceNew` (e.g. EKS cluster
  `name`, RDS `engine`).
- A provider upgrade changed `ForceNew` behavior on a previously-mutable
  field.
- A resource was renamed in the Terraform config — Terraform sees
  delete+create instead of in-place update.
- Drift from manual changes made outside Terraform (console clicks).

**Fix:** Read the plan output carefully — it names the specific field
that forces replacement. If it's a rename, use `terraform state mv`. If
it's drift, import the manual change or revert it. The `prevent_destroy`
lifecycle on EKS and RDS is the backstop — it blocks accidental
destruction at `plan` time.

---

## 12. Kustomize overlay applies wrong image tag

**Check:**

```bash
kustomize build k8s/overlays/staging | grep "image:"
kustomize build k8s/overlays/production | grep "image:"
```

**Common causes:**
- The overlay's `kustomization.yaml` `images:` transformer references
  the wrong repository or tag.
- CI's `kustomize edit set image` command targets the wrong overlay
  directory.
- Base manifest uses a hardcoded image instead of the `PLACEHOLDER`
  convention — the overlay transformer can't rewrite it.

**Fix:** Always verify with `kustomize build <overlay> | grep image:`
before applying. The base manifests use
`PLACEHOLDER/plinth-{backend,frontend}:0.0.0` — never edit
these directly; the overlay rewrites them.

---

## 13. Frontend build fails with "BACKEND_URL" not set

**Check:**

```bash
# In the CI log or locally:
cd frontend && npm run build 2>&1 | head -20
```

**Common causes:**
- The `BACKEND_URL` env var isn't passed during `docker build` or `npm
  run build`.
- The Next.js `rewrites()` function in `next.config.ts` reads
  `BACKEND_URL` at build time — if it's missing, the build fails
  because the rewrite destination can't be resolved.

**Fix:** Pass `BACKEND_URL` as a build arg or env var at build time:
```bash
docker build --build-arg BACKEND_URL=http://backend:8080 ./frontend
```

This is documented in the root README's "Design decisions" section —
the rewrite is baked into the image at build time, not read at runtime.

---

## 14. RDS connection works from one pod but not another

**Check:**

```bash
kubectl exec deploy/backend -- env | grep DATABASE_URL
kubectl exec deploy/frontend -- env | grep DATABASE_URL 2>&1 || echo "NOT SET"
kubectl get networkpolicy -o wide
```

**Common causes:**
- The non-backend pod isn't allowed by the NetworkPolicy — the
  `allow-frontend-to-backend-and-backend-to-postgres` policy only
  admits port 5432 from pods labeled `app.kubernetes.io/name: backend`.
- Security group allows the node but the pod's egress goes through a
  different network path.

**Fix:** This is the intended behavior — only the backend should reach
the database. If the backend pod itself can't connect, check the
NetworkPolicy's `from` rules and the pod labels.

---

## 15. Monitoring / alerts not firing

**Check:**

```bash
# CloudWatch
aws logs describe-log-groups --log-group-name-prefix="/aws/eks"
aws cloudwatch describe-alarms --alarm-name-prefix="plinth"

# In-cluster (if using Prometheus)
kubectl get servicemonitor -A
kubectl logs deploy/prometheus --tail=50
```

**Common causes:**
- CloudWatch log group doesn't exist — the EKS cluster's
  `enabled_cluster_log_types` doesn't include the log type you're
  filtering for.
- Alarm thresholds are too permissive — pods restart but the alarm
  doesn't trigger because the metric doesn't cross the threshold.
- ServiceMonitor selector doesn't match Prometheus's pod selector.

**Fix:** Verify the log group exists and has data flowing. For alarms,
check `aws cloudwatch list-metrics --namespace ContainerInsights` to
confirm metrics are being published before tuning thresholds.

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

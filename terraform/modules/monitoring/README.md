# monitoring module

## Purpose

Application CloudWatch log group, Container Insights (via the EKS addon),
and example alarms for node CPU and RDS free storage. The control plane
log group is deliberately *not* here -- it lives in the eks module, which
must create it before the cluster exists (see design notes).

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Resource name prefix | (required) |
| `cluster_name` | EKS cluster name | (required) |
| `db_instance_id` | RDS instance identifier for the storage alarm | (required) |
| `log_retention_days` | Log group retention | `30` |
| `sns_topic_arn` | Alarm notification target; empty = alarms with no subscriber | `""` |
| `node_cpu_alarm_threshold` | CPU % that triggers the high-CPU alarm | `80` |
| `rds_free_storage_threshold_bytes` | Free storage floor for the low-storage alarm | `2000000000` (2 GiB) |
| `tags` | Common tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `application_log_group_name` | Application log group |

## Design notes

- **No control plane log group here.** With `enabled_cluster_log_types`
  set, EKS auto-creates `/aws/eks/<cluster>/cluster` the moment the
  control plane comes up. This module runs *after* the eks module, so
  creating that group here would fail the first apply with
  `ResourceAlreadyExistsException`. The eks module owns it instead,
  created before the cluster with an explicit `depends_on`.
- **Container Insights via `aws_eks_addon`**, not a hand-rolled CloudWatch
  agent DaemonSet — AWS manages the collector's lifecycle and IRSA role
  for us, and it's what publishes the `ContainerInsights` namespace
  metrics the node CPU alarm reads from.
- **Alarms exist without a subscriber by default.** `sns_topic_arn`
  defaults to `""`, in which case this module creates its own SNS topic
  with zero subscriptions — the alarms are real and visible in the
  CloudWatch console/API, but nobody gets paged until an actual on-call
  channel (email, Slack via Lambda, PagerDuty) is subscribed to that
  topic, or a real topic ARN is passed in. This is intentionally explicit
  rather than silently skipping alarm creation.
- **Two example alarms, not a full alerting suite.** Node CPU high and RDS
  free storage low are the two most common "something's about to fall
  over" signals; a real production setup would add pod restart counts,
  RDS CPU/connections, and ALB 5xx rate, following the same pattern.

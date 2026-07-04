# The control plane log group (/aws/eks/<cluster>/cluster) is deliberately
# NOT created here: with enabled_cluster_log_types set, EKS auto-creates it
# at cluster creation, so it must be owned by the eks module and created
# BEFORE the cluster -- creating it here (post-cluster) would fail the
# first apply with ResourceAlreadyExistsException. See modules/eks/main.tf.
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${var.cluster_name}/application"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-logs"
  })
}

# Container Insights: ships node/pod/container CPU, memory, and network
# metrics into CloudWatch under the ContainerInsights namespace without
# running a separate collector DaemonSet to manage. Requires the cluster
# to already exist and have a functioning OIDC provider (the addon uses
# IRSA internally) -- both are satisfied by the time this module runs,
# since main.tf wires monitoring after eks.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"

  tags = var.tags
}

resource "aws_sns_topic" "alarms" {
  count = var.sns_topic_arn == "" ? 1 : 0
  name  = "${var.name_prefix}-alarms"
  tags  = var.tags
}

locals {
  # Use the provided topic if one was passed in; otherwise fall back to
  # the placeholder topic created above so alarms always have a valid
  # (if unsubscribed) action target. Wire a real subscription -- email,
  # Slack via a Lambda, PagerDuty -- once an on-call channel exists.
  # coalesce over the splat (rather than indexing alarms[0] in a ternary
  # branch) stays valid however this is refactored: when a real topic ARN
  # is passed in, the placeholder topic has count = 0 and the splat is
  # simply empty.
  alarm_actions = [coalesce(var.sns_topic_arn != "" ? var.sns_topic_arn : null, one(aws_sns_topic.alarms[*].arn))]
}

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${var.name_prefix}-node-cpu-high"
  alarm_description   = "EKS node CPU utilization above ${var.node_cpu_alarm_threshold}% for 10 minutes"
  namespace           = "ContainerInsights"
  metric_name         = "node_cpu_utilization"
  dimensions          = { ClusterName = var.cluster_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.node_cpu_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-free-storage-low"
  alarm_description   = "RDS free storage below ${var.rds_free_storage_threshold_bytes} bytes for 10 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = var.rds_free_storage_threshold_bytes
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  tags                = var.tags
}

environment        = "production"
region             = "ap-southeast-1"
cluster_name       = "plinth"
kubernetes_version = "1.30"
vpc_cidr           = "10.2.0.0/16"

node_instance_type = "t3.large"
node_desired_size  = 3
node_min_size      = 3
node_max_size      = 6

db_instance_class = "db.t4g.medium"
db_name           = "appdb"
db_username       = "appuser"

tags = {
  Project     = "plinth"
  Environment = "production"
}

environment        = "staging"
region             = "ap-southeast-1"
cluster_name       = "devops-assessment"
kubernetes_version = "1.30"
vpc_cidr           = "10.1.0.0/16"

node_instance_type = "t3.medium"
node_desired_size  = 2
node_min_size      = 2
node_max_size      = 4

db_instance_class = "db.t4g.micro"
db_name           = "appdb"
db_username       = "appuser"

tags = {
  Project     = "devops-assessment"
  Environment = "staging"
}

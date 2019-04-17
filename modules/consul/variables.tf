variable "ami_id" {}
variable "cluster_name" {}
variable "cluster_size" {}
variable "instance_type" {}

variable "additional_sg_ids" {
  type = "list"
}

variable "private_subnets" {
  type = "list"
}

variable "cluster_tag_key" {}
variable "cluster_tag_value" {}

variable "packerized" {
  type    = "string"
  default = false
}

variable "api_ingress_cidr_blocks" {
  type = "list"
}

variable "rpc_ingress_cidr_blocks" {
  type = "list"
}

variable "serf_ingress_cidr_blocks" {
  type = "list"
}

variable "vpc_id" {}

variable "s3_bucket" {
  default = ""
}

variable "s3_path" {
  default = ""
}

variable "consul_zip" {}

variable "ssm_parameter_path" {
  description = "Base path for Consul SSM parameters"
  default     = "/"
}

variable "ssm_parameter_gossip_encryption_key" {
  description = "SSM parameter name for Consul gossip encryption key, a 16-byte base64 encoded string"
}

variable "ssm_parameter_tls_ca" {
  description = "SSM parameter name for Consul TLS CA chain"
}

variable "ssm_parameter_tls_cert" {
  description = "SSM parameter name for Consul TLS certificate"
}

variable "ssm_parameter_tls_key" {
  description = "SSM parameter name for Consul TKS key"
}

variable "ssm_kms_key" {}

variable "ssh_public_key" {}

variable "health_check_grace_period" {
  description = "Time, in seconds, after instance comes into service before checking health."
  default     = 300
}

variable "wait_for_capacity_timeout" {
  description = "A maximum duration that Terraform should wait for ASG instances to be healthy before timing out. Setting this to '0' causes Terraform to skip all Capacity Waiting behavior."
  type        = "string"
  default     = "10m"
}

variable "enabled_metrics" {
  description = "List of autoscaling group metrics to enable."
  type        = "list"
  default     = []
}

variable "termination_policies" {
  description = "A list of policies to decide how the instances in the auto scale group should be terminated. The allowed values are OldestInstance, NewestInstance, OldestLaunchConfiguration, ClosestToNextInstanceHour, Default."
  type        = "string"
  default     = "Default"
}

variable "availability_zones" {
  type = "list"
}

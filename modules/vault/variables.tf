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

variable "consul_rejoin_tag_key" {}
variable "consul_rejoin_tag_value" {}

variable "packerized" {
  type    = "string"
  default = false
}

variable "api_ingress_cidr_blocks" {
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
variable "vault_zip" {}

variable "ssm_parameter_path" {
  description = "Base path for Consul SSM parameters"
  default     = "/"
}

variable "ssm_parameter_gossip_encryption_key" {
  description = "SSM parameter name for Consul gossip encryption key, a 16-byte base64 encoded string"
}

variable "ssm_parameter_consul_client_tls_ca" {
  description = "SSM parameter name for Consul TLS CA chain"
}

variable "ssm_parameter_consul_client_tls_cert" {
  description = "SSM parameter name for Consul TLS certificate"
}

variable "ssm_parameter_consul_client_tls_key" {
  description = "SSM parameter name for Consul TKS key"
}

variable "ssm_parameter_vault_tls_cert_chain" {}
variable "ssm_parameter_vault_tls_key" {}

variable "ssm_kms_key" {}

variable "ssh_public_key" {}

variable "kms_deletion_days" {
  default = 7
}

variable "kms_key_rotate" {
  default = true
}

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

variable "cross_zone_load_balancing" {
  description = "Set to true to enable cross-zone load balancing and you have your vault cluster set up across multiple AZs as per the RA"
  type        = "string"
  default     = true
}

variable "idle_timeout" {
  description = "The time, in seconds, that the connection is allowed to be idle."
  type        = "string"
  default     = 60
}

variable "connection_draining" {
  description = "Set to true to enable connection draining."
  type        = "string"
  default     = true
}

variable "connection_draining_timeout" {
  description = "The time, in seconds, to allow for connections to drain."
  type        = "string"
  default     = 300
}

variable "lb_port" {
  description = "The port the load balancer should listen on for API requests."
  type        = "string"
  default     = 8200
}

variable "vault_api_port" {
  description = "The port to listen on for API requests."
  type        = "string"
  default     = 8200
}

variable "health_check_protocol" {
  description = "The protocol to use for health check. As we are using TLS this will be HTTPS."
  type        = "string"
  default     = "HTTPS"
}

variable "health_check_path" {
  description = "The Vault API path to hit."
  type        = "string"
  default     = "/v1/sys/health"
}

variable "health_check_interval" {
  description = "The interval between checks (seconds)."
  type        = "string"
  default     = 10
}

variable "health_check_healthy_threshold" {
  description = "The number of health checks that must pass before the instance is declared healthy."
  type        = "string"
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "The number of health checks that must fail before the instance is declared unhealthy."
  type        = "string"
  default     = 2
}

variable "health_check_timeout" {
  description = "The amount of time, in seconds, before a health check times out."
  type        = "string"
  default     = 5
}

variable "health_check_success_codes" {
  description = "The HTTP success codes returned to determine if an instance is healthy."
  type        = "string"
  default     = "200,473"
}

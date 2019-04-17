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
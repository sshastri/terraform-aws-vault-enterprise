#############
# Variables #
#############

variable "consul_ssh_public_key" {}
variable "vault_ssh_public_key" {}
variable "environment" {}
variable "region" {}

variable "consul_private_subnet_ids" {
  type = "list"
}

variable "vault_private_subnet_ids" {
  type = "list"
}

variable "consul_ami_id" {}
variable "vault_ami_id" {}

variable "consul_additional_security_group_ids" {
  type = "list"
}

variable "vault_additional_security_group_ids" {
  type = "list"
}

variable "s3_bucket" {}
variable "vpc_id" {}
variable "ssm_kms_key" {}
variable "ssm_parameter_path" {}
variable "ssm_parameter_consul_tls_ca" {}
variable "ssm_parameter_consul_tls_cert" {}
variable "ssm_parameter_consul_tls_key" {}
variable "ssm_parameter_consul_gossip_encryption_key" {}
variable "ssm_parameter_consul_client_tls_ca" {}
variable "ssm_parameter_consul_client_tls_cert" {}
variable "ssm_parameter_consul_client_tls_key" {}

variable "ssm_parameter_vault_tls_cert_chain" {}
variable "ssm_parameter_vault_tls_key" {}
variable "consul_cluster_size" {}
variable "vault_cluster_size" {}

variable "availability_zones" {
  type = "list"
}

#############
# Providers #
#############

provider "aws" {
  region = "${var.region}"
}

###########
# Modules #
###########

module "s3" {
  source = "modules/s3"

  s3_bucket = "${var.s3_bucket}"
  s3_path   = "install_files"
}

module "consul" {
  source = "modules/consul"

  ami_id                              = "${var.consul_ami_id}"
  cluster_name                        = "${var.environment}"
  cluster_size                        = "${var.consul_cluster_size}"
  instance_type                       = "m5.large"
  availability_zones                  = ["${var.availability_zones}"]
  private_subnets                     = ["${var.consul_private_subnet_ids}"]
  cluster_tag_key                     = "consul_server_cluster"
  cluster_tag_value                   = "${var.environment}"
  packerized                          = false
  api_ingress_cidr_blocks             = ["0.0.0.0/0"]
  rpc_ingress_cidr_blocks             = ["0.0.0.0/0"]
  serf_ingress_cidr_blocks            = ["0.0.0.0/0"]
  additional_sg_ids                   = ["${var.consul_additional_security_group_ids}"]
  vpc_id                              = "${var.vpc_id}"
  s3_bucket                           = "${var.s3_bucket}"
  s3_path                             = "install_files"
  consul_zip                          = "consul_enterprise_premium-1.4.4.zip"
  ssm_kms_key                         = "${var.ssm_kms_key}"
  ssm_parameter_path                  = "${var.ssm_parameter_path}"
  ssm_parameter_gossip_encryption_key = "${var.ssm_parameter_consul_gossip_encryption_key}"
  ssm_parameter_tls_ca                = "${var.ssm_parameter_consul_tls_ca}"
  ssm_parameter_tls_cert              = "${var.ssm_parameter_consul_tls_cert}"
  ssm_parameter_tls_key               = "${var.ssm_parameter_consul_tls_key}"
  ssh_public_key                      = "${var.consul_ssh_public_key}"
}

module "vault" {
  source = "./modules/vault"

  ami_id                               = "${var.vault_ami_id}"
  cluster_name                         = "${var.environment}"
  cluster_size                         = "${var.vault_cluster_size}"
  instance_type                        = "m5.large"
  availability_zones                   = ["${var.availability_zones}"]
  private_subnets                      = "${var.vault_private_subnet_ids}"
  consul_rejoin_tag_key                = "consul_server_cluster"
  consul_rejoin_tag_value              = "${var.environment}"
  packerized                           = false
  api_ingress_cidr_blocks              = ["0.0.0.0/0"]
  additional_sg_ids                    = ["${var.vault_additional_security_group_ids}"]
  vpc_id                               = "${var.vpc_id}"
  s3_bucket                            = "${var.s3_bucket}"
  s3_path                              = "install_files"
  consul_zip                           = "consul_enterprise_premium-1.4.4.zip"
  vault_zip                            = "vault_enterprise_premium-1.0.3.zip"
  ssm_kms_key                          = "${var.ssm_kms_key}"
  ssm_parameter_path                   = "${var.ssm_parameter_path}"
  ssm_parameter_gossip_encryption_key  = "${var.ssm_parameter_consul_gossip_encryption_key}"
  ssm_parameter_consul_client_tls_ca   = "${var.ssm_parameter_consul_client_tls_ca}"
  ssm_parameter_consul_client_tls_cert = "${var.ssm_parameter_consul_client_tls_cert}"
  ssm_parameter_consul_client_tls_key  = "${var.ssm_parameter_consul_client_tls_key}"
  ssm_parameter_vault_tls_cert_chain   = "${var.ssm_parameter_vault_tls_cert_chain}"
  ssm_parameter_vault_tls_key          = "${var.ssm_parameter_vault_tls_key}"
  ssh_public_key                       = "${var.vault_ssh_public_key}"
}

###########
# Outputs #
###########

output "vault_lb_dns_name" {
  value = "${module.vault.lb_dns_name}"
}

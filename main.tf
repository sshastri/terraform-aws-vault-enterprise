#############
# Variables #
#############

variable "consul_ssh_public_key" {}
variable "vault_ssh_public_key" {}
variable "environment" {}
variable "consul_private_subnet_ids" {
    type = "list"
}

variable "vault_private_subnet_ids" {
    type = "list"
}

variable "consul_ami_id" {}
variable "vault_ami_id" {}
variable "consul_additional_security_groups_ids" {
    type = "list"
}

variable "vault_additional_security_groups_ids" {
    type = "list"
}

variable "s3_bucket" {}
variable "vpc_id" {}

#############
# Providers #
#############

provider "aws" {
  region = "${var.region}"
}

###########
# Modules #
###########

module "consul" {
  source = "./modules/consul"

  ami_id                   = "${var.consul_ami_id}"
  cluster_name             = "${var.environment}"
  cluster_size             = 5
  instance_type            = "m5.large"
  private_subnets          = ["${var.consul_private_subnet_ids}"]
  cluster_tag_key          = "consul_server_cluster"
  cluster_tag_value        = "${var.environment}"
  packerized               = false
  api_ingress_cidr_blocks  = ["0.0.0.0/0"]
  rpc_ingress_cidr_blocks  = ["0.0.0.0/0"]
  serf_ingress_cidr_blocks = ["0.0.0.0/0"]
  additional_sg_ids        = ["${var.consul_additional_security_group_ids}"]
  vpc_id                   = "${var.vpc_id}"
  s3_bucket                = "${var.s3_bucket}"
  s3_path                  = "install_files"
  consul_zip               = "consul_enterprise_premium-1.4.4.zip"
  ssm_encrypt_key = "${module.ssm.ssm_encrypt_key_name}"
  ssm_tls_ca = "${module.ssm.ssm_tls_ca_name}"
  ssm_tls_cert = "${module.ssm.ssm_tls_cert_name}"
  ssm_tls_key = "${module.ssm.ssm_tls_key_name}"
  ssm_parameter_path = "${module.ssm.ssm_parameter_path}"
  kms_key_arn = "${module.ssm.kms_key_arn}"
  ssh_public_key = "${var.consul_ssh_public_key}"
}


###########
# Outputs #
###########

output "consul_ip_addresses" {
  value = "${module.consul.ip_addresses}"
}

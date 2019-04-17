terraform {
  required_version = ">= 0.11.11"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_key_pair" "vault" {
  key_name   = "vault-server-${var.cluster_name}"
  public_key = "${var.ssh_public_key}"
}

resource "aws_iam_instance_profile" "vault" {
  name = "vault-server-${var.cluster_name}"
  role = "${aws_iam_role.vault.name}"
}

resource "aws_iam_role" "vault" {
  name               = "vault-server-${var.cluster_name}"
  path               = "/"
  assume_role_policy = "${file("${path.module}/files/iam_role.json")}"
}

resource "aws_iam_role_policy" "vault" {
  name   = "vault-server-${var.cluster_name}"
  role   = "${aws_iam_role.vault.id}"
  policy = "${file("${path.module}/files/iam_role_policy.json")}"
}

resource "aws_instance" "vault" {
  ami                         = "${var.ami_id}"
  count                       = "${var.cluster_size}"
  instance_type               = "${var.instance_type}"
  iam_instance_profile        = "${aws_iam_instance_profile.vault.id}"
  associate_public_ip_address = false
  key_name                    = "${aws_key_pair.vault.key_name}"
  vpc_security_group_ids      = ["${concat(var.additional_sg_ids, list(aws_security_group.vault.id))}"]
  user_data                   = "${data.template_file.vault_user_data.rendered}"
  subnet_id                   = "${element(var.private_subnets, count.index)}"

  tags = {
    "Name" = "vault-${var.cluster_name}-${count.index}"
  }
}

resource "random_id" "install_script" {
  keepers = {
    install_hash = "${filemd5("${path.root}/files/install_vault.sh")}"
    funcs_hash   = "${filemd5("${path.root}/files/funcs.sh")}"
  }

  byte_length = 8
}

data "template_file" "vault_user_data" {
  template = "${file("${path.module}/templates/user_data.sh.tpl")}"

  vars {
    packerized                           = "${var.packerized}"
    s3_bucket                            = "${var.s3_bucket}"
    s3_path                              = "${var.s3_path}"
    rejoin_tag_key                       = "${var.consul_rejoin_tag_key}"
    rejoin_tag_value                     = "${var.consul_rejoin_tag_value}"
    consul_zip                           = "${var.consul_zip}"
    vault_zip                            = "${var.vault_zip}"
    ssm_parameter_gossip_encryption_key  = "${var.ssm_parameter_gossip_encryption_key}"
    ssm_parameter_consul_client_tls_ca   = "${var.ssm_parameter_consul_client_tls_ca}"
    ssm_parameter_consul_client_tls_cert = "${var.ssm_parameter_consul_client_tls_cert}"
    ssm_parameter_consul_client_tls_key  = "${var.ssm_parameter_consul_client_tls_key}"
    ssm_parameter_vault_tls_cert_chain   = "${var.ssm_parameter_vault_tls_cert_chain}"
    ssm_parameter_vault_tls_key          = "${var.ssm_parameter_vault_tls_key}"
    install_script_hash                  = "${(var.packerized ? random_id.install_script.hex : "" )}"
    vault_api_address                    = false
  }
}

resource "aws_security_group" "vault" {
  name        = "vault-${var.cluster_name}"
  description = "Security group for communication to Vault servers"
  vpc_id      = "${var.vpc_id}"

  tags = {
    "Owner" = "${var.cluster_name}"
  }
}

resource "aws_security_group_rule" "vault_api_ingress" {
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = ["${var.api_ingress_cidr_blocks}"]
  description       = "Vault API"
  security_group_id = "${aws_security_group.vault.id}"
}

resource "aws_security_group_rule" "vault_api_ingress_internal" {
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  self              = true
  description       = "Vault API internal"
  security_group_id = "${aws_security_group.vault.id}"
}

resource "aws_security_group_rule" "vault_cluster_ingress_internal" {
  type              = "ingress"
  from_port         = 8201
  to_port           = 8201
  protocol          = "tcp"
  self              = true
  description       = "Vault internal cluster traffic"
  security_group_id = "${aws_security_group.vault.id}"
}

resource "aws_security_group_rule" "vault_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Vault egress traffic"
  security_group_id = "${aws_security_group.vault.id}"
}

resource "aws_iam_role_policy" "s3" {
  count  = "${var.packerized ? 0 : 1}"
  name   = "vault-server-s3-${var.cluster_name}"
  role   = "${aws_iam_role.vault.id}"
  policy = "${data.template_file.s3_iam_role_policy.rendered}"
}

data "template_file" "s3_iam_role_policy" {
  count    = "${var.packerized ? 0 : 1}"
  template = "${file("${path.module}/templates/s3_iam_role_policy.json.tpl")}"

  vars {
    s3_bucket = "${var.s3_bucket}"
  }
}

resource "aws_iam_role_policy" "kms" {
  name   = "vault-server-kms-${var.cluster_name}"
  role   = "${aws_iam_role.vault.id}"
  policy = "${data.template_file.kms_iam_role_policy.rendered}"
}

data "template_file" "kms_iam_role_policy" {
  template = "${file("${path.module}/templates/kms_iam_role_policy.json.tpl")}"

  vars {
    kms_key_arn = "${var.ssm_kms_key}"
  }
}

resource "aws_iam_role_policy" "ssm" {
  name   = "vault-server-ssm-${var.cluster_name}"
  role   = "${aws_iam_role.vault.id}"
  policy = "${data.template_file.ssm_iam_role_policy.rendered}"
}

data "template_file" "ssm_iam_role_policy" {
  template = "${file("${path.module}/templates/ssm_iam_role_policy.json.tpl")}"

  vars {
    ssm_parameter_arn = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_path}"
  }
}

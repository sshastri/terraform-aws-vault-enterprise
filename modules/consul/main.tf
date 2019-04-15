terraform {
  required_version = ">= 0.11.11"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


resource "aws_key_pair" "consul" {
  key_name   = "consul-server-${var.cluster_name}"
  public_key = "${var.ssh_public_key}"
}

resource "aws_iam_instance_profile" "consul" {
  name = "consul-server-${var.cluster_name}"
  role = "${aws_iam_role.consul.name}"
}

resource "aws_iam_role" "consul" {
  name               = "consul-server-${var.cluster_name}"
  path               = "/"
  assume_role_policy = "${file("${path.module}/files/iam_role.json")}"
}

resource "aws_iam_role_policy" "consul" {
  name   = "consul-server-${var.cluster_name}"
  role   = "${aws_iam_role.consul.id}"
  policy = "${file("${path.module}/files/iam_role_policy.json")}"
}

resource "aws_instance" "consul" {
  ami                         = "${var.ami_id}"
  count                       = "${var.cluster_size}"
  instance_type               = "${var.instance_type}"
  iam_instance_profile        = "${aws_iam_instance_profile.consul.id}"
  associate_public_ip_address = false
  key_name                    = "${aws_key_pair.consul.key_name}"
  vpc_security_group_ids      = ["${concat(var.additional_sg_ids, list(aws_security_group.consul.id))}"]
  user_data                   = "${data.template_file.consul_user_data.rendered}"
  subnet_id                   = "${element(var.private_subnets, count.index)}"

  tags = "${merge(map("Name", "consul-${var.cluster_name}-${count.index}"), map("${var.cluster_tag_key}", "${var.cluster_tag_value}"))}"
}

data "template_file" "consul_user_data" {
  template = "${file("${path.module}/templates/user_data.sh.tpl")}"

  vars {
    packerized             = "${var.packerized}"
    s3_bucket              = "${var.s3_bucket}"
    s3_path                = "${var.s3_path}"
    bootstrap_count        = "${var.cluster_size}"
    tag_key                = "${var.cluster_tag_key}"
    tag_value              = "${var.cluster_tag_value}"
    consul_zip             = "${var.consul_zip}"
    ssm_encrypt_key        = "${var.ssm_encrypt_key}"
    ssm_tls_ca             = "${var.ssm_tls_ca}"
    ssm_tls_cert           = "${var.ssm_tls_cert}"
    ssm_tls_key            = "${var.ssm_tls_key}"
    verify_server_hostname = "${var.verify_server_hostname}"
  }
}

resource "aws_security_group" "consul" {
  name        = "consul-${var.cluster_name}"
  description = "Security group for communication to Consul servers"
  vpc_id      = "${var.vpc_id}"

  tags = {
    "Owner" = "${var.cluster_name}"
  }
}

resource "aws_security_group_rule" "consul_api_ingress" {
  type              = "ingress"
  from_port         = 8500
  to_port           = 8500
  protocol          = "tcp"
  cidr_blocks       = ["${var.api_ingress_cidr_blocks}"]
  description       = "Consul API"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_security_group_rule" "consul_api_ingress_internal" {
  type              = "ingress"
  from_port         = 8500
  to_port           = 8500
  protocol          = "tcp"
  self              = true
  description       = "Consul API internal"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_security_group_rule" "consul_rpc_ingress" {
  type              = "ingress"
  from_port         = 8300
  to_port           = 8300
  protocol          = "tcp"
  cidr_blocks       = ["${var.rpc_ingress_cidr_blocks}"]
  description       = "Consul RPC traffic"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_security_group_rule" "consul_rpc_ingress_internal" {
  type              = "ingress"
  from_port         = 8300
  to_port           = 8300
  protocol          = "tcp"
  self              = true
  description       = "Consul internal RPC traffic"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_security_group_rule" "consul_serf_ingress" {
  type              = "ingress"
  from_port         = 8301
  to_port           = 8301
  protocol          = "tcp"
  cidr_blocks       = ["${var.serf_ingress_cidr_blocks}"]
  description       = "Consul serf traffic"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_security_group_rule" "consul_serf_ingress_internal" {
  type              = "ingress"
  from_port         = 8301
  to_port           = 8301
  protocol          = "tcp"
  self              = true
  description       = "Consul internal serf traffic"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_security_group_rule" "consul_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Consul egress traffic"
  security_group_id = "${aws_security_group.consul.id}"
}

resource "aws_s3_bucket_object" "install_consul" {
  count  = "${var.packerized ? 0 : 1}"
  bucket = "${var.s3_bucket}"
  key    = "${var.s3_path}/install_consul.sh"
  source = "${path.module}/files/install_consul.sh"
  etag   = "${filemd5("${path.module}/files/install_consul.sh")}"
}

resource "aws_iam_role_policy" "s3" {
  count  = "${var.packerized ? 0 : 1}"
  name   = "consul-server-s3-${var.cluster_name}"
  role   = "${aws_iam_role.consul.id}"
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
  name   = "consul-server-kms-${var.cluster_name}"
  role   = "${aws_iam_role.consul.id}"
  policy = "${data.template_file.kms_iam_role_policy.rendered}"
}

data "template_file" "kms_iam_role_policy" {
  template = "${file("${path.module}/templates/kms_iam_role_policy.json.tpl")}"

  vars {
    kms_key_arn = "${var.ssm_kms_key}"
  }
}

resource "aws_iam_role_policy" "ssm" {
  name   = "consul-server-ssm-${var.cluster_name}"
  role   = "${aws_iam_role.consul.id}"
  policy = "${data.template_file.ssm_iam_role_policy.rendered}"
}

data "template_file" "ssm_iam_role_policy" {
  template = "${file("${path.module}/templates/ssm_iam_role_policy.json.tpl")}"

  vars {
    ssm_parameter_arn = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_path}"
  }
}
terraform {
  required_version = ">= 0.11.11"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "vault" {
  description             = "Vault KMS key"
  deletion_window_in_days = "${var.kms_deletion_days}"
  enable_key_rotation     = "${var.kms_key_rotate}"

  tags {
    Name = "vault-kms-${var.cluster_name}"
  }
}

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

resource "aws_launch_configuration" "vault_asg" {
  name_prefix          = "vault-${var.cluster_name}-"
  image_id             = "${var.ami_id}"
  instance_type        = "${var.instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.vault.id}"
  security_groups      = ["${concat(var.additional_sg_ids, list(aws_security_group.vault.id))}"]
  key_name             = "${aws_key_pair.vault.key_name}"
  user_data            = "${data.template_file.vault_user_data.rendered}"

  lifecycle = {
    create_before_destroy = true
  }
}

resource "aws_placement_group" "vault" {
  name     = "vault-${var.cluster_name}"
  strategy = "spread"
}

resource "aws_autoscaling_group" "vault_asg" {
  name_prefix          = "${var.cluster_name}"
  launch_configuration = "${aws_launch_configuration.vault_asg.name}"
  availability_zones   = ["${var.availability_zones}"]
  vpc_zone_identifier  = ["${var.private_subnets}"]

  min_size             = "${var.cluster_size}"
  max_size             = "${var.cluster_size}"
  desired_capacity     = "${var.cluster_size}"
  placement_group      = "${aws_placement_group.vault.id}"
  termination_policies = ["${var.termination_policies}"]

  health_check_type         = "EC2"
  health_check_grace_period = "${var.health_check_grace_period}"
  wait_for_capacity_timeout = "${var.wait_for_capacity_timeout}"

  enabled_metrics = ["${var.enabled_metrics}"]

  lifecycle = {
    create_before_destroy = true
  }

  tag = {
    key                 = "Name"
    value               = "vault-${var.cluster_name}"
    propagate_at_launch = true
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
    vault_api_address                    = "${aws_lb.vault_lb.dns_name}"
    vault_unseal_kms_key_arn             = "${aws_kms_key.vault.arn}"
  }
}

resource "aws_lb_target_group" "vault_asg" {
  name        = "vault-${var.cluster_name}"
  port        = "${var.vault_api_port}"
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = "${var.vpc_id}"

  health_check = {
    protocol            = "${var.health_check_protocol}"
    path                = "${var.health_check_path}"
    interval            = "${var.health_check_interval}"
    healthy_threshold   = "${var.health_check_healthy_threshold}"
    # unhealthy_threshold = "${var.health_check_unhealthy_threshold}"
    # timeout             = "${var.health_check_timeout}"
    # matcher             = "${var.health_check_success_codes}"
  }

  stickiness = {
    type    = "lb_cookie"
    enabled = false
  }
}

resource "aws_autoscaling_attachment" "asg_attachment_vault" {
  autoscaling_group_name = "${aws_autoscaling_group.vault_asg.id}"
  alb_target_group_arn   = "${aws_lb_target_group.vault_asg.arn}"
}

resource "aws_lb" "vault_lb" {
  name_prefix                      = "vault-"
  internal                         = true
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = true
  idle_timeout                     = "${var.idle_timeout}"
  subnets                          = ["${var.private_subnets}"]
}

resource "aws_lb_listener" "vault_lb" {
  load_balancer_arn = "${aws_lb.vault_lb.arn}"
  port              = "${var.vault_api_port}"
  protocol          = "TCP"

  default_action = {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.vault_asg.arn}"
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
    ssm_kms_key_arn   = "${var.ssm_kms_key}"
    vault_kms_key_arn = "${aws_kms_key.vault.arn}"
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

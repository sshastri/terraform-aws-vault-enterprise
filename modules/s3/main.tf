variable "s3_bucket" {}
variable "s3_path" {}

resource "aws_s3_bucket_object" "functions" {
  bucket = "${var.s3_bucket}"
  key    = "${var.s3_path}/funcs.sh"
  source = "${path.module}/../../files/funcs.sh"
  etag   = "${filemd5("${path.module}/../../files/funcs.sh")}"
}

resource "aws_s3_bucket_object" "install_consul" {
  bucket = "${var.s3_bucket}"
  key    = "${var.s3_path}/install_consul.sh"
  source = "${path.module}/../../files/install_consul.sh"
  etag   = "${filemd5("${path.module}/../../files/install_consul.sh")}"
}

resource "aws_s3_bucket_object" "install_vault" {
  bucket = "${var.s3_bucket}"
  key    = "${var.s3_path}/install_vault.sh"
  source = "${path.module}/../../files/install_vault.sh"
  etag   = "${filemd5("${path.module}/../../files/install_vault.sh")}"
}
output "ip_addresses" {
  value = "${aws_instance.consul.*.private_ip}"
}

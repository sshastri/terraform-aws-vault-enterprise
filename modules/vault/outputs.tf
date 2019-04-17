output "ip_addresses" {
  value = "${aws_instance.vault.*.private_ip}"
}

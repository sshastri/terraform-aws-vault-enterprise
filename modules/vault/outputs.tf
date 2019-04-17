output "lb_dns_name" {
  value = "${aws_lb.vault_lb.dns_name}"
}

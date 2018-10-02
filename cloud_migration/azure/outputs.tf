# output.tf - outputs important parameters will need to finish configuring vault
# These parameters will but spit out after each terraform apply

output "public-ip" {
  value       = "${azurerm_public_ip.main.ip_address}"
  description = "Public IP Address"
}

# output.tf - outputs important parameters will need to finish configuring vault
# These parameters will but spit out after each terraform apply

output "PUBLIC_IP" {
  value = "ssh -i ${var.keyPairName}.pem ubuntu@${aws_instance.multicloud-demo.public_ip}"
}

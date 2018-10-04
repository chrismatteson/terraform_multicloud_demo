#!/bin/bash

sudo apt install unzip awscli jq -y
wget https://releases.hashicorp.com/vault/0.11.2/vault_0.11.2_linux_amd64.zip
sudo unzip vault_0.11.2_linux_amd64.zip -d /usr/bin
vault server -dev &
sleep 30s
export VAULT_ADDR=http://127.0.0.1:8200
vault auth enable azure
vault secrets enable aws
vault write aws/config/root access_key=$1 secret_key=$2 region=$3
vault write aws/roles/s3-role credential_type=iam_user policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::$4",
        "arn:aws:s3:::$4/*"
      ]
    }
  ]
}
EOF
vault write auth/azure/config tenant_id=$5 resource=https://management.azure.com client_id=$6 client_secret=$7
vault policy write s3-policy -<<EOF
path "aws/creds/s3-role" {
  capabilities = ["read"]
}
EOF
vault write auth/azure/role/dev-role policies=\"s3-policy\" bound_subscription_ids=$8 bound_resource_groups=$9

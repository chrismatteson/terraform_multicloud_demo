#!/bin/bash

sudo apt-get install -y unzip jq
# apt-get install -y libtool libltdl-dev 

USER="vault"
COMMENT="Hashicorp vault user"
GROUP="vault"
HOME="/srv/vault"

# Detect package management system.
YUM=$$(which yum 2>/dev/null)
APT_GET=$$(which apt-get 2>/dev/null)

user_rhel() {
  # RHEL user setup
  sudo /usr/sbin/groupadd --force --system $${GROUP}

  if ! getent passwd $${USER} >/dev/null ; then
    sudo /usr/sbin/adduser \
      --system \
      --gid $${GROUP} \
      --home $${HOME} \
      --no-create-home \
      --comment "$${COMMENT}" \
      --shell /bin/false \
      $${USER}  >/dev/null
  fi
}

user_ubuntu() {
  # UBUNTU user setup
  if ! getent group $${GROUP} >/dev/null
  then
    sudo addgroup --system $${GROUP} >/dev/null
  fi

  if ! getent passwd $${USER} >/dev/null
  then
    sudo adduser \
      --system \
      --disabled-login \
      --ingroup $${GROUP} \
      --home $${HOME} \
      --no-create-home \
      --gecos "$${COMMENT}" \
      --shell /bin/false \
      $${USER}  >/dev/null
  fi
}

if [[ ! -z $${YUM} ]]; then
  logger "Setting up user $${USER} for RHEL/CentOS"
  user_rhel
elif [[ ! -z $${APT_GET} ]]; then
  logger "Setting up user $${USER} for Debian/Ubuntu"
  user_ubuntu
else
  logger "$${USER} user not created due to OS detection failure"
  exit 1;
fi

logger "User setup complete"



VAULT_ZIP="vault.zip"
VAULT_URL=${vault_url}
sudo curl --output /tmp/$${VAULT_ZIP} $${VAULT_URL}
sudo unzip -o /tmp/$${VAULT_ZIP} -d /usr/local/bin/
sudo chmod 0755 /usr/local/bin/vault
sudo chown vault:vault /usr/local/bin/vault
sudo mkdir -pm 0755 /etc/vault.d
sudo mkdir -pm 0755 /opt/vault
sudo chown vault:vault /opt/vault


cat << EOF | sudo tee /lib/systemd/system/vault.service
[Unit]
Description=Vault Agent
Requires=network-online.target
After=network-online.target
[Service]
Restart=on-failure
PermissionsStartOnly=true
ExecStartPre=/sbin/setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault
ExecStart=/usr/local/bin/vault server -config /etc/vault.d
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
User=vault
Group=vault
[Install]
WantedBy=multi-user.target
EOF


cat << EOF | sudo tee /etc/vault.d/vault.hcl
storage "file" {
  path = "/opt/vault"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}
seal "azurekeyvault" {
  tenant_id      = "${azure_tenant_id}"
  vault_name     = "${azure_key_vault}"
  key_name       = "${azure_key_vault_key}"
}
ui=true
EOF


sudo chmod 0664 /lib/systemd/system/vault.service
sudo systemctl daemon-reload
sudo chown -R vault:vault /etc/vault.d
sudo chmod -R 0644 /etc/vault.d/*

cat << EOF | sudo tee /etc/profile.d/vault.sh
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_SKIP_VERIFY=true
EOF

sudo systemctl enable vault
sudo systemctl start vault

sleep 60s
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=`vault operator init -format json | jq -r .root_token`
vault token create -id=${vault_token}
vault auth enable azure
vault secrets enable aws
vault write aws/config/root access_key=${aws_iam_access_key} secret_key=${aws_iam_secret_key} region=${aws_region}
vault write aws/roles/s3-role credential_type=iam_user policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${aws_s3_bucket}",
        "arn:aws:s3:::${aws_s3_bucket}/*"
      ]
    }
  ]
}
EOF
vault write auth/azure/config tenant_id=${azure_tenant_id} resource=https://management.azure.com client_id=${azure_application_id} client_secret=${azure_sp_password}
vault policy write s3-policy -<<EOF
path "aws/creds/s3-role" {
  capabilities = ["read"]
}
EOF
vault write auth/azure/role/dev-role policies=\"s3-policy\" bound_subscription_ids=${azure_subscription_id} bound_resource_groups=${azure_resource_group}

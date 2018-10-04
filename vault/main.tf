provider "azurerm" {}
provider "aws" {
  region     = "${var.aws_region}"
}

# generate random project name
resource "random_id" "project_name" {
  byte_length = 4
}

resource "random_id" "client_secret" {
  byte_length = 32
}

# AWS resources

data "aws_iam_account_alias" "current" {}

resource "aws_s3_bucket" "appdata" {
  bucket = "${random_id.project_name.hex}-appdata"
  acl    = "private"

  tags {
    Name        = "Azure-AWS Vault Demo"
    Environment = "Dev"
  }
}

resource "aws_iam_user" "vault" {
  name = "${random_id.project_name.hex}-vault-user"
  path = "/system/"
}

resource "aws_iam_access_key" "vault" {
  user = "${aws_iam_user.vault.name}"
}

resource "aws_iam_user_policy" "vault_access" {
  name = "${random_id.project_name.hex}-vault-access"
  user = "${aws_iam_user.vault.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "iam:AttachUserPolicy",
        "iam:CreateAccessKey",
        "iam:CreateUser",
        "iam:DeleteAccessKey",
        "iam:DeleteUser",
        "iam:DeleteUserPolicy",
        "iam:DetachUserPolicy",
        "iam:ListAccessKeys",
        "iam:ListAttachedUserPolicies",
        "iam:ListGroupsForUser",
        "iam:ListUserPolicies",
        "iam:PutUserPolicy",
        "iam:RemoveUserFromGroup"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

# Azure Resources
data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "${random_id.project_name.hex}-rg"
  location = "${var.location}"
}

resource "azurerm_azuread_application" "vaultapp" {
  name                       = "${random_id.project_name.hex}-vaultapp"
}

resource "azurerm_azuread_service_principal" "vaultapp" {
  application_id = "${azurerm_azuread_application.vaultapp.application_id}"
}

resource "azurerm_azuread_service_principal_password" "vaultapp" {
  service_principal_id = "${azurerm_azuread_service_principal.vaultapp.id}"
  value                = "${random_id.client_secret.id}" 
  end_date             = "2020-01-01T01:02:03Z"
}

resource "azurerm_virtual_network" "main" {
  name                = "${random_id.project_name.hex}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"
}

resource "azurerm_subnet" "main" {
  name                 = "${random_id.project_name.hex}-subnet"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  address_prefix       = "10.0.1.0/24"
}

# VM Resources
resource "azurerm_public_ip" "main" {
  name                         = "${random_id.project_name.hex}-pubip"
  location                     = "${azurerm_resource_group.main.location}"
  resource_group_name          = "${azurerm_resource_group.main.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_network_interface" "main" {
  name                = "${random_id.project_name.hex}-nic"
  location            = "${azurerm_resource_group.main.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  ip_configuration {
    name                          = "config1"
    subnet_id                     = "${azurerm_subnet.main.id}"
    public_ip_address_id          = "${azurerm_public_ip.main.id}"
    private_ip_address_allocation = "dynamic"
  }
}

resource "azurerm_virtual_machine" "main" {
  name                  = "${random_id.project_name.hex}-vm"
  location              = "${azurerm_resource_group.main.location}"
  resource_group_name   = "${azurerm_resource_group.main.name}"
  network_interface_ids = ["${azurerm_network_interface.main.id}"]
  vm_size               = "Standard_A2_v2"

  identity = {
    type = "SystemAssigned"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${random_id.project_name.hex}vm-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${random_id.project_name.hex}vm"
    admin_username = "ubuntu"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  connection {
    type = "ssh"
    host = "${azurerm_public_ip.main.ip_address}"
    user = "ubuntu"
    password = "Password1234!"
  }

  provisioner "file" {
    source      = "setupvault.sh"
    destination = "/tmp/setupvault.sh"
  }

  provisioner "remote-exec" {    
    inline = [
      "chmod +x /tmp/setupvault.sh",
      "/tmp/setupvault.sh ${aws_iam_access_key.vault.id} ${aws_iam_access_key.vault.secret} ${var.aws_region} ${aws_s3_bucket.appdata.bucket} ${data.azurerm_client_config.current.tenant_id} ${azurerm_azuread_application.vaultapp.application_id} ${azurerm_azuread_service_principal_password.vaultapp.value} ${data.azurerm_client_config.current.subscription_id} ${azurerm_resource_group.main.name}"
    ]
  }
}

resource "azurerm_virtual_machine_extension" "virtual_machine_extension" {
  name                 = "vault"
  location             = "${var.location}"
  resource_group_name  = "${azurerm_resource_group.main.name}"
  virtual_machine_name = "${azurerm_virtual_machine.main.name}"
  publisher            = "Microsoft.ManagedIdentity"
  type                 = "ManagedIdentityExtensionForLinux"
  type_handler_version = "1.0"

  settings = <<SETTINGS
    {
        "port": 50342
    }
SETTINGS
}

data "azurerm_subscription" "subscription" {}

data "azurerm_builtin_role_definition" "builtin_role_definition" {
  name = "Contributor"
}

# Grant the VM identity contributor rights to the current subscription
resource "azurerm_role_assignment" "role_assignment" {
  scope              = "${data.azurerm_subscription.subscription.id}"
  role_definition_id = "${data.azurerm_subscription.subscription.id}${data.azurerm_builtin_role_definition.builtin_role_definition.id}"
  principal_id       = "${lookup(azurerm_virtual_machine.main.identity[0], "principal_id")}"

  lifecycle {
    ignore_changes = ["name"]
  }
}

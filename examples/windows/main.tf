terraform {
  required_version = ">= 1.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.83, < 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
This variable controls whether or not telemetry is enabled for the module.
For more information see https://aka.ms/avm/telemetryinfo.
If it is set to false, then no telemetry will be collected.
DESCRIPTION
}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = "eastus"
  name     = module.naming.resource_group.name_unique
  tags = {
    source = "AVM Sample Windows Deployment"
  }
}

resource "azurerm_virtual_network" "this" {
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  name                = module.naming.virtual_network.name_unique
  resource_group_name = azurerm_resource_group.this.name
  dns_servers         = ["10.0.0.4", "10.0.0.5"]
  tags = {
    source = "AVM Sample Windows Deployment"
  }
}

resource "azurerm_subnet" "subnet" {
  address_prefixes     = ["10.0.1.0/24"]
  name                 = "VMSS-Subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
}

resource "azurerm_public_ip" "natgwpip" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.this.location
  name                = module.naming.public_ip.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  tags = {
    source = "AVM Sample Windows Deployment"
  }
  zones = ["1", "2", "3"]
}

resource "azurerm_nat_gateway" "this" {
  location            = azurerm_resource_group.this.location
  name                = "MyNatGateway"
  resource_group_name = azurerm_resource_group.this.name
  tags = {
    source = "AVM Sample Windows Deployment"
  }
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.natgwpip.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  nat_gateway_id = azurerm_nat_gateway.this.id
  subnet_id      = azurerm_subnet.subnet.id
}

resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# This is the module call
module "terraform-azurerm-avm-res-compute-virtualmachinescaleset" {
  source = "../../"
  # source             = "Azure/avm-res-compute-virtualmachinescaleset/azurerm"
  admin_password              = "P@ssw0rd1234!"
  name                        = module.naming.virtual_machine_scale_set.name_unique
  resource_group_name         = azurerm_resource_group.this.name
  enable_telemetry            = var.enable_telemetry
  location                    = azurerm_resource_group.this.location
  platform_fault_domain_count = 1
  network_interface = [{
    name = "VMSS-NIC"
    ip_configuration = [{
      name      = "VMSS-IPConfig"
      subnet_id = azurerm_subnet.subnet.id
    }]
  }]
  os_profile = {
    windows_configuration = {
      disable_password_authentication = false
      admin_username                  = "azureuser"
      license_type                    = "None"
      # hotpatching_enabled             = true
      patch_assessment_mode = "ImageDefault"
      patch_mode            = "AutomaticByOS"
      timezone              = "Pacific Standard Time"
      provision_vm_agent    = true
      winrm_listener = [{
        protocol = "Http"
      }]
    }
  }
  source_image_reference = {
    publisher = "MicrosoftWindowsServer" # 2022-datacenter-azure-edition
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
  tags = {
    source = "AVM Sample Windows Deployment"
  }
  depends_on = [azurerm_subnet_nat_gateway_association.this]
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "virtual_machine_scale_set_id" {
  value = module.terraform-azurerm-avm-res-compute-virtualmachinescaleset.resource
}

output "virtual_machine_scale_set_unique_id" {
  value = module.terraform-azurerm-avm-res-compute-virtualmachinescaleset.unique_id
}

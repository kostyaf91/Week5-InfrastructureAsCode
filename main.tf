# Azure provider configuration
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }
  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

# Resource group creation
resource "azurerm_resource_group" "rg" {
  name     = "week-5-project"
  location = "eastus"

  tags = {
    Owner = "Kostya Filimonov"
  }
}

# Virtual network creation
resource "azurerm_virtual_network" "vnet" {
  name                = "week5-vnet"
  location            = var.rg-location
  resource_group_name = var.rg-name
  address_space       = ["10.0.0.0/16"]
  depends_on          = [azurerm_resource_group.rg]
}

# Subnets creation
resource "azurerm_subnet" "public-subnet" {
  name                 = "public-subnet"
  resource_group_name  = var.rg-name
  virtual_network_name = var.vn-name
  address_prefixes     = ["10.0.0.0/24"]
  depends_on           = [azurerm_resource_group.rg, azurerm_virtual_network.vnet]
}
resource "azurerm_subnet" "private-subnet" {
  name                 = "private-subnet"
  resource_group_name  = var.rg-name
  virtual_network_name = var.vn-name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on = [azurerm_resource_group.rg, azurerm_virtual_network.vnet]
}

#Public IP creation
resource "azurerm_public_ip" "vmss-public-ip" {
  name                = "vmss-public-ip"
  location            = var.rg-location
  resource_group_name = var.rg-name
  allocation_method   = "Static"
  depends_on          = [azurerm_resource_group.rg]
}

# Load balancer creation
resource "azurerm_lb" "vmss-lb" {
  name                = "vmss-lb"
  location            = var.rg-location
  resource_group_name = var.rg-name
  depends_on          = [azurerm_resource_group.rg]

  frontend_ip_configuration {
    name                 = "lb-public-ip"
    public_ip_address_id = azurerm_public_ip.vmss-public-ip.id
    public_ip_prefix_id  = azurerm_public_ip.vmss-public-ip.public_ip_prefix_id
  }
}
resource "azurerm_lb_backend_address_pool" "lb-backend-address-pool" {
  loadbalancer_id = azurerm_lb.vmss-lb.id
  name            = "lb-backend-address-pool"
}
resource "azurerm_lb_probe" "lb-probe" {
  loadbalancer_id     = azurerm_lb.vmss-lb.id
  name                = "lb-probe-8080"
  port                = 8080
  resource_group_name = var.rg-name
  depends_on          = [azurerm_resource_group.rg]
}
resource "azurerm_lb_rule" "lb_rule_8080" {
  backend_port                   = 8080
  frontend_ip_configuration_name = azurerm_lb.vmss-lb.frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb-backend-address-pool.id]
  frontend_port                  = 8080
  loadbalancer_id                = azurerm_lb.vmss-lb.id
  name                           = "lb_rule_8080"
  protocol                       = "Tcp"
  resource_group_name            = var.rg-name
  depends_on                     = [azurerm_resource_group.rg, azurerm_public_ip.vmss-public-ip]
}

# VM scale set creation
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "vmss"
  admin_username      = var.server_username
  admin_password      = var.server_password
  instances           = 1
  location            = var.rg-location
  resource_group_name = var.rg-name
  sku                 = "Standard_B2s"
  #upgrade_mode                    = "Automatic"
  disable_password_authentication = false
  depends_on                      = [azurerm_resource_group.rg]

  network_interface {
    name                      = "netInterface"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.public-nsg.id
    ip_configuration {
      name                                   = "vmss-ip-config"
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.lb-backend-address-pool.id]
      subnet_id                              = azurerm_subnet.public-subnet.id
      primary                                = true
      public_ip_address {
        name = "vmss-ip"
      }
    }
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

# NSG creation
resource "azurerm_network_security_group" "public-nsg" {
  location            = var.rg-location
  name                = "public-nsg"
  resource_group_name = var.rg-name
  depends_on          = [azurerm_resource_group.rg]


  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "allow-8080"
    priority                   = 100
    protocol                   = "Tcp"
    destination_port_range     = "8080"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "allow-ssh"
    priority                   = 110
    protocol                   = "Tcp"
    source_address_prefix      = "77.137.64.220"
    destination_port_range     = "22"
    source_port_range          = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    access                     = "Deny"
    direction                  = "Inbound"
    name                       = "deny-ssh"
    priority                   = 120
    protocol                   = "Tcp"
    destination_port_range     = "22"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_security_group" "private-nsg" {
  location            = var.rg-location
  name                = "private-nsg"
  resource_group_name = var.rg-name
  depends_on          = [azurerm_resource_group.rg]

  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "allow-postgres"
    priority                   = 100
    protocol                   = "Tcp"
    source_address_prefix      = azurerm_subnet.public-subnet.address_prefix
    destination_port_range     = "5432"
    source_port_range          = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    access                     = "Deny"
    direction                  = "Inbound"
    name                       = "deny-postgres"
    priority                   = 110
    protocol                   = "Tcp"
    destination_port_range     = "5432"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    access                     = "Allow"
    direction                  = "Inbound"
    name                       = "allow-ssh"
    priority                   = 120
    protocol                   = "Tcp"
    source_address_prefix      = azurerm_subnet.public-subnet.address_prefix
    destination_port_range     = "22"
    source_port_range          = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    access                     = "Deny"
    direction                  = "Inbound"
    name                       = "deny-ssh"
    priority                   = 130
    protocol                   = "Tcp"
    destination_port_range     = "22"
    source_port_range          = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
#NSG association subnets
resource "azurerm_subnet_network_security_group_association" "nsg-to-public" {
  network_security_group_id = azurerm_network_security_group.public-nsg.id
  subnet_id                 = azurerm_subnet.public-subnet.id
}
resource "azurerm_subnet_network_security_group_association" "nsg-to-private" {
  network_security_group_id = azurerm_network_security_group.private-nsg.id
  subnet_id                 = azurerm_subnet.private-subnet.id
}

# VM scale set autoscale setting
resource "azurerm_monitor_autoscale_setting" "vm-autoscale" {
  location            = var.rg-location
  name                = "vm-autoscale"
  resource_group_name = var.rg-name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id
  depends_on          = [azurerm_resource_group.rg, azurerm_linux_virtual_machine_scale_set.vmss]
  profile {
    name = "AutoScale"
    capacity {
      default = 3
      maximum = 5
      minimum = 1
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        operator           = "GreaterThan"
        statistic          = "Average"
        threshold          = 75
        time_aggregation   = "Average"
        time_grain         = "PT1M"
        time_window        = "PT5M"
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
      }
      scale_action {
        cooldown  = "PT1M"
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
      }
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}

# Postgres DB creation
resource "azurerm_network_interface" "db-network-interface" {
  location            = var.rg-location
  name                = "db-network-interface"
  resource_group_name = var.rg-name
  ip_configuration {
    name                          = "db-ip-config"
    private_ip_address_allocation = "Dynamic"
    private_ip_address            = ""
    subnet_id                     = azurerm_subnet.private-subnet.id
  }
  depends_on = [azurerm_resource_group.rg]
}
resource "azurerm_linux_virtual_machine" "db-server" {
  admin_username                  = var.server_username
  admin_password                  = var.server_password
  location                        = var.rg-location
  name                            = "db-server"
  network_interface_ids           = [azurerm_network_interface.db-network-interface.id]
  resource_group_name             = var.rg-name
  size                            = "Standard_B2s"
  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }
}

# Terraform state creation
resource "azurerm_storage_account" "kostyaf91tfstate" {
  account_replication_type = "LRS"
  account_tier             = "Standard"
  location                 = var.rg-location
  name                     = "kostyaf91tfstate"
  resource_group_name      = var.rg-name
  allow_blob_public_access = true
}

resource "azurerm_storage_container" "tf-state-container" {
  name                 = "tf-state-container"
  storage_account_name = azurerm_storage_account.kostyaf91tfstate.name
  container_access_type = "blob"
}





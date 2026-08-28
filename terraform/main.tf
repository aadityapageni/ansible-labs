terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "winrm" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "winrm" {
  name                = "winrm-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.winrm.location
  resource_group_name = azurerm_resource_group.winrm.name
}

resource "azurerm_subnet" "default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.winrm.name
  virtual_network_name = azurerm_virtual_network.winrm.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_network_security_group" "winrm" {
  name                = "winrm-nsg"
  location            = azurerm_resource_group.winrm.location
  resource_group_name = azurerm_resource_group.winrm.name

  security_rule {
    name                       = "RDP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 310
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "WinRM-HTTPS"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 330
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "winrm" {
  name                = "winrm-ip"
  location            = azurerm_resource_group.winrm.location
  resource_group_name = azurerm_resource_group.winrm.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
}

resource "azurerm_network_interface" "winrm" {
  name                = "winrm815_z1"
  location            = azurerm_resource_group.winrm.location
  resource_group_name = azurerm_resource_group.winrm.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.winrm.id
  }
}

resource "azurerm_network_interface_security_group_association" "winrm" {
  network_interface_id      = azurerm_network_interface.winrm.id
  network_security_group_id = azurerm_network_security_group.winrm.id
}

resource "azurerm_windows_virtual_machine" "winrm" {
  name                = "winrm"
  resource_group_name = azurerm_resource_group.winrm.name
  location            = azurerm_resource_group.winrm.location
  size                = "Standard_B2s"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  zone                = "1"

  network_interface_ids = [
    azurerm_network_interface.winrm.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "microsoftwindowsserver"
    offer     = "windowsserver2022"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  boot_diagnostics {}

  patch_mode   = "AutomaticByOS"

  additional_capabilities {
    hibernation_enabled = false
  }
}

resource "azurerm_virtual_machine_extension" "custom_script" {
  name                 = "CustomScriptExtension"
  virtual_machine_id   = azurerm_windows_virtual_machine.winrm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = jsonencode({
    fileUris = [
      "https://winrmstartsmall.blob.core.windows.net/winrm-scripts/ConfigureRemotingForAnsible.ps1?se=2026-11-24&sp=r&spr=https&sv=2026-04-06&sr=b&sig=YheEzZvpU3EIudMBZd5Vt1KNS7IW4qpZB8y3jRkxykA%3D"
    ]
    commandToExecute = "powershell -ExecutionPolicy Bypass -File ConfigureRemotingForAnsible.ps1"
  })

  depends_on = [
    azurerm_windows_virtual_machine.winrm
  ]
}

resource "azurerm_virtual_machine_extension" "openssh" {
  name                       = "InstallOpenSSH"
  virtual_machine_id         = azurerm_windows_virtual_machine.winrm.id
  publisher                  = "Microsoft.Azure.OpenSSH"
  type                       = "WindowsOpenSSH"
  type_handler_version       = "3.0"
  auto_upgrade_minor_version = true

  depends_on = [
    azurerm_virtual_machine_extension.custom_script
  ]
}

resource "azurerm_virtual_machine_extension" "ssh_key" {
  name                       = "CopySSHKey"
  virtual_machine_id         = azurerm_windows_virtual_machine.winrm.id
  publisher                  = "Microsoft.CPlat.Core"
  type                       = "RunCommandWindows"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    script = [
      "Add-Content 'C:\\ProgramData\\ssh\\administrators_authorized_keys' -Value '${var.ssh_public_key}' -Encoding UTF8",
      "icacls.exe 'C:\\ProgramData\\ssh\\administrators_authorized_keys' /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'"
    ]
  })

  depends_on = [
    azurerm_virtual_machine_extension.openssh
  ]
}

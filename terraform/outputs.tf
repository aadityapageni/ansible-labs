output "admin_username" {
  value = var.admin_username
}

output "public_ip_address" {
  value = azurerm_public_ip.winrm.ip_address
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.winrm.name
}

output "vmss-pass" {
  value = azurerm_linux_virtual_machine_scale_set.vmss.admin_password
  sensitive = true
}
output "db-pass" {
  value = azurerm_linux_virtual_machine.db-server.admin_password
  sensitive = true
}

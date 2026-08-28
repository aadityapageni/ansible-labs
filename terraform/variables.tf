variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "winrm_group"
}

variable "admin_username" {
  description = "VM admin username"
  type        = string
  default     = "wakizu"
}

variable "admin_password" {
  description = "VM admin password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for OpenSSH"
  type        = string
}

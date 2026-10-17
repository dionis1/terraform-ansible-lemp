variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "lemp-server"
}

variable "memory_mb" {
  description = "VM memory in MB"
  type        = number
  default     = 2048
}

variable "vcpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 2
}

variable "disk_size_gb" {
  description = "VM disk capacity in GiB (must be at least the base image virtual size)"
  type        = number
  default     = 20
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized for the devops user"
  type        = string
  default     = "~/.ssh/terraform-lemp.pub"
}

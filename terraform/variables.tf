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
  description = "Disk size in GB"
  type        = number
  default     = 20
}
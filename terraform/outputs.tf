output "vm_name" {
  description = "Name of the virtual machine"
  value       = libvirt_domain.vm.name
}

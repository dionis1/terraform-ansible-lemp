# terraform-ansible-lemp

Terraform provisions an Ubuntu 24.04 VM on local libvirt/KVM. The Terraform
configuration uses dmacvicar/libvirt 0.9.x, with 0.9.9 recorded in the lock file.

## Prerequisites

Install Terraform, libvirt/KVM, curl, qemu-img, and the cloud-init ISO tooling
(`xorriso`). Your user must be able to access `qemu:///system`. The libvirt
`default` storage pool and NAT network must already exist and be active.

## Download the Ubuntu image

From the repository root:

```bash
cd terraform
curl --fail --location --output ubuntu-24.04-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
qemu-img info ubuntu-24.04-server-cloudimg-amd64.img
```

The downloaded image is intentionally ignored by Git. Its URL points to the
current Ubuntu 24.04 release image; the download is not pinned to a checksum.

## Configure SSH and VM size

Use an existing SSH key pair, or create a dedicated one if it does not exist:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/terraform-lemp -C terraform-lemp
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set `ssh_public_key_path` to your **public** key
(the `.pub` file). Terraform expands `~`. The corresponding private key stays
on your host and is used to connect as `devops`.

`disk_size_gb` sets the VM disk capacity in GiB (default: 20). It must be at
least the downloaded image's virtual size reported by `qemu-img info`.
Terraform uploads a base image and creates a QCOW2 overlay of the requested
capacity. Cloud-init expands the root partition and filesystem on first boot.
Keep the base volume: the VM disk depends on it.

## Deploy

```bash
terraform init
terraform validate
terraform plan
terraform apply
virsh -c qemu:///system net-dhcp-leases default
ssh -i ~/.ssh/terraform-lemp devops@VM_IP
```

Replace `VM_IP` with the DHCP address. Inside the VM, check:

```bash
cloud-init status --wait
lsblk
df -h /
```

## Existing deployments

Changing from the earlier uploaded boot disk to the base/overlay layout may
replace the boot disk. Review the plan and back up any needed data before
applying. This is a provisioning layout, not an in-place disk resize procedure.
Changing the public key in cloud-init does not reliably update an already
initialized guest; update its authorized_keys separately or reprovision it.
Local state, tfvars, private keys, and image files must remain out of Git.

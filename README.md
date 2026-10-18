# Terraform + Ansible + Docker LEMP

A local DevOps portfolio project that provisions an Ubuntu VM, configures Linux
and Docker, and deploys an NGINX/PHP/MariaDB application. The PHP page opens a
real database connection and runs `SELECT 1`; database failures return HTTP 503.

## Architecture

```text
Terraform → libvirt/KVM Ubuntu 24.04 VM
                     ↓
               cloud-init: SSH user, root filesystem growth, guest agent
                     ↓
               Ansible: common → docker → lemp
                     ↓
               NGINX :8080 → PHP-FPM → MariaDB
```

MariaDB uses a named volume for persistence and an internal backend network.
NGINX and PHP share a web network. Only NGINX publishes an application port.
The Terraform VM includes the virtio channel required by the QEMU guest agent.

## Repository

- `terraform/`: VM, base image, sized QCOW2 overlay, cloud-init and provider lock.
- `ansible/`: inventory, roles, collection requirements and Vault-encrypted credentials.
- `docker/`: Compose stack, NGINX configuration, PHP Dockerfile and credential example.
- `app/index.php`: application and live database connectivity check.
- `scripts/smoke-test.sh`: independent HTTP/database smoke test.

## Prerequisites

Use a Linux host with libvirt/KVM, Terraform (>=1.5), Ansible, curl, Python 3,
qemu-img and xorriso. Your user needs access to `qemu:///system`; libvirt's
`default` NAT network and storage pool must exist and be active.
The committed lock file selects dmacvicar/libvirt 0.9.9. Configuration uses the
0.9.x schema and is incompatible with the older 0.8.x provider.

## 1. Prepare the VM

From the repository root:

```bash
cd terraform
curl --fail --location --output ubuntu-24.04-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
qemu-img info ubuntu-24.04-server-cloudimg-amd64.img
```

The image is ignored by Git. This release URL is mutable and not checksum-pinned.
Use an existing SSH key pair or create a dedicated one if the path is unused:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/terraform-lemp -C terraform-lemp
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. `ssh_public_key_path` points to the `.pub` file;
keep the private key on your host. `disk_size_gb` is capacity in GiB (default
20), and must be at least the base image's virtual size. Terraform creates a
base volume and a sized QCOW2 overlay; cloud-init grows the guest root filesystem.
Keep the base volume because the overlay depends on it.

```bash
terraform init
terraform validate
terraform plan
terraform apply
virsh -c qemu:///system net-dhcp-leases default
```

Set `ansible_host` in `ansible/inventory.ini` to the VM's current lease and check
the SSH key path. The committed address is an example from this local lab;
DHCP addresses can change. Inside the VM, wait for initialization:

```bash
ssh -i ~/.ssh/terraform-lemp devops@VM_IP
cloud-init status --wait
lsblk
df -h /
exit
```

## 2. Configure database secrets with Ansible Vault

From the repository root:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

`ansible/files/lemp.env` is encrypted and safe to commit. Its Vault password is
not committed. On the original development host, `.vault-pass` is an ignored,
mode-0600 password file. Back it up securely outside the repository; losing it
means losing access to this encrypted file. The old ignored `docker/.env` is
retained locally but is no longer the playbook's credential source.

To use the existing encrypted credentials with the local password file:

```bash
ansible-vault edit --vault-password-file .vault-pass ansible/files/lemp.env
```

For a fresh clone with your own database credentials, create a local environment
file from the example, replace all placeholder passwords, and encrypt it with
your own Vault password (the command prompts for that password):

```bash
cp docker/.env.example docker/.env
# Edit docker/.env with your chosen database name, user and passwords.
ansible-vault encrypt --output ansible/files/lemp.env docker/.env
```

Use simple single-line credentials compatible with Docker Compose dotenv syntax;
for example, long random hexadecimal passwords avoid quoting/interpolation issues.
Never commit plaintext `.env` files or Vault passwords. Use `ansible-vault edit`
to edit encrypted secrets, rather than decrypting them in place.

Ansible decrypts the file when copying it to `/opt/lemp/.env`, owned by root with
mode 0600. The copy task uses `no_log: true`. Vault protects repository secrets
at rest; the deployed file and container environment still contain credentials.

## 3. Deploy the application

From the repository root, using the original host's password file:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  --vault-password-file .vault-pass --syntax-check
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  --vault-password-file .vault-pass
```

For your own prompted Vault password, replace `--vault-password-file .vault-pass`
with `--ask-vault-pass`. The roles install packages and Docker, copy application
files, decrypt the environment file and start Compose. The final HTTP check
retries until the page returns 200 and includes `Connected`.

Visit `http://VM_IP:8080/`. Rerun the same playbook to inspect idempotency;
`changed=0 failed=0 unreachable=0` is the target for an unchanged deployment,
although expired APT cache updates may legitimately report changes.

## 4. Run the independent smoke test

```bash
./scripts/smoke-test.sh http://VM_IP:8080/
```

Requires curl and Python 3. The script checks HTTP 200 and the visible
`Database connection: Connected` status. Connection failures, request timeouts,
unexpected HTTP status and missing database success all return nonzero.
With no URL it checks `http://127.0.0.1:8080/` on the machine running the script.

On the VM, additional read-only diagnostics are:

```bash
cd /opt/lemp
sudo docker compose ps
sudo docker compose logs --tail=50
systemctl status qemu-guest-agent --no-pager
```

## Persistence and recovery exercises

MariaDB stores data in the Compose `db_data` volume. A healthy container does
not prove persistence or backups. Test persistence separately with disposable
data and verify it after recreating only the database container. Do not use
`docker compose down -v` unless you intend to delete database data.

To test failure detection in this lab, stop the `db` service on the VM, run the
smoke test from the host and expect failure, then start `db`, wait for health,
and rerun the test expecting success. This is an optional disruptive exercise;
it is not part of the smoke-test script or normal deployment.

Changing MariaDB environment passwords does not rotate users in an initialized
data volume. Coordinate credential changes with SQL user updates and backups.
Changing a cloud-init SSH key does not reliably update an initialized guest.
Changing the Terraform disk layout can replace a boot volume; inspect the plan
and back up needed data. This project does not implement in-place disk resizing.

## Scope and limitations

This is a local portfolio lab. It demonstrates reproducible infrastructure,
configuration management, encrypted repository secrets and application-level
verification. It does not provide TLS, automated backups, monitoring, CI, image
digest pinning or a production secret manager. Database persistence and outage
recovery require separate execution and evidence; configuration alone is not proof.

Terraform state, local tfvars, private keys, Vault password files, plaintext
credentials and VM images are ignored. The provider lock and encrypted Vault
file are committed. Never publish raw Terraform state or rendered Compose
configuration containing secrets.

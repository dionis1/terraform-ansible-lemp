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
- `ansible/`: example inventory, roles, pinned collection and Vault-encrypted credentials.
- `docker/`: Compose stack, NGINX configuration, PHP Dockerfile and credential example.
- `app/index.php`: application and live database connectivity check.
- `scripts/generate-inventory.py`: Terraform-to-Ansible inventory handoff.
- `scripts/download-cloud-image.sh`: checksum-verified image download.
- `scripts/smoke-test.sh`: independent HTTP/database smoke test.
- `scripts/db-recovery-test.sh`: backup restore, persistence and outage exercise.
- `docs/evidence/`: recorded validation results from the lab.

## Prerequisites

Use a Linux host with libvirt/KVM, Terraform (>=1.5), Ansible, curl, Python 3,
qemu-img and xorriso. Your user needs access to `qemu:///system`; libvirt's
`default` NAT network and storage pool must exist and be active.
The committed lock file selects dmacvicar/libvirt 0.9.9. Configuration uses the
0.9.x schema and is incompatible with the older 0.8.x provider.

## 1. Prepare the VM

From the repository root:

```bash
./scripts/download-cloud-image.sh
cd terraform
qemu-img info ubuntu-24.04-server-cloudimg-amd64.img
```

The image is ignored by Git. The download script pins Ubuntu's dated
`release-20260926` build and verifies the SHA-256 in `terraform/cloud-image.sha256`.
It refuses to overwrite an existing image that fails verification. Terraform
also verifies the checksum before provisioning the base volume. The checksum
was obtained from Ubuntu's HTTPS-published checksum list:
https://cloud-images.ubuntu.com/releases/noble/release-20260926/SHA256SUMS
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

From the repository root, generate the local inventory automatically:

```bash
cd ..
./scripts/generate-inventory.py
# For a different private key:
# ./scripts/generate-inventory.py --ssh-key ~/.ssh/my-key
```

The script reads Terraform's `vm_name` output and queries that domain's current
libvirt DHCP lease. It waits up to 120 seconds and writes an ignored local
`ansible/inventory.ini`. Rerun it after VM recreation or DHCP changes. No guest
agent is needed for discovery. For manual configuration, copy
`ansible/inventory.ini.example` and replace its documentation-only IP and key path.
The generator requires Terraform state, virsh access and an existing private key.

Inside the VM, wait for initialization:

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
ansible-galaxy collection install -r ansible/requirements.yml -p .ansible/collections
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

The 3.8.0 pin includes the upstream fix that stops classifying Compose's
health-check `Waiting` event as a deployment change. The system's older 3.7.0
reported a false change even when no containers were recreated. See
[the upstream changelog](https://github.com/ansible-collections/community.docker/blob/main/CHANGELOG.rst#v380).

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

## 5. Verify persistence, backup restore and outage recovery

Recorded results are in [the verification report](docs/evidence/verification.md).
The report links an unchanged second Ansible run and the recovery transcript.
These are observations from this local lab, not a guarantee of future runs.

The repeatable exercise runs **on the VM as root** and briefly interrupts the
database. It creates a dedicated `portfolio_verification` test schema, refuses
to overwrite an existing schema with that name, and cleans up its test data.

From the repository root, copy both scripts to a temporary directory on the VM:

```bash
ssh -i ~/.ssh/terraform-lemp devops@VM_IP 'mkdir -p /tmp/lemp-verification'
scp -i ~/.ssh/terraform-lemp scripts/smoke-test.sh scripts/db-recovery-test.sh \
  devops@VM_IP:/tmp/lemp-verification/
ssh -i ~/.ssh/terraform-lemp devops@VM_IP \
  'sudo bash /tmp/lemp-verification/db-recovery-test.sh'
```

The script performs:

1. A baseline HTTP/database smoke test.
2. A transactional logical backup of the application database and a disposable
   marker schema into `/var/backups/lemp/` (root-only directory, mode-0600 dump).
3. Restoration into a separate disposable MariaDB container with an isolated
   volume, no published ports and no network. Marker values and normalized
   application dump hashes must match; the live database is never overwritten.
4. Recreation of the live database container while retaining its named volume;
   the marker must survive and the application must pass its smoke test.
5. A database stop; the app must return HTTP 503 and the smoke test must fail.
6. Database restart, readiness and a successful application smoke test.

An exit trap attempts to restart the database on errors and removes the test
schema and temporary restore container/volume. Backups remain root-only on the
VM and are not committed. Review logs and restore service manually if the host
or Docker fails during cleanup. This is a logical restore demonstration, not
scheduled backup automation or a full disaster recovery solution.

MariaDB uses the Compose `db_data` volume. Do not use `docker compose down -v`
unless you intend to delete database data.

Changing MariaDB environment passwords does not rotate users in an initialized
data volume. Coordinate credential changes with SQL user updates and backups.
Changing a cloud-init SSH key does not reliably update an initialized guest.
Changing the Terraform disk layout can replace a boot volume; inspect the plan
and back up needed data. This project does not implement in-place disk resizing.

## Reproducibility and scope

- Ubuntu cloud image: dated build plus pinned SHA-256, checked on download and
  by Terraform. Review and update the URL and checksum together for upgrades.
- NGINX and MariaDB: tag plus immutable digest in Compose.
- PHP base image: immutable digest in the Dockerfile. Ansible rebuilds the PHP
  image when the deployed Dockerfile changes; normal unchanged runs use policy.
- `community.docker`: exactly 3.8.0, with its inventory utility dependency
  pinned to 1.0.0, in `ansible/requirements.yml`. Project `ansible.cfg` selects
  the local collection installation; run commands from the repository root.
- Terraform provider: 0.9.9 selected by the committed lock file.

These pins do not make the entire host byte-for-byte reproducible: APT packages,
PHP build dependencies and the host toolchain are not fully version-locked.
Digest pins also need deliberate security updates. This is an amd64 local lab;
Docker's APT repository configuration currently assumes amd64.

This project demonstrates infrastructure provisioning, Linux configuration,
encrypted repository secrets, application verification and recovery exercises.
It does not provide TLS, scheduled backups, monitoring, CI or a production
secret manager. See the evidence report for exactly what was tested.

Terraform state, local tfvars, private keys, Vault password files, plaintext
credentials and VM images are ignored. The provider lock and encrypted Vault
file are committed. Never publish raw Terraform state or rendered Compose
configuration containing secrets.

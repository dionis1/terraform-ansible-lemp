# Lab verification — 18 October 2026

Executed against the local Ubuntu 24.04 amd64 libvirt VM. Recovery transcript
timestamps are UTC. Commands below ran from the repository root unless stated
otherwise. No database passwords, Vault password or database dumps are included.

## Observed results

| Check | Actual result | Evidence |
| --- | --- | --- |
| Terraform drift and image precondition | No infrastructure changes | [Terraform plan](terraform-plan.txt) |
| Inventory handoff | Generator read Terraform vm_name and found the matching libvirt IPv4 lease; Ansible connected through the generated inventory | [Generator](../../scripts/generate-inventory.py), playbook logs below |
| Consecutive Ansible run 1 | ok=19, changed=0, unreachable=0, failed=0, skipped=1 | [First run](ansible-first-run.txt) |
| Consecutive Ansible run 2 | ok=19, changed=0, unreachable=0, failed=0, skipped=1 | [Second run](ansible-second-run.txt) |
| Isolated backup restore | Restored marker equals source; normalized application dump SHA-256 hashes match | [Recovery transcript](database-recovery.txt) |
| Persistence | Container ID changed; marker row survived recreation using the existing volume | [Recovery transcript](database-recovery.txt) |
| Database outage | HTTP 503; smoke test returned nonzero | [Recovery transcript](database-recovery.txt) |
| Recovery | Database restarted and application smoke test passed | [Recovery transcript](database-recovery.txt) |

## Reproduce deployment verification

```bash
./scripts/download-cloud-image.sh
./scripts/generate-inventory.py
ansible-galaxy collection install -r ansible/requirements.yml -p .ansible/collections
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --vault-password-file .vault-pass
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --vault-password-file .vault-pass
./scripts/smoke-test.sh http://VM_IP:8080/
```

Use your own Vault password as described in the README. The logs record
consecutive runs after deployment of the pinned container configuration.
`community.docker` 3.7.0 initially reported changed=1 solely for a Compose
`Waiting` event. The project now pins 3.8.0, whose upstream fix treats that as
waiting rather than a change. No blanket `changed_when: false` was added to
the deployment task to conceal changes.

## Recovery method and limits

The exercise used [db-recovery-test.sh](../../scripts/db-recovery-test.sh),
invoked on the VM as root with smoke-test.sh beside it. It created a separate
`portfolio_verification` schema containing one random marker row. The PHP app
currently performs connectivity checks and has no application tables; therefore
the marker explicitly provides nonempty data for persistence and restore tests.
The application database was backed up as well, and its normalized logical dump
was compared between source and restore target.

A compressed transactional logical dump was stored under `/var/backups/lemp/`.
The directory is root-only and the resulting file's mode was independently
verified as 0600. The backup restored into a disposable container from the same
pinned MariaDB image, with a separate volume and `--network none`. The running
application database was not overwritten during restore.

The live database container was then recreated with its existing named volume,
and the marker survived. Stopping the database produced the expected HTTP 503
and failed smoke test. Restarting it restored HTTP 200 and database connectivity.
The `FAIL: expected HTTP 200, received 503` line in the transcript is intentional:
it demonstrates the negative test succeeding.

Afterward, the marker schema, temporary restore container and temporary restore
volume were removed. MariaDB was healthy and a final host-side smoke test passed.
The protected backup remains on the VM. No plaintext backup or database contents
were committed. This demonstrates a lab logical restore and a brief database
outage; it does not establish scheduled backups, full-host recovery, production
RPO/RTO guarantees or behavior under concurrent application writes.

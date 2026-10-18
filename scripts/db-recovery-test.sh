#!/usr/bin/env bash
# Run on the VM as root. Briefly interrupts the database and writes a test schema.
set -euo pipefail
umask 077
[[ $EUID -eq 0 ]] || { echo "Run with sudo on the VM" >&2; exit 1; }
compose=(docker compose -f /opt/lemp/compose.yaml)
smoke="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/smoke-test.sh"
[[ -x "$smoke" ]] || { echo "Place smoke-test.sh beside this script" >&2; exit 1; }
restore="lemp-restore-check-$$"
volume="$restore-data"
password_file=$(mktemp)
backup=""
fixture_created=false
recovery_needed=false

sql() {
  "${compose[@]}" exec -T db sh -c \
    'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot --batch --skip-column-names' <<< "$1"
}
wait_db() {
  for ((i=0; i<60; i++)); do
    if "${compose[@]}" exec -T db sh -c \
      'exec healthcheck.sh --connect --innodb_initialized' >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Database did not become ready" >&2
  return 1
}
cleanup() {
  rc=$?
  trap - EXIT
  if $recovery_needed; then
    "${compose[@]}" start db >/dev/null || rc=1
    wait_db || rc=1
  fi
  if $fixture_created; then
    sql 'DROP DATABASE IF EXISTS portfolio_verification;' >/dev/null || rc=1
  fi
  docker rm -f "$restore" >/dev/null 2>&1 || true
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume rm "$volume" >/dev/null || rc=1
  fi
  rm -f "$password_file"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Started: %s\n' "$(date -u +%FT%TZ)"
"$smoke" http://127.0.0.1:8080/
wait_db
# Refuse to overwrite a pre-existing schema with the same test name.
[[ "$(sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='portfolio_verification';")" == 0 ]] || {
  echo "Test schema already exists; investigate before rerunning" >&2; exit 1;
}
fixture_created=true
marker=$(cat /proc/sys/kernel/random/uuid)
sql "CREATE DATABASE portfolio_verification;
CREATE TABLE portfolio_verification.marker (id INT PRIMARY KEY, token VARCHAR(36) NOT NULL);
INSERT INTO portfolio_verification.marker VALUES (1, '$marker');" >/dev/null

mkdir -p /var/backups/lemp
chmod 700 /var/backups/lemp
backup="/var/backups/lemp/$(date -u +%Y%m%dT%H%M%SZ)-$$.sql.gz"
"${compose[@]}" exec -T db sh -c \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb-dump -uroot --single-transaction --routines --events --triggers --databases "$MARIADB_DATABASE" portfolio_verification' | gzip > "$backup"
gzip --test "$backup"
printf 'PASS: logical backup written with mode 0600: %s\n' "$backup"
database=$("${compose[@]}" exec -T db printenv MARIADB_DATABASE)
source_hash=$("${compose[@]}" exec -T db sh -c \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb-dump -uroot --single-transaction --compact --skip-comments --skip-dump-date --order-by-primary "$MARIADB_DATABASE"' | sha256sum | cut -d' ' -f1)

# Restore into an isolated disposable container; never overwrite the live database.
printf 'MARIADB_ROOT_PASSWORD=%s\n' "$(cat /proc/sys/kernel/random/uuid)" > "$password_file"
image=$(docker inspect --format '{{.Config.Image}}' "$("${compose[@]}" ps -q db)")
docker volume create "$volume" >/dev/null
docker run -d --name "$restore" --network none --env-file "$password_file" \
  -v "$volume:/var/lib/mysql" "$image" >/dev/null
ready=false
for ((i=0; i<60; i++)); do
  if docker exec "$restore" sh -c \
    'exec healthcheck.sh --connect --innodb_initialized' >/dev/null 2>&1; then
    ready=true; break
  fi
  sleep 2
done
$ready || { echo "Restore target did not become ready" >&2; exit 1; }
gzip -dc "$backup" | docker exec -i "$restore" sh -c \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot'
restored=$(docker exec "$restore" sh -c \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot --batch --skip-column-names -e "SELECT token FROM portfolio_verification.marker WHERE id=1;"')
[[ "$restored" == "$marker" ]]
restored_hash=$(docker exec "$restore" sh -c \
  'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb-dump -uroot --single-transaction --compact --skip-comments --skip-dump-date --order-by-primary "$1"' sh "$database" | sha256sum | cut -d' ' -f1)
[[ "$source_hash" == "$restored_hash" ]]
echo 'PASS: isolated backup restore; marker and application logical dump hashes match'

old_container=$("${compose[@]}" ps -q db)
recovery_needed=true
"${compose[@]}" up -d --force-recreate --no-deps db
wait_db
new_container=$("${compose[@]}" ps -q db)
[[ "$old_container" != "$new_container" ]]
[[ "$(sql 'SELECT token FROM portfolio_verification.marker WHERE id=1;')" == "$marker" ]]
echo 'PASS: database container recreated; persistent marker retained'
"$smoke" http://127.0.0.1:8080/

"${compose[@]}" stop db
status=$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
  --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8080/)
[[ "$status" == 503 ]] || { echo "Expected HTTP 503, got $status" >&2; exit 1; }
if "$smoke" http://127.0.0.1:8080/; then
  echo 'Smoke test unexpectedly passed during database outage' >&2; exit 1
fi
echo 'PASS: database outage returns HTTP 503 and smoke test exits nonzero'
"${compose[@]}" start db
wait_db
"$smoke" http://127.0.0.1:8080/
echo 'PASS: database recovered and application healthy'
printf 'Completed: %s\n' "$(date -u +%FT%TZ)"

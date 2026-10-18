#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root/terraform"
image=ubuntu-24.04-server-cloudimg-amd64.img
if [[ -e "$image" ]]; then
  sha256sum --check cloud-image.sha256
  exit
fi
tmp=$(mktemp "$image.download.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl --fail --location --retry 3 --output "$tmp" \
  https://cloud-images.ubuntu.com/releases/noble/release-20260926/ubuntu-24.04-server-cloudimg-amd64.img
expected=$(awk '{print $1}' cloud-image.sha256)
printf '%s  %s\n' "$expected" "$tmp" | sha256sum --check
mv -- "$tmp" "$image"

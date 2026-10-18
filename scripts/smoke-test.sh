#!/usr/bin/env bash
set -euo pipefail

url="${1:-http://127.0.0.1:8080/}"
body=$(mktemp)
trap 'rm -f "$body"' EXIT

if ! status=$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
  --output "$body" --write-out '%{http_code}' "$url"); then
  echo "FAIL: could not reach $url" >&2
  exit 1
fi
if [[ "$status" != "200" ]]; then
  echo "FAIL: expected HTTP 200, received $status" >&2
  exit 1
fi

if ! python3 - "$body" <<'PYTHON'
from html.parser import HTMLParser
import re, sys
class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)
p = Text()
with open(sys.argv[1]) as f:
    p.feed(f.read())
text = ' '.join(' '.join(p.parts).split())
sys.exit(0 if re.search(r'Database connection:\s*Connected\b', text) else 1)
PYTHON
then
  echo "FAIL: page does not report Database connection: Connected" >&2
  exit 1
fi

echo "PASS: HTTP 200 and application database connection confirmed ($url)"

#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-build/platform.yaml}"

if [[ ! -s "${manifest}" ]]; then
  echo "error: rendered manifest not found: ${manifest}" >&2
  exit 1
fi

if grep -n "CHANGE_ME" "${manifest}"; then
  echo >&2
  echo "error: replace every CHANGE_ME value in platform/overlays/production/production-config.yaml" >&2
  exit 1
fi

if grep -Pn "^\\s+(password|clientSecret):\\s+(?![\"']?\\{\\{|\\\$)" "${manifest}"; then
  echo "error: possible plaintext credential in rendered output" >&2
  exit 1
fi

echo "preflight passed: ${manifest}"

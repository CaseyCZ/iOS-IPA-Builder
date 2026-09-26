#!/usr/bin/env bash
set -euo pipefail

required=(
  APPLE_CERTIFICATE_P12_BASE64
  APPLE_CERTIFICATE_PASSWORD
  APPLE_PROVISIONING_PROFILE_BASE64
  APPLE_TEAM_ID
)

missing=0
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Missing required signing secret: $name"
    missing=1
  fi
done

if (( missing )); then
  exit 90
fi

if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "::error::APPLE_TEAM_ID must be a 10-character Apple Team ID."
  exit 91
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

decode_base64_to_file() {
  local value="$1"
  local destination="$2"
  VALUE="$value" DESTINATION="$destination" python3 - <<'PY'
import base64, os, sys
try:
    data = base64.b64decode(os.environ["VALUE"], validate=True)
except Exception:
    sys.exit(1)
with open(os.environ["DESTINATION"], "wb") as f:
    f.write(data)
PY
}

if ! decode_base64_to_file "$APPLE_CERTIFICATE_P12_BASE64" "$tmp/certificate.p12"; then
  echo "::error::APPLE_CERTIFICATE_P12_BASE64 is not valid base64."
  exit 92
fi

if ! decode_base64_to_file "$APPLE_PROVISIONING_PROFILE_BASE64" "$tmp/profile.mobileprovision"; then
  echo "::error::APPLE_PROVISIONING_PROFILE_BASE64 is not valid base64."
  exit 93
fi

if [[ ! -s "$tmp/certificate.p12" ]]; then
  echo "::error::Decoded signing certificate is empty."
  exit 94
fi

if [[ ! -s "$tmp/profile.mobileprovision" ]]; then
  echo "::error::Decoded provisioning profile is empty."
  exit 95
fi

# Validate the P12 container and password without printing certificate data.
if ! openssl pkcs12 \
  -in "$tmp/certificate.p12" \
  -passin env:APPLE_CERTIFICATE_PASSWORD \
  -noout >/dev/null 2>&1; then
  echo "::error::The P12 certificate or its password is invalid."
  exit 96
fi

echo "Signing secrets are present and structurally valid."
echo "No signing material was written outside the temporary directory."

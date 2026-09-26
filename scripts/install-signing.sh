#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "::error::Apple signing material can only be installed on macOS."
  exit 100
fi

required=(
  APPLE_CERTIFICATE_P12_BASE64
  APPLE_CERTIFICATE_PASSWORD
  APPLE_PROVISIONING_PROFILE_BASE64
  APPLE_TEAM_ID
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Missing required signing secret: $name"
    exit 101
  fi
done

if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "::error::APPLE_TEAM_ID must be a 10-character Apple Team ID."
  exit 102
fi

BASE_DIR="${RUNNER_TEMP:-/tmp}/ios-ipa-builder-signing"
STATE_FILE="$BASE_DIR/state.txt"
ORIGINAL_KEYCHAINS="$BASE_DIR/original-keychains.txt"
P12_PATH="$BASE_DIR/certificate.p12"
PROFILE_RAW="$BASE_DIR/profile.mobileprovision"
PROFILE_PLIST="$BASE_DIR/profile.plist"
CERT_PEM="$BASE_DIR/certificate.pem"
KEYCHAIN_PATH="$BASE_DIR/build.keychain-db"

rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"
chmod 700 "$BASE_DIR"

if ! printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 -d > "$P12_PATH" 2>/dev/null; then
  echo "::error::APPLE_CERTIFICATE_P12_BASE64 is not valid base64."
  exit 103
fi

if ! printf '%s' "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 -d > "$PROFILE_RAW" 2>/dev/null; then
  echo "::error::APPLE_PROVISIONING_PROFILE_BASE64 is not valid base64."
  exit 104
fi

if ! security cms -D -i "$PROFILE_RAW" > "$PROFILE_PLIST" 2>/dev/null; then
  echo "::error::Provisioning profile could not be decoded."
  exit 105
fi

if ! openssl pkcs12 -in "$P12_PATH" -clcerts -nokeys \
  -passin env:APPLE_CERTIFICATE_PASSWORD -out "$CERT_PEM" >/dev/null 2>&1; then
  if ! openssl pkcs12 -legacy -in "$P12_PATH" -clcerts -nokeys \
    -passin env:APPLE_CERTIFICATE_PASSWORD -out "$CERT_PEM" >/dev/null 2>&1; then
    echo "::error::The P12 certificate or its password is invalid."
    exit 106
  fi
fi

CERT_SHA1="$(openssl x509 -in "$CERT_PEM" -outform DER | shasum | awk '{print toupper($1)}')"

PROFILE_INFO="$(PROFILE_PLIST="$PROFILE_PLIST" APPLE_TEAM_ID="$APPLE_TEAM_ID" CERT_SHA1="$CERT_SHA1" python3 - <<'PY'
import datetime
import hashlib
import os
import plistlib

with open(os.environ["PROFILE_PLIST"], "rb") as f:
    p = plistlib.load(f)

team_ids = p.get("TeamIdentifier") or []
team = os.environ["APPLE_TEAM_ID"]
if team not in team_ids:
    raise SystemExit("ERROR:TEAM")

expires = p.get("ExpirationDate")
now = datetime.datetime.now(datetime.timezone.utc)
if expires is None:
    raise SystemExit("ERROR:EXPIRATION")
if expires.tzinfo is None:
    expires = expires.replace(tzinfo=datetime.timezone.utc)
if expires <= now:
    raise SystemExit("ERROR:EXPIRED")

entitlements = p.get("Entitlements") or {}
if entitlements.get("get-task-allow") is True:
    raise SystemExit("ERROR:DEVELOPMENT_PROFILE")
if p.get("ProvisionedDevices"):
    raise SystemExit("ERROR:DEVICE_PROFILE")
if p.get("ProvisionsAllDevices") is True:
    raise SystemExit("ERROR:ENTERPRISE_PROFILE")

profile_hashes = {
    hashlib.sha1(cert).hexdigest().upper()
    for cert in (p.get("DeveloperCertificates") or [])
}
if os.environ["CERT_SHA1"] not in profile_hashes:
    raise SystemExit("ERROR:CERT_MISMATCH")

uuid = p.get("UUID")
if not uuid:
    raise SystemExit("ERROR:UUID")

name = str(p.get("Name") or "Provisioning Profile").replace("\n", " ")
print(uuid)
print(name)
print(expires.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)" || {
  case "$?" in
    *) echo "::error::Provisioning profile validation failed. Check Team ID, expiration, distribution type and certificate match." ;;
  esac
  exit 107
}

PROFILE_UUID="$(printf '%s\n' "$PROFILE_INFO" | sed -n '1p')"
PROFILE_NAME="$(printf '%s\n' "$PROFILE_INFO" | sed -n '2p')"
PROFILE_EXPIRES="$(printf '%s\n' "$PROFILE_INFO" | sed -n '3p')"

PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE_PATH="$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
mkdir -p "$PROFILE_DIR"

security list-keychains -d user | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' > "$ORIGINAL_KEYCHAINS"

KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

originals=()
while IFS= read -r keychain; do
  [[ -n "$keychain" ]] && originals+=("$keychain")
done < "$ORIGINAL_KEYCHAINS"
security list-keychains -d user -s "$KEYCHAIN_PATH" "${originals[@]}"

if ! security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null 2>&1; then
  echo "::error::Apple certificate import into the temporary keychain failed."
  exit 108
fi

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null 2>&1

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q '1)'; then
  echo "::error::No valid code-signing identity was found in the temporary keychain."
  exit 109
fi

cp "$PROFILE_RAW" "$PROFILE_PATH"
chmod 600 "$PROFILE_PATH"

{
  printf '%s\n' "$KEYCHAIN_PATH"
  printf '%s\n' "$PROFILE_PATH"
  printf '%s\n' "$ORIGINAL_KEYCHAINS"
} > "$STATE_FILE"
chmod 600 "$STATE_FILE"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "profile_uuid=$PROFILE_UUID"
    echo "profile_name=$PROFILE_NAME"
    echo "profile_expires=$PROFILE_EXPIRES"
  } >> "$GITHUB_OUTPUT"
fi

echo "Temporary Apple signing environment installed."
echo "Provisioning profile: $PROFILE_NAME"
echo "Profile expires: $PROFILE_EXPIRES"
echo "Certificate/profile match: verified"

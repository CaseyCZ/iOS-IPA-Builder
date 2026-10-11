#!/usr/bin/env bash
set -u

BASE_DIR="${RUNNER_TEMP:-/tmp}/ios-ipa-builder-signing"
STATE_FILE="$BASE_DIR/state.txt"

KEYCHAIN_PATH=""
PROFILE_PATH=""
ORIGINAL_KEYCHAINS=""

if [[ -f "$STATE_FILE" ]]; then
  KEYCHAIN_PATH="$(sed -n '1p' "$STATE_FILE")"
  PROFILE_PATH="$(sed -n '2p' "$STATE_FILE")"
  ORIGINAL_KEYCHAINS="$(sed -n '3p' "$STATE_FILE")"
fi

if [[ -n "$PROFILE_PATH" ]]; then
  rm -f "$PROFILE_PATH"
fi

if [[ -n "$KEYCHAIN_PATH" && -f "$KEYCHAIN_PATH" ]]; then
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
fi

if [[ -n "$ORIGINAL_KEYCHAINS" && -f "$ORIGINAL_KEYCHAINS" ]]; then
  originals=()
  while IFS= read -r keychain; do
    [[ -n "$keychain" ]] && originals+=("$keychain")
  done < "$ORIGINAL_KEYCHAINS"
  if (( ${#originals[@]} > 0 )); then
    security list-keychains -d user -s "${originals[@]}" >/dev/null 2>&1 || true
  fi
fi

rm -rf "$BASE_DIR"
echo "Temporary Apple signing environment removed."

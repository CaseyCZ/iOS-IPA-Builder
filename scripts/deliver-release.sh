#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:-}"
OUTPUT_REPO="${OUTPUT_REPO:-}"
OUTPUT_TOKEN="${OUTPUT_TOKEN:-}"
OUTPUT_VISIBILITY="${OUTPUT_VISIBILITY:-private}"

if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
  echo "::error::IPA file does not exist."
  exit 80
fi

validate_ipa() {
  local ipa="$1"

  if [[ ! -s "$ipa" ]]; then
    echo "::error::IPA is empty."
    exit 85
  fi

  IPA_TO_VALIDATE="$ipa" python3 - <<'PY'
import os, sys, zipfile

path = os.environ["IPA_TO_VALIDATE"]

if not zipfile.is_zipfile(path):
    print("::error::IPA is not a valid ZIP archive.")
    raise SystemExit(85)

try:
    with zipfile.ZipFile(path, "r") as zf:
        bad = zf.testzip()
        if bad is not None:
            print(f"::error::IPA ZIP CRC test failed at: {bad}")
            raise SystemExit(86)

        names = zf.namelist()
        app_plists = [
            name for name in names
            if name.startswith("Payload/")
            and name.count("/") == 2
            and name.endswith(".app/Info.plist")
        ]

        if len(app_plists) != 1:
            print(
                "::error::IPA must contain exactly one "
                "Payload/*.app/Info.plist entry."
            )
            raise SystemExit(87)

        if any(
            name and not name.startswith("Payload/")
            for name in names
        ):
            print("::error::IPA contains entries outside Payload/.")
            raise SystemExit(88)

        print(f"IPA archive validated: {app_plists[0]}")
except zipfile.BadZipFile:
    print("::error::IPA ZIP structure is invalid.")
    raise SystemExit(85)
PY
}

# Never publish a package that an installer cannot parse as an IPA/ZIP.
validate_ipa "$IPA_PATH"

if [[ -z "$OUTPUT_REPO" || -z "$OUTPUT_TOKEN" ]]; then
  echo "::error::IPA delivery requires OUTPUT_REPO and OUTPUT_TOKEN repository secrets."
  exit 81
fi

if [[ ! "$OUTPUT_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "::error::OUTPUT_REPO must use owner/repo format."
  exit 82
fi

API="https://api.github.com"
ACCEPT="Accept: application/vnd.github+json"
AUTH="Authorization: Bearer $OUTPUT_TOKEN"
VERSION="X-GitHub-Api-Version: 2026-03-10"

repo_json="$(curl --fail-with-body --silent --show-error \
  -H "$ACCEPT" \
  -H "$AUTH" \
  -H "$VERSION" \
  "$API/repos/$OUTPUT_REPO")"

REPO_PRIVATE="$(JSON_INPUT="$repo_json" python3 - <<'PY'
import json, os
data=json.loads(os.environ["JSON_INPUT"])
print("true" if data.get("private") is True else "false")
PY
)"

case "$OUTPUT_VISIBILITY" in
  private)
    if [[ "$REPO_PRIVATE" != "true" ]]; then
      echo "::error::Output visibility is set to private, but the configured repository is public."
      exit 83
    fi
    ;;
  public)
    if [[ "$REPO_PRIVATE" == "true" ]]; then
      echo "::error::Output visibility is set to public, but the configured repository is private."
      exit 83
    fi
    ;;
  *)
    echo "::error::OUTPUT_VISIBILITY must be private or public."
    exit 83
    ;;
esac

FILE_SIZE="$(stat -f%z "$IPA_PATH")"
MAX_SIZE=$((2 * 1024 * 1024 * 1024))
if (( FILE_SIZE >= MAX_SIZE )); then
  echo "::error::GitHub Release assets must be under 2 GiB."
  exit 84
fi

IPA_NAME="$(basename "$IPA_PATH")"
TAG="ios-build-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
RELEASE_NAME="iOS IPA Build ${GITHUB_RUN_ID:-local}.${GITHUB_RUN_ATTEMPT:-1}"
SHA256="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"

release_body="$(python3 - <<PY
import json
print(json.dumps({
  "tag_name": "$TAG",
  "name": "$RELEASE_NAME",
  "body": "iOS build output ($OUTPUT_VISIBILITY).\n\nFile: $IPA_NAME\nSHA-256: $SHA256",
  "draft": False,
  "prerelease": True
}))
PY
)"

release_json="$(curl --fail-with-body --silent --show-error \
  -X POST \
  -H "$ACCEPT" \
  -H "$AUTH" \
  -H "$VERSION" \
  -H "Content-Type: application/json" \
  "$API/repos/$OUTPUT_REPO/releases" \
  -d "$release_body")"

RELEASE_ID="$(JSON_INPUT="$release_json" python3 - <<'PY'
import json, os
data=json.loads(os.environ["JSON_INPUT"])
value=data.get("id")
if not value:
    raise SystemExit("GitHub did not return a release id.")
print(value)
PY
)"

ENCODED_NAME="$(IPA_NAME="$IPA_NAME" python3 - <<'PY'
import os, urllib.parse
print(urllib.parse.quote(os.environ["IPA_NAME"], safe=""))
PY
)"

curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "$AUTH" \
  -H "$VERSION" \
  -H "Content-Type: application/octet-stream" \
  "https://uploads.github.com/repos/$OUTPUT_REPO/releases/$RELEASE_ID/assets?name=$ENCODED_NAME" \
  --data-binary "@$IPA_PATH" >/dev/null

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "delivered=true"
    echo "release_tag=$TAG"
    echo "ipa_name=$IPA_NAME"
  } >> "$GITHUB_OUTPUT"
fi

echo "IPA delivered to the configured $OUTPUT_VISIBILITY output repository."
echo "File: $IPA_NAME"
echo "SHA-256: $SHA256"

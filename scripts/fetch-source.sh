#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-source}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

eval "$(bash "$SCRIPT_DIR/request-context.sh")"

rm -rf "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin "https://github.com/$SOURCE_REPO.git"

ASKPASS=""
if [[ -n "${SOURCE_TOKEN:-}" ]]; then
  ASKPASS="${RUNNER_TEMP:-/tmp}/ios-builder-git-askpass.sh"
  cat > "$ASKPASS" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) printf '%s\n' "$SOURCE_TOKEN" ;;
  *) printf '\n' ;;
esac
EOF
  chmod 700 "$ASKPASS"
  export GIT_ASKPASS="$ASKPASS"
  export GIT_TERMINAL_PROMPT=0
fi

FETCH_LOG="${RUNNER_TEMP:-/tmp}/ios-builder-fetch.log"
rm -f "$FETCH_LOG"

friendly_fetch_error() {
  if [[ -z "${SOURCE_TOKEN:-}" ]]; then
    echo "::error::The source could not be opened. If this is a private project, add SOURCE_TOKEN in Settings → Secrets and variables → Actions."
  else
    echo "::error::The source could not be opened. Check the repository, branch/tag and SOURCE_TOKEN access."
  fi
}

if [[ -n "$SOURCE_REF" ]]; then
  if ! git -C "$DEST" fetch --quiet --depth=1 origin "$SOURCE_REF" > /dev/null 2>"$FETCH_LOG"; then
    friendly_fetch_error
    exit 150
  fi
else
  if ! git -C "$DEST" fetch --quiet --depth=1 origin HEAD > /dev/null 2>"$FETCH_LOG"; then
    friendly_fetch_error
    exit 151
  fi
fi

git -C "$DEST" checkout --quiet --detach FETCH_HEAD
git -C "$DEST" remote remove origin
rm -f "$ASKPASS" "$FETCH_LOG"
unset SOURCE_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT

echo "Source fetched successfully."

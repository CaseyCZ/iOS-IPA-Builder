#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-source}"
REQUESTED_TYPE="${2:-auto}"
REQUESTED_PATH="${3:-}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "::error::Source directory does not exist."
  exit 20
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
SEARCH_ROOT="$SOURCE_DIR"

if [[ -n "$REQUESTED_PATH" ]]; then
  if [[ ! -d "$SOURCE_DIR/$REQUESTED_PATH" ]]; then
    echo "::error::Requested project path does not exist."
    exit 22
  fi
  SEARCH_ROOT="$SOURCE_DIR/$REQUESTED_PATH"
fi

first_file() {
  find . -maxdepth 4 -type f \( "$@" \) \
    -not -path './.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/Pods/*' \
    -print 2>/dev/null | sort | head -n 1
}

first_dir() {
  find . -maxdepth 4 -type d \( "$@" \) \
    -not -path './.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/Pods/*' \
    -print 2>/dev/null | sort | head -n 1
}

scan_project() {
  local root="$1"
  cd "$root"

  CAPACITOR_FILE="$(first_file -name 'capacitor.config.json' -o -name 'capacitor.config.ts' -o -name 'capacitor.config.js' || true)"
  FLUTTER_FILE="$(first_file -name 'pubspec.yaml' || true)"
  PACKAGE_FILE="$(first_file -name 'package.json' || true)"
  XCODE_WORKSPACE="$(first_dir -name '*.xcworkspace' || true)"
  XCODE_PROJECT="$(first_dir -name '*.xcodeproj' || true)"

  HAS_CAPACITOR=false
  HAS_FLUTTER=false
  HAS_REACT_NATIVE=false
  HAS_XCODE=false

  [[ -n "$CAPACITOR_FILE" ]] && HAS_CAPACITOR=true

  if [[ -n "$FLUTTER_FILE" ]] && grep -Eq '^[[:space:]]*flutter:[[:space:]]*$' "$FLUTTER_FILE"; then
    HAS_FLUTTER=true
  fi

  if [[ -n "$PACKAGE_FILE" ]] && grep -Eq '"react-native"[[:space:]]*:' "$PACKAGE_FILE"; then
    HAS_REACT_NATIVE=true
  fi

  if [[ -n "$XCODE_WORKSPACE" || -n "$XCODE_PROJECT" ]]; then
    HAS_XCODE=true
  fi
}

detect_type() {
  if [[ "$HAS_CAPACITOR" == true ]]; then
    echo "capacitor"
  elif [[ "$HAS_FLUTTER" == true ]]; then
    echo "flutter"
  elif [[ "$HAS_REACT_NATIVE" == true ]]; then
    echo "react-native"
  elif [[ "$HAS_XCODE" == true ]]; then
    echo "xcode"
  else
    echo "unknown"
  fi
}

root_has_direct_project_marker() {
  if [[ -f "$SOURCE_DIR/capacitor.config.json" || -f "$SOURCE_DIR/capacitor.config.ts" || -f "$SOURCE_DIR/capacitor.config.js" ]]; then
    return 0
  fi

  if [[ -f "$SOURCE_DIR/pubspec.yaml" ]] && grep -Eq '^[[:space:]]*flutter:[[:space:]]*$' "$SOURCE_DIR/pubspec.yaml"; then
    return 0
  fi

  if [[ -f "$SOURCE_DIR/package.json" ]] && grep -Eq '"react-native"[[:space:]]*:' "$SOURCE_DIR/package.json"; then
    return 0
  fi

  if find "$SOURCE_DIR" -maxdepth 1 -type d \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi

  return 1
}

scan_project "$SEARCH_ROOT"
DETECTED_TYPE="$(detect_type)"

# If the selected folder is only an output/archive folder but the repository
# root clearly contains an iOS project, use the root automatically.
if [[ "$DETECTED_TYPE" == "unknown" && -n "$REQUESTED_PATH" ]] && root_has_direct_project_marker; then
  REQUESTED_PATH=""
  SEARCH_ROOT="$SOURCE_DIR"
  scan_project "$SEARCH_ROOT"
  DETECTED_TYPE="$(detect_type)"

  if [[ "${DETECT_QUIET:-0}" != "1" ]]; then
    echo "Selected project path is not a supported project; using repository root instead."
  fi
fi

FINAL_TYPE="$DETECTED_TYPE"
if [[ "$REQUESTED_TYPE" != "auto" ]]; then
  FINAL_TYPE="$REQUESTED_TYPE"
fi

if [[ "$FINAL_TYPE" == "unknown" ]]; then
  echo "::error::Unable to detect a supported iOS project type."
  if [[ -n "$REQUESTED_PATH" ]]; then
    echo "The selected project folder does not contain a supported iOS project. Leave Project path blank if the app is in the repository root."
  else
    echo "Looked for Capacitor config, Flutter pubspec.yaml, React Native package.json and Xcode project/workspace."
  fi
  exit 21
fi

marker_for_type() {
  case "$1" in
    capacitor) echo "$CAPACITOR_FILE" ;;
    flutter) echo "$FLUTTER_FILE" ;;
    react-native) echo "$PACKAGE_FILE" ;;
    xcode) echo "${XCODE_WORKSPACE:-$XCODE_PROJECT}" ;;
  esac
}

MARKER="$(marker_for_type "$FINAL_TYPE")"

if [[ "$REQUESTED_TYPE" != "auto" && -z "$MARKER" ]]; then
  echo "::warning::Requested project type '$REQUESTED_TYPE' does not have its usual marker. The build may fail later."
fi

PROJECT_ROOT="."
if [[ -n "$MARKER" ]]; then
  MARKER_DIR="$(dirname "$MARKER")"

  case "$FINAL_TYPE" in
    xcode)
      if [[ "$(basename "$MARKER_DIR")" == "ios" ]]; then
        PROJECT_ROOT="$(dirname "$MARKER_DIR")"
      else
        PROJECT_ROOT="$MARKER_DIR"
      fi
      ;;
    *)
      PROJECT_ROOT="$MARKER_DIR"
      ;;
  esac
fi

PROJECT_ROOT="${PROJECT_ROOT#./}"
[[ -z "$PROJECT_ROOT" ]] && PROJECT_ROOT="."

if [[ -n "$REQUESTED_PATH" ]]; then
  if [[ "$PROJECT_ROOT" == "." ]]; then
    PROJECT_ROOT="$REQUESTED_PATH"
  else
    PROJECT_ROOT="$REQUESTED_PATH/$PROJECT_ROOT"
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "project_type=$FINAL_TYPE"
    echo "detected_type=$DETECTED_TYPE"
    echo "project_root=$PROJECT_ROOT"
    echo "marker=${MARKER#./}"
    echo "xcode_workspace=${XCODE_WORKSPACE#./}"
    echo "xcode_project=${XCODE_PROJECT#./}"
  } >> "$GITHUB_OUTPUT"
fi

if [[ -n "${DETECT_ENV_FILE:-}" ]]; then
  {
    printf 'DETECTED_PROJECT_TYPE=%q\n' "$FINAL_TYPE"
    printf 'DETECTED_TYPE=%q\n' "$DETECTED_TYPE"
    printf 'DETECTED_PROJECT_ROOT=%q\n' "$PROJECT_ROOT"
  } > "$DETECT_ENV_FILE"
  chmod 600 "$DETECT_ENV_FILE"
fi

if [[ "${DETECT_QUIET:-0}" != "1" ]]; then
  echo "Requested type : $REQUESTED_TYPE"
  echo "Detected type  : $DETECTED_TYPE"
  echo "Build type     : $FINAL_TYPE"
  echo "Project root   : $PROJECT_ROOT"
  echo "Marker         : ${MARKER#./}"
fi

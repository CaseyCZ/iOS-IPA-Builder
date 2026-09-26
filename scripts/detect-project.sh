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

cd "$SEARCH_ROOT"

first_file() {
  find . -maxdepth 4 -type f \( "$@" \) -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/Pods/*' -print 2>/dev/null | sort | head -n 1
}

first_dir() {
  find . -maxdepth 4 -type d \( "$@" \) -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/Pods/*' -print 2>/dev/null | sort | head -n 1
}

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

DETECTED_TYPE="$(detect_type)"
FINAL_TYPE="$DETECTED_TYPE"

if [[ "$REQUESTED_TYPE" != "auto" ]]; then
  FINAL_TYPE="$REQUESTED_TYPE"
fi

if [[ "$FINAL_TYPE" == "unknown" ]]; then
  echo "::error::Unable to detect a supported iOS project type."
  echo "Looked for Capacitor config, Flutter pubspec.yaml, React Native package.json and Xcode project/workspace."
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

if [[ "${DETECT_QUIET:-0}" != "1" ]]; then
  echo "Requested type : $REQUESTED_TYPE"
  echo "Detected type  : $DETECTED_TYPE"
  echo "Build type     : $FINAL_TYPE"
  echo "Project root   : $PROJECT_ROOT"
  echo "Marker         : ${MARKER#./}"
fi

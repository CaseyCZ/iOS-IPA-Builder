#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-source}"
PROJECT_TYPE="${2:-}"
PROJECT_ROOT="${3:-.}"
REQUESTED_SCHEME="${4:-}"
REQUESTED_OUTPUT="${5:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
PROFILE_NAME="${PROFILE_NAME:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "::error::App Store builds require macOS."
  exit 110
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "::error::Source directory does not exist: $SOURCE_DIR"
  exit 111
fi

if [[ ! "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "::error::APPLE_TEAM_ID is missing or invalid."
  exit 112
fi

if [[ -z "$PROFILE_NAME" ]]; then
  echo "::error::Provisioning profile name is missing."
  exit 113
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
ROOT="$SOURCE_DIR"
if [[ "$PROJECT_ROOT" != "." && -n "$PROJECT_ROOT" ]]; then
  ROOT="$SOURCE_DIR/$PROJECT_ROOT"
fi

if [[ ! -d "$ROOT" ]]; then
  echo "::error::Detected project root does not exist: $ROOT"
  exit 114
fi

case "$PROJECT_TYPE" in
  xcode|capacitor|flutter|react-native) ;;
  *)
    echo "::error::Unsupported App Store project type: $PROJECT_TYPE"
    exit 115
    ;;
esac

install_js_dependencies() {
  local dir="$1"
  (
    cd "$dir"
    if [[ -f pnpm-lock.yaml ]]; then
      corepack enable
      pnpm install --frozen-lockfile
    elif [[ -f yarn.lock ]]; then
      corepack enable
      yarn install --immutable 2>/dev/null || yarn install --frozen-lockfile
    elif [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      npm ci --no-audit --no-fund
    elif [[ -f package.json ]]; then
      npm install --no-audit --no-fund
    else
      echo "::error::JavaScript project has no package.json."
      exit 116
    fi
  )
}

run_web_build_if_present() {
  local dir="$1"
  (
    cd "$dir"
    if node -e "const p=require('./package.json');process.exit(p.scripts&&p.scripts.build?0:1)"; then
      npm run build
    else
      echo "No package.json build script; continuing without a web build."
    fi
  )
}

prepare_capacitor() {
  local dir="$1"
  install_js_dependencies "$dir"
  run_web_build_if_present "$dir"

  (
    cd "$dir"
    if [[ ! -d ios/App ]]; then
      npx cap add ios
    fi
    npx cap sync ios

    local web_dir
    web_dir="$(node - <<'NODE'
const fs=require('fs');
for (const file of ['capacitor.config.json','capacitor.config.js','capacitor.config.ts']) {
  if (!fs.existsSync(file)) continue;
  if (file.endsWith('.json')) {
    const c=JSON.parse(fs.readFileSync(file,'utf8'));
    process.stdout.write(String(c.webDir||'dist'));
    process.exit(0);
  }
}
process.stdout.write('dist');
NODE
)"
    if [[ -d assets && -d "$web_dir" ]]; then
      mkdir -p "$web_dir/assets"
      rsync -a --ignore-existing assets/ "$web_dir/assets/"
      npx cap sync ios
    fi
  )
}

install_pods_if_needed() {
  local ios_dir="$1"
  local project_root="${2:-$1}"

  [[ -d "$ios_dir" ]] || return 0
  ios_dir="$(cd "$ios_dir" && pwd)"
  project_root="$(cd "$project_root" && pwd)"

  if [[ -f "$ios_dir/Podfile" ]]; then
    if [[ -f "$project_root/Gemfile" ]] && command -v bundle >/dev/null 2>&1 && (cd "$project_root" && bundle check >/dev/null 2>&1); then
      (cd "$ios_dir" && bundle exec pod install)
    else
      (cd "$ios_dir" && pod install)
    fi
  fi
}

prepare_react_native() {
  local dir="$1"
  [[ -f "$dir/package.json" ]] || { echo "::error::React Native project has no package.json."; exit 117; }
  [[ -d "$dir/ios" ]] || { echo "::error::React Native project has no ios directory."; exit 118; }
  install_js_dependencies "$dir"
  install_pods_if_needed "$dir/ios" "$dir"
}

prepare_flutter() {
  local dir="$1"
  command -v flutter >/dev/null 2>&1 || { echo "::error::Flutter SDK is not installed."; exit 119; }
  (
    cd "$dir"
    flutter pub get
    # Prepare generated iOS configuration and plugin integration before the signed archive.
    flutter build ios --release --no-codesign
  )
}

find_xcode_container() {
  local search_root="$1"
  local workspace project

  workspace="$(find "$search_root" -maxdepth 4 -type d -name '*.xcworkspace' \
    -not -path '*/Pods/*' -not -path '*/DerivedData/*' | sort | head -n 1 || true)"
  project="$(find "$search_root" -maxdepth 4 -type d -name '*.xcodeproj' \
    -not -path '*/Pods/*' -not -path '*/DerivedData/*' | sort | head -n 1 || true)"

  if [[ -n "$workspace" ]]; then
    printf 'workspace|%s\n' "$workspace"
  elif [[ -n "$project" ]]; then
    printf 'project|%s\n' "$project"
  else
    echo "::error::No Xcode workspace or project found."
    exit 120
  fi
}

detect_scheme() {
  local kind="$1"
  local container="$2"
  local json

  if [[ -n "$REQUESTED_SCHEME" ]]; then
    printf '%s\n' "$REQUESTED_SCHEME"
    return
  fi

  if [[ "$kind" == "workspace" ]]; then
    json="$(xcodebuild -workspace "$container" -list -json)"
  else
    json="$(xcodebuild -project "$container" -list -json)"
  fi

  JSON_INPUT="$json" python3 - <<'PY'
import json, os
data=json.loads(os.environ["JSON_INPUT"])
root=data.get("workspace") or data.get("project") or {}
schemes=root.get("schemes") or []
if not schemes:
    raise SystemExit("No shared Xcode scheme found. Supply the scheme input explicitly.")
print(schemes[0])
PY
}

detect_apple_platform() {
  local kind="$1"
  local container="$2"
  local scheme="$3"
  local args=()
  local settings sdkroot supported

  if [[ "$kind" == "workspace" ]]; then
    args+=( -workspace "$container" )
  else
    args+=( -project "$container" )
  fi

  settings="$(xcodebuild "${args[@]}" -scheme "$scheme" -configuration Release -showBuildSettings 2>/dev/null)"
  sdkroot="$(printf '%s\n' "$settings" | awk -F' = ' '/^[[:space:]]*SDKROOT = / {print $2; exit}')"
  supported="$(printf '%s\n' "$settings" | awk -F' = ' '/^[[:space:]]*SUPPORTED_PLATFORMS = / {print $2; exit}')"

  if [[ "$sdkroot" == appletvos* ]]; then
    echo "tvos"
  elif [[ "$sdkroot" == iphoneos* ]]; then
    echo "ios"
  elif [[ "$supported" == *appletvos* && "$supported" != *iphoneos* ]]; then
    echo "tvos"
  elif [[ "$supported" == *iphoneos* ]]; then
    echo "ios"
  else
    echo "::error::Unable to detect whether the Xcode scheme targets iOS or tvOS." >&2
    echo "::error::SDKROOT='$sdkroot' SUPPORTED_PLATFORMS='$supported'" >&2
    exit 125
  fi
}

archive_app() {
  local search_root="$1"
  local archive_path="$RUNNER_TEMP/ios-ipa-builder/AppStore.xcarchive"
  local derived="$RUNNER_TEMP/ios-ipa-builder-derived"
  rm -rf "$archive_path" "$derived"
  mkdir -p "$(dirname "$archive_path")"

  local found kind container scheme
  found="$(find_xcode_container "$search_root")"
  kind="${found%%|*}"
  container="${found#*|}"
  scheme="$(detect_scheme "$kind" "$container")"

  local platform sdk destination
  platform="$(detect_apple_platform "$kind" "$container" "$scheme")"

  case "$platform" in
    tvos)
      sdk="appletvos"
      destination="generic/platform=tvOS"
      ;;
    ios)
      sdk="iphoneos"
      destination="generic/platform=iOS"
      ;;
    *)
      echo "::error::Unsupported Apple platform: $platform"
      exit 126
      ;;
  esac

  local args=()
  if [[ "$kind" == "workspace" ]]; then
    args+=( -workspace "$container" )
  else
    args+=( -project "$container" )
  fi

  echo "Xcode container : $container"
  echo "Scheme          : $scheme"
  echo "Platform        : $platform"
  echo "Configuration   : Release"
  echo "Signing         : manual App Store distribution"

  xcodebuild \
    "${args[@]}" \
    -scheme "$scheme" \
    -configuration Release \
    -sdk "$sdk" \
    -destination "$destination" \
    -derivedDataPath "$derived" \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
    archive

  local app_path
  app_path="$(find "$archive_path/Products/Applications" -maxdepth 1 -type d -name '*.app' -print | sort | head -n 1 || true)"
  if [[ -z "$app_path" ]]; then
    echo "::error::Archive completed but no application was found in the xcarchive."
    exit 121
  fi

  codesign --verify --deep --strict "$app_path"

  ARCHIVE_PATH="$archive_path"
  ARCHIVED_APP_PATH="$app_path"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"

  if [[ -z "$BUNDLE_ID" ]]; then
    echo "::error::Could not determine archived app bundle identifier."
    exit 122
  fi
}

create_export_options() {
  local options="$RUNNER_TEMP/ios-ipa-builder/ExportOptions.plist"
  local method="app-store-connect"

  if ! xcodebuild -help 2>&1 | grep -q 'app-store-connect'; then
    method="app-store"
  fi

  EXPORT_OPTIONS="$options"
  EXPORT_METHOD="$method"

  APPLE_TEAM_ID="$APPLE_TEAM_ID" PROFILE_NAME="$PROFILE_NAME" BUNDLE_ID="$BUNDLE_ID" EXPORT_METHOD="$method" EXPORT_OPTIONS="$options" python3 - <<'PY'
import os, plistlib
data = {
    "method": os.environ["EXPORT_METHOD"],
    "destination": "export",
    "signingStyle": "manual",
    "signingCertificate": "Apple Distribution",
    "teamID": os.environ["APPLE_TEAM_ID"],
    "manageAppVersionAndBuildNumber": False,
    "provisioningProfiles": {
        os.environ["BUNDLE_ID"]: os.environ["PROFILE_NAME"]
    },
}
with open(os.environ["EXPORT_OPTIONS"], "wb") as f:
    plistlib.dump(data, f)
PY
}

export_ipa() {
  local export_dir="$RUNNER_TEMP/ios-ipa-builder/export"
  rm -rf "$export_dir"
  mkdir -p "$export_dir"

  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

  local ipa_path
  ipa_path="$(find "$export_dir" -maxdepth 1 -type f -name '*.ipa' -print | sort | head -n 1 || true)"
  if [[ -z "$ipa_path" || ! -s "$ipa_path" ]]; then
    echo "::error::Signed IPA export failed."
    exit 123
  fi

  local ipa_base final_path
  ipa_base="${REQUESTED_OUTPUT:-$(basename "$ipa_path" .ipa)}"
  ipa_base="${ipa_base%.ipa}"
  if [[ ! "$ipa_base" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "::error::Generated output name is unsafe: $ipa_base"
    exit 124
  fi

  final_path="$export_dir/$ipa_base-app-store.ipa"
  if [[ "$ipa_path" != "$final_path" ]]; then
    mv "$ipa_path" "$final_path"
  fi

  local sha size
  sha="$(shasum -a 256 "$final_path" | awk '{print $1}')"
  size="$(du -h "$final_path" | awk '{print $1}')"

  if [[ -n "${BUILD_ENV_FILE:-}" ]]; then
    {
      printf 'IPA_PATH=%q\n' "$final_path"
      printf 'IPA_NAME=%q\n' "$(basename "$final_path")"
      printf 'IPA_SHA256=%q\n' "$sha"
      printf 'IPA_SIZE=%q\n' "$size"
      printf 'BUNDLE_ID=%q\n' "$BUNDLE_ID"
      printf 'EXPORT_METHOD=%q\n' "$EXPORT_METHOD"
    } > "$BUILD_ENV_FILE"
    chmod 600 "$BUILD_ENV_FILE"
  fi

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "ipa_path=$final_path"
      echo "ipa_name=$(basename "$final_path")"
      echo "ipa_sha256=$sha"
      echo "ipa_size=$size"
      echo "bundle_id=$BUNDLE_ID"
      echo "export_method=$EXPORT_METHOD"
    } >> "$GITHUB_OUTPUT"
  fi

  echo "Signed IPA     : $final_path"
  echo "Bundle ID      : $BUNDLE_ID"
  echo "Export method  : $EXPORT_METHOD"
  echo "Size           : $size"
  echo "SHA-256        : $sha"
}

case "$PROJECT_TYPE" in
  capacitor)
    prepare_capacitor "$ROOT"
    install_pods_if_needed "$ROOT/ios/App" "$ROOT"
    SEARCH_ROOT="$ROOT/ios"
    ;;
  react-native)
    prepare_react_native "$ROOT"
    SEARCH_ROOT="$ROOT/ios"
    ;;
  flutter)
    prepare_flutter "$ROOT"
    SEARCH_ROOT="$ROOT/ios"
    ;;
  xcode)
    install_pods_if_needed "$ROOT" "$ROOT"
    SEARCH_ROOT="$ROOT"
    ;;
esac

archive_app "$SEARCH_ROOT"
create_export_options
export_ipa

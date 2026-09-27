#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-source}"
PROJECT_TYPE="${2:-}"
PROJECT_ROOT="${3:-.}"
REQUESTED_SCHEME="${4:-}"
REQUESTED_OUTPUT="${5:-}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "::error::Source directory does not exist: $SOURCE_DIR"
  exit 50
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
ROOT="$SOURCE_DIR"
if [[ "$PROJECT_ROOT" != "." && -n "$PROJECT_ROOT" ]]; then
  ROOT="$SOURCE_DIR/$PROJECT_ROOT"
fi

if [[ ! -d "$ROOT" ]]; then
  echo "::error::Detected project root does not exist: $ROOT"
  exit 51
fi

case "$PROJECT_TYPE" in
  xcode|capacitor|flutter|react-native) ;;
  *)
    echo "::error::Unsupported unsigned project type: $PROJECT_TYPE"
    exit 52
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
      exit 53
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

  cd "$dir"

  if [[ ! -d ios/App ]]; then
    echo "No Capacitor iOS project found; creating it."
    npx cap add ios
  fi

  npx cap sync ios

  # Some web projects intentionally keep classic/static assets outside their
  # bundler graph. Copy only missing root assets into the generated webDir.
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
}

install_pods_if_needed() {
  local ios_dir="$1"
  local project_root="${2:-$1}"

  [[ -d "$ios_dir" ]] || return 0
  ios_dir="$(cd "$ios_dir" && pwd)"
  project_root="$(cd "$project_root" && pwd)"

  if [[ -f "$ios_dir/Podfile" ]]; then
    echo "Podfile detected; installing CocoaPods dependencies."
    if [[ -f "$project_root/Gemfile" ]] && command -v bundle >/dev/null 2>&1 && (cd "$project_root" && bundle check >/dev/null 2>&1); then
      (cd "$ios_dir" && bundle exec pod install)
    else
      (cd "$ios_dir" && pod install)
    fi
  fi
}

prepare_react_native() {
  local dir="$1"
  if [[ ! -f "$dir/package.json" ]]; then
    echo "::error::React Native project has no package.json at the detected project root."
    exit 59
  fi
  if [[ ! -d "$dir/ios" ]]; then
    echo "::error::React Native project has no ios directory. Expo managed projects without native iOS files are not supported yet."
    exit 60
  fi

  install_js_dependencies "$dir"
  install_pods_if_needed "$dir/ios" "$dir"
}

build_flutter_app() {
  local dir="$1"

  if ! command -v flutter >/dev/null 2>&1; then
    echo "::error::Flutter SDK is not installed on the runner."
    exit 61
  fi

  cd "$dir"
  flutter --version
  flutter pub get
  flutter build ios --release --no-codesign

  local app_path
  app_path="$(find "$dir/build/ios/iphoneos" -maxdepth 2 -type d -name '*.app' -print | sort | head -n 1 || true)"
  if [[ -z "$app_path" ]]; then
    echo "::error::Flutter build completed but no iphoneos .app was found."
    exit 62
  fi

  BUILT_APP_PATH="$app_path"
  echo "Built app        : $BUILT_APP_PATH"
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
    exit 54
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
import json, os, sys
data=json.loads(os.environ["JSON_INPUT"])
root=data.get("workspace") or data.get("project") or {}
schemes=root.get("schemes") or []
if not schemes:
    raise SystemExit("No shared Xcode scheme was found. Supply the scheme input explicitly.")
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
    exit 63
  fi
}

BUILT_APP_PATH=""

build_xcode_app() {
  local search_root="$1"
  local derived="$RUNNER_TEMP/ios-ipa-builder-derived"
  rm -rf "$derived"

  local found kind container scheme
  found="$(find_xcode_container "$search_root")"
  kind="${found%%|*}"
  container="${found#*|}"
  scheme="$(detect_scheme "$kind" "$container")"

  local platform sdk destination product_dir
  platform="$(detect_apple_platform "$kind" "$container" "$scheme")"

  case "$platform" in
    tvos)
      sdk="appletvos"
      destination="generic/platform=tvOS"
      product_dir="appletvos"
      ;;
    ios)
      sdk="iphoneos"
      destination="generic/platform=iOS"
      product_dir="iphoneos"
      ;;
    *)
      echo "::error::Unsupported Apple platform: $platform"
      exit 64
      ;;
  esac

  echo "Xcode container : $container"
  echo "Scheme          : $scheme"
  echo "Platform        : $platform"
  echo "Configuration   : Release"
  echo "Signing         : disabled"

  local args=()
  if [[ "$kind" == "workspace" ]]; then
    args+=( -workspace "$container" )
  else
    args+=( -project "$container" )
  fi

  xcodebuild \
    "${args[@]}" \
    -scheme "$scheme" \
    -configuration Release \
    -sdk "$sdk" \
    -destination "$destination" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    DEVELOPMENT_TEAM="" \
    build

  local app_path
  app_path="$(find "$derived/Build/Products" -maxdepth 3 -type d -name '*.app' \
    -path "*Release-$product_dir*" -print | sort | head -n 1 || true)"

  if [[ -z "$app_path" ]]; then
    echo "::error::Xcode build completed but no Release iphoneos .app was found."
    exit 55
  fi

  BUILT_APP_PATH="$app_path"
  echo "Built app        : $BUILT_APP_PATH"
}

package_ipa() {
  local app_path="$1"
  local output_dir="$RUNNER_TEMP/ios-ipa-builder-output"
  rm -rf "$output_dir"
  mkdir -p "$output_dir/Payload"

  cp -R "$app_path" "$output_dir/Payload/"

  local app_name ipa_base ipa_path
  app_name="$(basename "$app_path" .app)"
  ipa_base="${REQUESTED_OUTPUT:-$app_name}"
  ipa_base="${ipa_base%.ipa}"

  if [[ ! "$ipa_base" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "::error::Generated output name is unsafe: $ipa_base"
    exit 56
  fi

  ipa_path="$output_dir/$ipa_base-unsigned.ipa"
  (
    cd "$output_dir"
    zip -qry "$ipa_path" Payload
  )

  if [[ ! -s "$ipa_path" ]]; then
    echo "::error::IPA packaging failed."
    exit 57
  fi

  local sha size
  sha="$(shasum -a 256 "$ipa_path" | awk '{print $1}')"
  size="$(du -h "$ipa_path" | awk '{print $1}')"

  if [[ -n "${BUILD_ENV_FILE:-}" ]]; then
    {
      printf 'IPA_PATH=%q\n' "$ipa_path"
      printf 'IPA_NAME=%q\n' "$(basename "$ipa_path")"
      printf 'IPA_SHA256=%q\n' "$sha"
      printf 'IPA_SIZE=%q\n' "$size"
    } > "$BUILD_ENV_FILE"
    chmod 600 "$BUILD_ENV_FILE"
  fi

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "ipa_path=$ipa_path"
      echo "ipa_name=$(basename "$ipa_path")"
      echo "ipa_sha256=$sha"
      echo "ipa_size=$size"
    } >> "$GITHUB_OUTPUT"
  fi

  echo "IPA       : $ipa_path"
  echo "Size      : $size"
  echo "SHA-256   : $sha"
}

case "$PROJECT_TYPE" in
  capacitor)
    prepare_capacitor "$ROOT"
    install_pods_if_needed "$ROOT/ios/App" "$ROOT"
    build_xcode_app "$ROOT/ios"
    ;;
  react-native)
    prepare_react_native "$ROOT"
    build_xcode_app "$ROOT/ios"
    ;;
  flutter)
    build_flutter_app "$ROOT"
    ;;
  xcode)
    install_pods_if_needed "$ROOT" "$ROOT"
    build_xcode_app "$ROOT"
    ;;
esac

if [[ -z "$BUILT_APP_PATH" ]]; then
  echo "::error::Internal builder error: built app path is empty."
  exit 58
fi

package_ipa "$BUILT_APP_PATH"

#!/usr/bin/env bash
set -euo pipefail

EVENT_PATH="${GITHUB_EVENT_PATH:-}"
if [[ -z "$EVENT_PATH" || ! -f "$EVENT_PATH" ]]; then
  echo "GitHub event payload is unavailable." >&2
  exit 140
fi

python3 - "$EVENT_PATH" <<'PY'
import json
import re
import shlex
import sys
from urllib.parse import urlparse

event_path = sys.argv[1]
with open(event_path, "r", encoding="utf-8") as f:
    event = json.load(f)

inputs = event.get("inputs") or {}

def get(name, default=""):
    value = inputs.get(name, default)
    return "" if value is None else str(value).strip()

def normalize_repo(raw, field):
    raw = raw.strip()
    if not raw:
        raise SystemExit(f"{field} is required.")

    if raw.startswith("git@github.com:"):
        raw = raw[len("git@github.com:"):]

    if raw.startswith("http://") or raw.startswith("https://"):
        parsed = urlparse(raw)
        if parsed.hostname not in {"github.com", "www.github.com"}:
            raise SystemExit(f"{field} must point to github.com.")
        parts = [p for p in parsed.path.split("/") if p]
        if len(parts) < 2:
            raise SystemExit(f"{field} must identify owner/repo.")
        owner, repo = parts[0], parts[1]
    else:
        raw = raw.split("#", 1)[0].split("?", 1)[0].strip("/")
        parts = raw.split("/")
        if len(parts) != 2:
            raise SystemExit(f"{field} must use owner/repo or a GitHub repository URL.")
        owner, repo = parts

    if repo.endswith(".git"):
        repo = repo[:-4]

    allowed = re.compile(r"^[A-Za-z0-9_.-]+$")
    if not allowed.fullmatch(owner) or not allowed.fullmatch(repo):
        raise SystemExit(f"{field} contains unsupported owner/repository characters.")

    return f"{owner}/{repo}"

source_repo = normalize_repo(get("source_repo"), "source_repo")
output_raw = get("output_repo")
output_repo = normalize_repo(output_raw, "output_repo") if output_raw else source_repo

source_ref = get("source_ref")
if source_ref:
    if source_ref.startswith("-") or ".." in source_ref or not re.fullmatch(r"[A-Za-z0-9._/-]+", source_ref):
        raise SystemExit("source_ref contains unsupported characters or an unsafe ref.")

project_path = get("project_path").strip("/")
if project_path in {".", ""}:
    project_path = ""
elif project_path.startswith("/") or "\n" in project_path or "\r" in project_path or "\\" in project_path:
    raise SystemExit("project_path must be a relative repository path.")
else:
    parts = project_path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise SystemExit("project_path contains an unsafe path segment.")

project_type = get("project_type", "auto")
if project_type not in {"auto", "xcode", "capacitor", "flutter", "react-native"}:
    raise SystemExit("Unsupported project type.")

build_mode = get("build_mode", "unsigned")
if build_mode not in {"unsigned", "app-store"}:
    raise SystemExit("Unsupported build mode.")

output_visibility = get("output_visibility", "private")
if output_visibility not in {"private", "public"}:
    raise SystemExit("Unsupported output visibility.")

log_mode = get("log_mode", "private")
if log_mode not in {"private", "verbose"}:
    raise SystemExit("Unsupported log mode.")

output_name = get("output_name")
if output_name and not re.fullmatch(r"[A-Za-z0-9._-]+", output_name):
    raise SystemExit("output_name may contain only letters, numbers, dot, underscore and dash.")

scheme = get("scheme")
if "\n" in scheme or "\r" in scheme:
    raise SystemExit("scheme contains unsupported characters.")

values = {
    "SOURCE_REPO": source_repo,
    "SOURCE_REF": source_ref,
    "PROJECT_PATH": project_path,
    "PROJECT_TYPE": project_type,
    "BUILD_MODE": build_mode,
    "SCHEME": scheme,
    "OUTPUT_NAME": output_name,
    "OUTPUT_REPO": output_repo,
    "OUTPUT_VISIBILITY": output_visibility,
    "LOG_MODE": log_mode,
}

for key, value in values.items():
    print(f"{key}={shlex.quote(value)}")
PY

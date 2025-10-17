#!/usr/bin/env bash

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found on PATH" >&2
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <new-webhook-url> [profile-json]" >&2
  exit 1
fi

new_url=$1
profile_file=${2:-test/integration/fixtures/profile/profiles.json}

if [[ ! -f "$profile_file" ]]; then
  echo "Profile file not found: $profile_file" >&2
  exit 1
fi

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

jq --arg url "$new_url" '
  .verifiers |= map(
    if (.verifier | type) == "object" then
      .verifier.webHook = $url
    else
      .
    end
  )
' "$profile_file" >"$tmp_file"

mv "$tmp_file" "$profile_file"

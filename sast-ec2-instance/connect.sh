#!/usr/bin/env bash
# Open an SSM Session Manager shell on the lab instance.
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
TARGET="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$TARGET" && -f "$SCRIPT_DIR/.state/last-instance-id" ]]; then
  TARGET="$(cat "$SCRIPT_DIR/.state/last-instance-id")"
fi
if [[ -z "$REGION" && -f "$SCRIPT_DIR/.state/last-region" ]]; then
  REGION="$(cat "$SCRIPT_DIR/.state/last-region")"
fi
REGION="${REGION:-us-east-1}"

[[ -n "$TARGET" ]] || { echo "usage: $0 <instance-id>" >&2; exit 1; }

command -v session-manager-plugin >/dev/null || {
  echo "Install the Session Manager plugin:" >&2
  echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" >&2
  exit 1
}

exec aws ssm start-session --region "$REGION" --target "$TARGET"

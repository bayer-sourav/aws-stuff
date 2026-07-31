#!/usr/bin/env bash
# Terminate the lab instance. Does not delete IAM role / SG (safe to reuse).
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

echo "terminating $TARGET in $REGION"
aws ec2 terminate-instances --region "$REGION" --instance-ids "$TARGET" >/dev/null
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$TARGET"
echo "done"
rm -f "$SCRIPT_DIR/.state/last-instance-id"

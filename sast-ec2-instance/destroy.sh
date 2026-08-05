#!/usr/bin/env bash
# Terminate the lab instance. Does not delete IAM role / SG / key pair (safe to reuse).
# Removes the managed ~/.ssh/config Host block so Cursor dropdown stays clean.
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
NAME="${NAME:-sast-lab}"
SSH_HOST="${SSH_HOST:-${NAME}}"
SSH_CONFIG="${SSH_CONFIG:-${HOME}/.ssh/config}"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  # Prefer HostName from the managed SSH block, else Name tag.
  if [[ -f "$SSH_CONFIG" ]]; then
    TARGET="$(awk -v host="$SSH_HOST" '
      $0 == "# BEGIN aws-stuff:" host {inblock=1; next}
      $0 == "# END aws-stuff:" host {inblock=0}
      inblock && $1 == "HostName" {print $2; exit}
    ' "$SSH_CONFIG")"
  fi
  if [[ -z "$TARGET" ]]; then
    TARGET="$(aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag:Name,Values=${NAME}" \
                "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query 'Reservations[].Instances[].InstanceId' --output text | awk '{print $1}')"
  fi
fi

[[ -n "$TARGET" && "$TARGET" != "None" ]] || {
  echo "no instance found (pass id, or set NAME= matching the Name tag)" >&2
  exit 1
}

echo "terminating $TARGET in $REGION"
aws ec2 terminate-instances --region "$REGION" --instance-ids "$TARGET" >/dev/null
aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$TARGET"

if [[ -f "$SSH_CONFIG" ]]; then
  tmp="$(mktemp)"
  sed "/^# BEGIN aws-stuff:${SSH_HOST}\$/,/^# END aws-stuff:${SSH_HOST}\$/d" "$SSH_CONFIG" >"$tmp"
  cat "$tmp" >"$SSH_CONFIG"
  rm -f "$tmp"
  echo "removed SSH host '${SSH_HOST}' from $SSH_CONFIG"
fi

echo "done"

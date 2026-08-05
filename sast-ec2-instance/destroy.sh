#!/usr/bin/env bash
# Tear down everything create.sh made: instance, SG, IAM role/profile, EC2 key pair, SSH Host block.
# Does not delete your local private key (~/.ssh/id_ed25519).
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
NAME="${NAME:-sast-lab}"
ROLE_NAME="${ROLE_NAME:-${NAME}-ssm-role}"
PROFILE_NAME="${PROFILE_NAME:-${NAME}-ssm-profile}"
SG_NAME="${SG_NAME:-${NAME}-ssm-sg}"
KEY_NAME="${KEY_NAME:-${NAME}}"
SSH_HOST="${SSH_HOST:-${NAME}}"
SSH_CONFIG="${SSH_CONFIG:-${HOME}/.ssh/config}"
TARGET="${1:-}"

echo "destroy name=$NAME region=$REGION"

# --- instance ---
if [[ -z "$TARGET" ]]; then
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

if [[ -n "$TARGET" && "$TARGET" != "None" ]]; then
  echo "terminating $TARGET"
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$TARGET" >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$TARGET"
else
  echo "no instance to terminate (continuing with SG/IAM/key cleanup)"
fi

# --- security group (retry: ENI release can lag after terminate) ---
SG_ID="$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
  echo "deleting security group $SG_NAME ($SG_ID)"
  for _ in $(seq 1 24); do
    if aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" 2>/dev/null; then
      break
    fi
    sleep 5
  done
  # confirm
  LEFT="$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  if [[ -n "$LEFT" && "$LEFT" != "None" ]]; then
    echo "warning: could not delete SG $SG_ID yet (still in use?)" >&2
  fi
else
  echo "security group $SG_NAME not found"
fi

# --- instance profile + role ---
if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
  echo "deleting instance profile $PROFILE_NAME"
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME" 2>/dev/null || true
  aws iam delete-instance-profile --instance-profile-name "$PROFILE_NAME"
else
  echo "instance profile $PROFILE_NAME not found"
fi

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "deleting role $ROLE_NAME"
  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
  # detach anything else that got attached
  while read -r arn; do
    [[ -n "$arn" ]] || continue
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$arn" || true
  done < <(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n')
  aws iam delete-role --role-name "$ROLE_NAME"
else
  echo "role $ROLE_NAME not found"
fi

# --- EC2 key pair (not your local ~/.ssh key) ---
if aws ec2 describe-key-pairs --region "$REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "deleting EC2 key pair $KEY_NAME"
  aws ec2 delete-key-pair --region "$REGION" --key-name "$KEY_NAME"
else
  echo "EC2 key pair $KEY_NAME not found"
fi

# --- SSH config Host block ---
if [[ -f "$SSH_CONFIG" ]]; then
  tmp="$(mktemp)"
  sed "/^# BEGIN aws-stuff:${SSH_HOST}\$/,/^# END aws-stuff:${SSH_HOST}\$/d" "$SSH_CONFIG" >"$tmp"
  cat "$tmp" >"$SSH_CONFIG"
  rm -f "$tmp"
  echo "removed SSH host '${SSH_HOST}' from $SSH_CONFIG"
fi

echo "done"

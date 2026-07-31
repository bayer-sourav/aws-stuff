#!/usr/bin/env bash
# Create a GPU lab EC2 instance reachable via SSM Session Manager.
# Mirrors the shape documented in INSTANCE.md (g6e.4xlarge / AL2023 / 300G / SSM).
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
NAME="${NAME:-sast-lab}"
INSTANCE_TYPE="${INSTANCE_TYPE:-g6e.4xlarge}"
VOLUME_SIZE="${VOLUME_SIZE:-300}"
ROLE_NAME="${ROLE_NAME:-${NAME}-ssm-role}"
PROFILE_NAME="${PROFILE_NAME:-${NAME}-ssm-profile}"
SG_NAME="${SG_NAME:-${NAME}-ssm-sg}"
# Optional: KEY_NAME=my-key  SUBNET_ID=subnet-xxx  AMI_ID=ami-xxx
KEY_NAME="${KEY_NAME:-}"
SUBNET_ID="${SUBNET_ID:-}"
AMI_ID="${AMI_ID:-}"

AMI_PARAM="${AMI_PARAM:-/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-amazon-linux-2023/latest/ami-id}"

need() { command -v "$1" >/dev/null || { echo "missing dependency: $1" >&2; exit 1; }; }
need aws
need jq

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
echo "account=$ACCOUNT region=$REGION name=$NAME"

# --- IAM role + instance profile (SSM) ---
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "creating role $ROLE_NAME"
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST" >/dev/null
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
else
  echo "role $ROLE_NAME already exists"
fi

if ! aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1; then
  echo "creating instance profile $PROFILE_NAME"
  aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME"
  echo "waiting for instance profile to propagate..."
  sleep 15
else
  echo "instance profile $PROFILE_NAME already exists"
fi

# --- networking ---
if [[ -z "$SUBNET_ID" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text)"
  [[ "$VPC_ID" != "None" && -n "$VPC_ID" ]] || { echo "no default VPC; set SUBNET_ID=" >&2; exit 1; }
  SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
    --query 'Subnets[0].SubnetId' --output text)"
  echo "using default vpc=$VPC_ID subnet=$SUBNET_ID"
else
  VPC_ID="$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$SUBNET_ID" \
    --query 'Subnets[0].VpcId' --output text)"
  echo "using subnet=$SUBNET_ID vpc=$VPC_ID"
fi

SG_ID="$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  echo "creating security group $SG_NAME (egress-only; SSM needs no inbound)"
  SG_ID="$(aws ec2 create-security-group --region "$REGION" \
    --group-name "$SG_NAME" --description "SSM-only lab ($NAME)" --vpc-id "$VPC_ID" \
    --query GroupId --output text)"
  # default egress allow-all is fine for Session Manager + package installs
else
  echo "security group $SG_ID already exists"
fi

# --- AMI ---
if [[ -z "$AMI_ID" ]]; then
  AMI_ID="$(aws ssm get-parameter --region "$REGION" --name "$AMI_PARAM" \
    --query 'Parameter.Value' --output text)"
fi
echo "ami=$AMI_ID type=$INSTANCE_TYPE root=${VOLUME_SIZE}G"

RUN_ARGS=(
  --region "$REGION"
  --image-id "$AMI_ID"
  --instance-type "$INSTANCE_TYPE"
  --subnet-id "$SUBNET_ID"
  --security-group-ids "$SG_ID"
  --iam-instance-profile "Name=$PROFILE_NAME"
  --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=${VOLUME_SIZE},VolumeType=gp3,DeleteOnTermination=true}"
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled,InstanceMetadataTags=enabled"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}}]"
  --count 1
)
# Associate a public IP so the instance can reach SSM endpoints without a VPC endpoint.
# (If your subnet/VPC already has SSM endpoints, you can drop this.)
RUN_ARGS+=(--associate-public-ip-address)

if [[ -n "$KEY_NAME" ]]; then
  RUN_ARGS+=(--key-name "$KEY_NAME")
fi

INSTANCE_ID="$(aws ec2 run-instances "${RUN_ARGS[@]}" --query 'Instances[0].InstanceId' --output text)"
echo "launched $INSTANCE_ID — waiting for running..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

echo "waiting for SSM agent to register (can take 1–3 min)..."
for i in $(seq 1 60); do
  STATUS="$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
  if [[ "$STATUS" == "Online" ]]; then
    echo "SSM Online"
    break
  fi
  sleep 5
done

if [[ "${STATUS:-}" != "Online" ]]; then
  echo "SSM not Online yet. Check IAM, outbound HTTPS, and:" >&2
  echo "  aws ssm describe-instance-information --region $REGION --filters Key=InstanceIds,Values=$INSTANCE_ID" >&2
  echo "Instance still created: $INSTANCE_ID" >&2
  exit 2
fi

cat <<EOF

Ready.
  instance: $INSTANCE_ID
  region:   $REGION

Connect:
  ./connect.sh $INSTANCE_ID

Or:
  aws ssm start-session --region $REGION --target $INSTANCE_ID

Tear down later:
  ./destroy.sh $INSTANCE_ID
EOF

# stash last instance id for convenience
mkdir -p "$(dirname "$0")/.state"
echo "$INSTANCE_ID" >"$(dirname "$0")/.state/last-instance-id"
echo "$REGION" >"$(dirname "$0")/.state/last-region"

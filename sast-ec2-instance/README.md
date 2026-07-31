# sast-ec2-instance

Recreate the SAST GPU lab EC2 instance (SSM Session Manager access) in any AWS account.

See [INSTANCE.md](INSTANCE.md) for what the original box looked like.

## What you get

| Setting | Default |
| --- | --- |
| Type | `g6e.4xlarge` (NVIDIA L40S) |
| AMI | Latest Deep Learning Base OSS Nvidia Driver GPU AMI (AL2023) via SSM Parameter Store |
| Root disk | 300 GB `gp3` |
| Access | **SSM Session Manager only** (no inbound SG rules) |
| IAM | Instance role with `AmazonSSMManagedInstanceCore` |

## Prerequisites (on your laptop / admin shell)

1. AWS CLI v2 configured for the **target** account (`aws sts get-caller-identity`)
2. Permissions to create IAM roles, instance profiles, security groups, and EC2 instances
3. [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for `./connect.sh`
4. `jq`
5. GPU quota for `g6e.4xlarge` in the region (request in Service Quotas if launch fails)
6. Default VPC **or** set `SUBNET_ID=...` (subnet needs a path to the internet or SSM VPC endpoints)

## Quick start

```bash
cd sast-ec2-instance
chmod +x create.sh connect.sh destroy.sh

# optional overrides
export AWS_REGION=us-east-1
# export INSTANCE_TYPE=g6e.2xlarge   # cheaper if quota/cost constrained
# export VOLUME_SIZE=300
# export NAME=sast-lab
# export KEY_NAME=my-keypair         # optional; SSM does not need it
# export SUBNET_ID=subnet-xxxxxxxx

./create.sh
./connect.sh          # uses last launched instance
# ./connect.sh i-0abc...

./destroy.sh          # terminate when done — GPU boxes are expensive
```

## Environment variables

| Var | Default | Purpose |
| --- | --- | --- |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | `us-east-1` | Region |
| `NAME` | `sast-lab` | Name tag + prefix for role/SG |
| `INSTANCE_TYPE` | `g6e.4xlarge` | EC2 type |
| `VOLUME_SIZE` | `300` | Root EBS size (GiB) |
| `ROLE_NAME` | `${NAME}-ssm-role` | IAM role |
| `PROFILE_NAME` | `${NAME}-ssm-profile` | Instance profile |
| `SG_NAME` | `${NAME}-ssm-sg` | Security group |
| `SUBNET_ID` | default VPC subnet | Where to launch |
| `KEY_NAME` | _(empty)_ | Optional SSH key |
| `AMI_ID` | looked up | Override AMI |
| `AMI_PARAM` | DLAMI base OSS nvidia AL2023 latest | SSM parameter for AMI lookup |

## Files

| File | Role |
| --- | --- |
| `create.sh` | IAM + SG + launch + wait for SSM Online |
| `connect.sh` | `aws ssm start-session` |
| `destroy.sh` | Terminate instance |
| `INSTANCE.md` | Fingerprint of the original lab box |
| `.state/` | Last instance id/region (gitignored) |

## Notes

- **Cost:** `g6e.4xlarge` is pricey. Destroy when idle.
- **Not a full disk clone:** This recreates the *platform* (GPU AL2023 + SSM), not your `~/Projects` data. Copy repos from git / S3 yourself.
- **SSM not coming Online:** instance needs outbound HTTPS (NAT/IGW or SSM interface endpoints) and the managed policy on the instance role.
- **IAM / SG reuse:** `create.sh` is idempotent for role, profile, and SG; only the instance is new each run.

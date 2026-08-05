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
| Cursor | Imports your local SSH pubkey + writes `Host sast-lab` into `~/.ssh/config` |

## Prerequisites (on your laptop / admin shell)

1. AWS CLI v2 configured for the **target** account (`aws sts get-caller-identity`)
2. Permissions to create IAM roles, instance profiles, security groups, key pairs, and EC2 instances
3. [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (needed for SSH-over-SSM and Cursor)
4. `jq`
5. GPU quota for `g6e.4xlarge` in the region (request in Service Quotas if launch fails)
6. Default VPC **or** set `SUBNET_ID=...` (subnet needs a path to the internet or SSM VPC endpoints)

## Quick start

```bash
cd sast-ec2-instance
chmod +x create.sh destroy.sh

# optional overrides
export AWS_REGION=us-east-1
# export INSTANCE_TYPE=g6e.2xlarge   # cheaper if quota/cost constrained
# export VOLUME_SIZE=300
# export NAME=sast-lab               # also used as SSH Host alias + EC2 key name
# export SUBNET_ID=subnet-xxxxxxxx   # optional; pins AZ — omit to let EC2 pick

./create.sh
# → imports ~/.ssh/id_ed25519.pub (or id_rsa / generates one)
# → launches instance with that key
# → upserts Host sast-lab in ~/.ssh/config (SSM ProxyCommand)

# Cursor: Remote-SSH: Connect to Host… → sast-lab
# or: ssh sast-lab

./destroy.sh          # instance + SG + IAM role/profile + EC2 key pair + SSH Host
```

## Connect from Cursor IDE

After `./create.sh`, the host is already in your SSH config.

1. Command Palette → **Remote-SSH: Connect to Host…** → **`sast-lab`** (or whatever `NAME`/`SSH_HOST` you set)
2. Cursor installs its server over the SSM SSH tunnel and opens a remote window

No inbound port 22 — traffic goes through Session Manager. Sanity check: `ssh sast-lab`.

`SKIP_SSH_CONFIG=1 ./create.sh` skips writing `~/.ssh/config`.

## Environment variables

| Var | Default | Purpose |
| --- | --- | --- |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | `us-east-1` | Region |
| `NAME` | `sast-lab` | Name tag + prefix for role/SG/key |
| `INSTANCE_TYPE` | `g6e.4xlarge` | Preferred EC2 type |
| `INSTANCE_TYPES` | `$INSTANCE_TYPE` | Comma list to try on capacity miss, e.g. `g6e.4xlarge,g6e.2xlarge` |
| `VOLUME_SIZE` | `300` | Root EBS size (GiB) |
| `ROLE_NAME` | `${NAME}-ssm-role` | IAM role |
| `PROFILE_NAME` | `${NAME}-ssm-profile` | Instance profile |
| `SG_NAME` | `${NAME}-ssm-sg` | Security group |
| `SUBNET_ID` | _(empty)_ | Pin one subnet; omit to try every default-VPC AZ for capacity |
| `KEY_NAME` | `${NAME}` | EC2 key pair (imported from local pubkey if missing) |
| `SSH_IDENTITY` | `~/.ssh/id_ed25519` or `id_rsa` | Private key path (`.pub` must exist) |
| `SSH_HOST` | `${NAME}` | Name shown in Cursor / `ssh` |
| `SSH_CONFIG` | `~/.ssh/config` | Where to write the Host block |
| `SKIP_SSH_CONFIG` | `0` | Set `1` to skip SSH config update |
| `AMI_ID` | looked up | Override AMI |
| `AMI_PARAM` | DLAMI base OSS nvidia AL2023 latest | SSM parameter for AMI lookup |

## Files

| File | Role |
| --- | --- |
| `create.sh` | IAM + SG + key + launch + SSH config + wait for SSM Online |
| `destroy.sh` | Full teardown: instance, SG, IAM role/profile, EC2 key pair, SSH Host |
| `INSTANCE.md` | Fingerprint of the original lab box |

## Notes

- **Capacity:** `g6e.*` is often scarce. `create.sh` walks all default-VPC AZs (and optional `INSTANCE_TYPES` fallbacks). If everything fails, try another `AWS_REGION` or smaller type.
- **Cost:** `g6e.4xlarge` is pricey. Destroy when idle.
- **Not a full disk clone:** This recreates the *platform* (GPU AL2023 + SSM), not your `~/Projects` data. Copy repos from git / S3 yourself.
- **SSM not coming Online:** instance needs outbound HTTPS (NAT/IGW or SSM interface endpoints) and the managed policy on the instance role.
- **IAM / SG / key:** `create.sh` reuses them if they still exist; `destroy.sh` deletes them all (not your local private key).
- **Existing key pair:** if `KEY_NAME` already exists in the account from something else, destroy will delete it when `KEY_NAME` matches — use a dedicated name (default `sast-lab`).

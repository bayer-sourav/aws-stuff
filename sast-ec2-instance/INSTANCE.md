# Current instance fingerprint

Captured from the lab box this repo was authored against. Use this as the target shape when recreating elsewhere — not as hard-coded IDs (those are account-specific).

| Field | Value |
| --- | --- |
| Region / AZ | `us-east-1` / `us-east-1a` |
| Instance type | `g6e.4xlarge` (1× NVIDIA L40S, ~46 GB GPU mem, 16 vCPU, 128 GiB RAM) |
| OS | Amazon Linux 2023 |
| Root volume | 300 GB EBS (`gp3`-class), mounted at `/` |
| Ephemeral store | ~559 GB NVMe instance store (`nvme1n1`) — **lost on stop** |
| Access | SSM Session Manager (no inbound SSH required) |
| IAM role name | `mon-default-instance-role` |
| Notable software | `amazon-ssm-agent`, Docker 25, NVIDIA driver ~610, CUDA toolkit 12.8+, nvidia-container-toolkit |

Account-specific IDs from the source box (do **not** reuse in another account):

- Instance: `i-086e1d0887788ad7a`
- AMI: `ami-0a4bb605fd8897f26`
- VPC / subnet / SG: default-VPC style (`vpc-0e928f2f0bc809f70`, `subnet-0599bf41ad9677081`, `sg-0af2b43c7cd04548e` / `launch-wizard-1`)
- SSH key name (optional): `sast-aws-ec2`

The recreate script intentionally:

1. Looks up a **public** Deep Learning Base OSS Nvidia Driver GPU AMI (AL2023) in the target region
2. Creates a fresh IAM role + instance profile with `AmazonSSMManagedInstanceCore`
3. Tries every default-VPC AZ for capacity (or `SUBNET_ID` if you pin one)
4. Opens **no inbound** SG rules — Session Manager only needs outbound HTTPS

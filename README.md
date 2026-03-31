# AWS Network Security Lab — IaC Portfolio

A multi-region AWS network security lab built entirely with CloudFormation and PowerShell automation. This project replicates enterprise-grade network architecture patterns including Transit Gateway mesh connectivity, Site-to-Site VPN with BGP, and AWS Network Firewall with active/active inspection.

Built by Derek McWilliams ([@MacGotHub](https://github.com/MacGotHub)) as a hands-on AWS learning project.

---

## Architecture Overview

### Current State
- Multi-region VPCs across `us-east-1` and `us-west-2`
- Transit Gateway peering with cross-region routing
- Full mesh Site-to-Site VPN with BGP dynamic routing
- Two simulated on-premises sites dual-homed to both regions
- 8 IPSec tunnels with dual-tunnel redundancy per connection
- VPN terminates directly on TGW (enterprise pattern)

### Planned
- AWS Network Firewall with active/active Gateway Load Balancer
- Dedicated inspection VPCs per region
- VPC Flow Logs with Splunk integration
- AWS Security Hub + GuardDuty

---

## Lab Structure
```
aws-cfn-project/
├── 01-vpc-ec2/                    # Lab 1 — Basic VPC + EC2
│   └── starter-vpc.yaml
├── 02-transit-gateway/            # Lab 2 — Multi-region TGW
│   ├── vpc-east.yaml
│   ├── vpc-west.yaml
│   ├── tgw-east.yaml
│   ├── tgw-west.yaml
│   └── README.md
├── 03-site-to-site-vpn/           # Lab 3 — Full mesh VPN + BGP
│   ├── vpc-onprem-east.yaml
│   ├── vpc-onprem-west.yaml
│   ├── vpn-tgw-east.yaml
│   ├── vpn-tgw-west.yaml
│   └── README.md
├── 04-network-firewall/           # Lab 4 — AWS Network Firewall (WIP)
│   ├── inspection-vpc-east.yaml
│   ├── inspection-vpc-west.yaml
│   ├── firewall-policy.yaml
│   ├── firewall-east.yaml
│   └── firewall-west.yaml
└── scripts/
    ├── deploy.ps1                 # Full environment deployment
    ├── teardown.ps1               # Full environment teardown
    └── generate-strongswan-configs.ps1  # Auto-generates VPN configs
```

---

## Network Design

| Component | CIDR | Region |
|---|---|---|
| VPC East | 10.0.0.0/16 | us-east-1 |
| VPC West | 10.1.0.0/16 | us-west-2 |
| On-prem Site 1 | 10.2.0.0/16 | us-east-1 (simulated) |
| On-prem Site 2 | 10.3.0.0/16 | us-west-2 (simulated) |
| Inspection VPC East | 10.4.0.0/16 | us-east-1 |
| Inspection VPC West | 10.5.0.0/16 | us-west-2 |

### BGP ASNs
| Router | ASN |
|---|---|
| TGW East | 64512 |
| TGW West | 64513 |
| On-prem Site 1 | 65001 |
| On-prem Site 2 | 65002 |

---

## Prerequisites

- AWS CLI installed and configured
- PowerShell (Windows) or pwsh (Mac/Linux)
- EC2 key pairs created in both `us-east-1` and `us-west-2` named `starter-key`

---

## Deployment

### Full deployment (Labs 1-3)
```powershell
.\scripts\deploy.ps1
```

### Generate Strongswan + Bird configs after deployment
```powershell
.\scripts\generate-strongswan-configs.ps1
```

### Apply configs to on-prem instances
Follow the output instructions from the generator script to SCP configs to each Strongswan instance.

### Teardown
```powershell
.\scripts\teardown.ps1
```

---

## Key Learnings

- CloudFormation does not support cross-region TGW peering attachments via `AWS::EC2::TransitGatewayPeeringAttachment` — use CLI instead
- VPN termination on TGW directly (vs VGW) is the modern enterprise pattern and eliminates the need for per-VPC VGW resources
- Strongswan VTI interfaces require Linux interface names ≤15 characters
- AWS Network Firewall CloudWatch log groups must exist before firewall deployment
- Windows line endings (CRLF) break Strongswan and Bird config files on Linux — use Unix line endings (LF)

---

## Cost Estimate (when running)

| Resource | Cost/hr |
|---|---|
| TGW East + West | ~$0.10 |
| TGW peering | ~$0.05 |
| VPN connections (4) | ~$0.20 |
| Network Firewall (2 regions) | ~$0.79 |
| EC2 instances (4x t3.micro) | ~$0.04 |
| **Total** | **~$1.18/hr** |

Always run `.\scripts\teardown.ps1` when finished to avoid unnecessary charges.

---

## Tools Used

- AWS CloudFormation
- AWS CLI
- PowerShell
- Strongswan (IPSec)
- Bird (BGP)
- VS Code
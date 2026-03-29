# AWS Multi-Region Transit Gateway Lab

## Architecture Overview
Two VPCs in separate AWS regions connected via Transit Gateway peering.

- **East VPC** (us-east-1): 10.0.0.0/16
- **West VPC** (us-west-2): 10.1.0.0/16
- **Transit Gateway peering** between us-east-1 and us-west-2

## Prerequisites
- AWS CLI installed and configured
- EC2 key pair created in both us-east-1 and us-west-2 named `starter-key`
- Your public IP in CIDR format (x.x.x.x/32)

## Deployment Order

### Step 1 - Deploy East VPC (us-east-1)
```bash
aws cloudformation deploy \
  --template-file 02-transit-gateway/vpc-east.yaml \
  --stack-name vpc-east-stack \
  --parameter-overrides \
    KeyPairName=starter-key \
    MyIPAddress=/32 \
    TGWEastId= \
  --region us-east-1
```

### Step 2 - Deploy West VPC (us-west-2)
```bash
aws cloudformation deploy \
  --template-file 02-transit-gateway/vpc-west.yaml \
  --stack-name vpc-west-stack \
  --parameter-overrides \
    KeyPairName=starter-key \
    MyIPAddress=/32 \
    TGWWestId= \
  --region us-west-2
```

### Step 3 - Deploy East Transit Gateway (us-east-1)
```bash
aws cloudformation deploy \
  --template-file 02-transit-gateway/tgw-east.yaml \
  --stack-name tgw-east-stack \
  --parameter-overrides \
    VPCEastId= \
    PrivateSubnetEastId= \
  --region us-east-1
```

### Step 4 - Deploy West Transit Gateway (us-west-2)
```bash
aws cloudformation deploy \
  --template-file 02-transit-gateway/tgw-west.yaml \
  --stack-name tgw-west-stack \
  --parameter-overrides \
    VPCWestId= \
    PrivateSubnetWestId= \
  --region us-west-2
```

### Step 5 - Create TGW Peering (CLI only - CloudFormation not supported)
> Note: AWS CloudFormation early validation rejects cross-region TGW peering.
> Use CLI instead.
```bash
# Initiate peering from East
aws ec2 create-transit-gateway-peering-attachment \
  --transit-gateway-id  \
  --peer-transit-gateway-id  \
  --peer-account-id  \
  --peer-region us-west-2 \
  --region us-east-1

# Accept peering on West side
aws ec2 accept-transit-gateway-peering-attachment \
  --transit-gateway-attachment-id  \
  --region us-west-2
```

### Step 6 - Add VPC Routes
> Note: Run after TGW peering is in available state.
```bash
# East VPC route to West
aws ec2 create-route \
  --route-table-id  \
  --destination-cidr-block 10.1.0.0/16 \
  --transit-gateway-id  \
  --region us-east-1

# West VPC route to East
aws ec2 create-route \
  --route-table-id  \
  --destination-cidr-block 10.0.0.0/16 \
  --transit-gateway-id  \
  --region us-west-2
```

## Resource IDs (this deployment)

| Resource | ID |
|---|---|
| VPC East | vpc-0cb93ba494d5a1932 |
| VPC West | vpc-0f87e2985426d7cd8 |
| TGW East | tgw-0db59754af7f14915 |
| TGW West | tgw-0f4abf2e8e2f3d443 |
| TGW Peering Attachment | tgw-attach-02eeb27f232a579b9 |
| East Public RT | rtb-0fa7ab2a60f78df4c |
| West Public RT | rtb-0c8f9f7662819c9bf |
| EC2 East Private IP | 10.0.1.30 |
| EC2 West Private IP | 10.1.1.14 |

## Teardown Order
Always delete in reverse order to avoid dependency errors.
```bash
# 1. Delete peering attachment
aws ec2 delete-transit-gateway-peering-attachment \
  --transit-gateway-attachment-id tgw-attach-02eeb27f232a579b9 \
  --region us-east-1

# 2. Delete West TGW stack
aws cloudformation delete-stack --stack-name tgw-west-stack --region us-west-2

# 3. Delete East TGW stack
aws cloudformation delete-stack --stack-name tgw-east-stack --region us-east-1

# 4. Delete West VPC stack
aws cloudformation delete-stack --stack-name vpc-west-stack --region us-west-2

# 5. Delete East VPC stack
aws cloudformation delete-stack --stack-name vpc-east-stack --region us-east-1
```

## Known Limitations
- TGW peering attachment must be created via CLI — CloudFormation early validation
  rejects cross-region peering attachments
- Key pairs are regional — a separate key pair is required in each region
- TGW resources cannot be stopped, only deleted — plan costs accordingly (~$0.17/hr)

## Connectivity Test
SSH into East EC2 and ping West EC2 private IP:
```bash
ssh -i starter-key.pem ec2-user@
ping 10.1.1.14
```
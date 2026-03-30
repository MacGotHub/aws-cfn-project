# ============================================
# AWS Full Mesh VPN Lab - Deploy Script
# ============================================
# Prerequisites:
# - AWS CLI configured
# - starter-key exists in us-east-1
# - starter-key exists in us-west-2
# - Update MY_IP before running

$MY_IP = "73.179.127.149/32"
$KEY_NAME = "starter-key"

Write-Host "`n=== Step 1: Deploying East VPC ===" -ForegroundColor Cyan
aws cloudformation deploy `
    --template-file 02-transit-gateway/vpc-east.yaml `
    --stack-name vpc-east-stack `
    --parameter-overrides `
        KeyPairName=$KEY_NAME `
        MyIPAddress=$MY_IP `
        TGWEastId=PLACEHOLDER `
    --region us-east-1

Write-Host "`n=== Step 2: Deploying West VPC ===" -ForegroundColor Cyan
aws cloudformation deploy `
    --template-file 02-transit-gateway/vpc-west.yaml `
    --stack-name vpc-west-stack `
    --parameter-overrides `
        KeyPairName=$KEY_NAME `
        MyIPAddress=$MY_IP `
        TGWWestId=PLACEHOLDER `
    --region us-west-2

Write-Host "`n=== Step 3: Deploying East TGW ===" -ForegroundColor Cyan
$VPCEastId = (aws cloudformation describe-stacks `
    --stack-name vpc-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`VPCEastId`].OutputValue' `
    --output text --region us-east-1)

$PrivateSubnetEastId = (aws cloudformation describe-stacks `
    --stack-name vpc-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetEastId`].OutputValue' `
    --output text --region us-east-1)

aws cloudformation deploy `
    --template-file 02-transit-gateway/tgw-east.yaml `
    --stack-name tgw-east-stack `
    --parameter-overrides `
        VPCEastId=$VPCEastId `
        PrivateSubnetEastId=$PrivateSubnetEastId `
    --region us-east-1

Write-Host "`n=== Step 4: Deploying West TGW ===" -ForegroundColor Cyan
$VPCWestId = (aws cloudformation describe-stacks `
    --stack-name vpc-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`VPCWestId`].OutputValue' `
    --output text --region us-west-2)

$PrivateSubnetWestId = (aws cloudformation describe-stacks `
    --stack-name vpc-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetWestId`].OutputValue' `
    --output text --region us-west-2)

aws cloudformation deploy `
    --template-file 02-transit-gateway/tgw-west.yaml `
    --stack-name tgw-west-stack `
    --parameter-overrides `
        VPCWestId=$VPCWestId `
        PrivateSubnetWestId=$PrivateSubnetWestId `
    --region us-west-2

Write-Host "`n=== Step 5: Creating TGW Peering ===" -ForegroundColor Cyan
$TGWEastId = (aws cloudformation describe-stacks `
    --stack-name tgw-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`TGWEastId`].OutputValue' `
    --output text --region us-east-1)

$TGWWestId = (aws cloudformation describe-stacks `
    --stack-name tgw-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`TGWWestId`].OutputValue' `
    --output text --region us-west-2)

$ACCOUNT_ID = (aws sts get-caller-identity --query 'Account' --output text)

$PeeringId = (aws ec2 create-transit-gateway-peering-attachment `
    --transit-gateway-id $TGWEastId `
    --peer-transit-gateway-id $TGWWestId `
    --peer-account-id $ACCOUNT_ID `
    --peer-region us-west-2 `
    --region us-east-1 `
    --query 'TransitGatewayPeeringAttachment.TransitGatewayAttachmentId' `
    --output text)

Write-Host "Peering attachment created: $PeeringId" -ForegroundColor Yellow
Write-Host "Waiting for peering to be available..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

aws ec2 accept-transit-gateway-peering-attachment `
    --transit-gateway-attachment-id $PeeringId `
    --region us-west-2

Write-Host "Waiting for peering to become available..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

Write-Host "`n=== Step 6: Adding VPC Routes ===" -ForegroundColor Cyan
$EastPublicRT = (aws ec2 describe-route-tables `
    --filters "Name=tag:Name,Values=public-rt-east" `
    --query 'RouteTables[0].RouteTableId' `
    --output text --region us-east-1)

$WestPublicRT = (aws ec2 describe-route-tables `
    --filters "Name=tag:Name,Values=public-rt-west" `
    --query 'RouteTables[0].RouteTableId' `
    --output text --region us-west-2)

aws ec2 create-route `
    --route-table-id $EastPublicRT `
    --destination-cidr-block 10.1.0.0/16 `
    --transit-gateway-id $TGWEastId `
    --region us-east-1

aws ec2 create-route `
    --route-table-id $WestPublicRT `
    --destination-cidr-block 10.0.0.0/16 `
    --transit-gateway-id $TGWWestId `
    --region us-west-2

Write-Host "`n=== Step 7: Deploying On-Prem Sites ===" -ForegroundColor Cyan
aws cloudformation deploy `
    --template-file 03-site-to-site-vpn/vpc-onprem-east.yaml `
    --stack-name onprem-east-stack `
    --parameter-overrides `
        KeyPairName=$KEY_NAME `
        MyIPAddress=$MY_IP `
    --region us-east-1

aws cloudformation deploy `
    --template-file 03-site-to-site-vpn/vpc-onprem-west.yaml `
    --stack-name onprem-west-stack `
    --parameter-overrides `
        KeyPairName=$KEY_NAME `
        MyIPAddress=$MY_IP `
    --region us-west-2

Write-Host "`n=== Step 8: Deploying VPN Connections ===" -ForegroundColor Cyan
$Site1IP = (aws cloudformation describe-stacks `
    --stack-name onprem-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`StrongswanEastPublicIP`].OutputValue' `
    --output text --region us-east-1)

$Site2IP = (aws cloudformation describe-stacks `
    --stack-name onprem-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`StrongswanWestPublicIP`].OutputValue' `
    --output text --region us-west-2)

aws cloudformation deploy `
    --template-file 03-site-to-site-vpn/vpn-east.yaml `
    --stack-name vpn-east-stack `
    --parameter-overrides `
        VPCEastId=$VPCEastId `
        Site1PublicIP=$Site1IP `
        Site2PublicIP=$Site2IP `
    --region us-east-1

aws cloudformation deploy `
    --template-file 03-site-to-site-vpn/vpn-west.yaml `
    --stack-name vpn-west-stack `
    --parameter-overrides `
        VPCWestId=$VPCWestId `
        Site1PublicIP=$Site1IP `
        Site2PublicIP=$Site2IP `
    --region us-west-2

Write-Host "`n=== Step 9: Downloading VPN Configs ===" -ForegroundColor Cyan
$VPNSite1EastId = (aws cloudformation describe-stacks `
    --stack-name vpn-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`VPNSite1EastId`].OutputValue' `
    --output text --region us-east-1)

$VPNSite2EastId = (aws cloudformation describe-stacks `
    --stack-name vpn-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`VPNSite2EastId`].OutputValue' `
    --output text --region us-east-1)

$VPNSite1WestId = (aws cloudformation describe-stacks `
    --stack-name vpn-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`VPNSite1WestId`].OutputValue' `
    --output text --region us-west-2)

$VPNSite2WestId = (aws cloudformation describe-stacks `
    --stack-name vpn-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`VPNSite2WestId`].OutputValue' `
    --output text --region us-west-2)

aws ec2 describe-vpn-connections `
    --vpn-connection-ids $VPNSite1EastId `
    --query 'VpnConnections[0].CustomerGatewayConfiguration' `
    --output text --region us-east-1 > 03-site-to-site-vpn\vpn-site1-east-config.xml

aws ec2 describe-vpn-connections `
    --vpn-connection-ids $VPNSite2EastId `
    --query 'VpnConnections[0].CustomerGatewayConfiguration' `
    --output text --region us-east-1 > 03-site-to-site-vpn\vpn-site2-east-config.xml

aws ec2 describe-vpn-connections `
    --vpn-connection-ids $VPNSite1WestId `
    --query 'VpnConnections[0].CustomerGatewayConfiguration' `
    --output text --region us-west-2 > 03-site-to-site-vpn\vpn-site1-west-config.xml

aws ec2 describe-vpn-connections `
    --vpn-connection-ids $VPNSite2WestId `
    --query 'VpnConnections[0].CustomerGatewayConfiguration' `
    --output text --region us-west-2 > 03-site-to-site-vpn\vpn-site2-west-config.xml

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps (manual):" -ForegroundColor Yellow
Write-Host "1. Run .\scripts\generate-strongswan-configs.ps1"
Write-Host "2. SSH into Site 1 ($Site1IP) and apply configs"
Write-Host "3. SSH into Site 2 ($Site2IP) and apply configs"
Write-Host ""
Write-Host "Key Resource IDs:" -ForegroundColor Yellow
Write-Host "TGW East:     $TGWEastId"
Write-Host "TGW West:     $TGWWestId"
Write-Host "TGW Peering:  $PeeringId"
Write-Host "Site 1 IP:    $Site1IP"
Write-Host "Site 2 IP:    $Site2IP"
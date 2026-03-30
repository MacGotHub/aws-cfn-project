# ============================================
# AWS Full Mesh VPN Lab - Teardown Script
# ============================================

Write-Host "`n=== Tearing down VPN stacks ===" -ForegroundColor Cyan
aws cloudformation delete-stack --stack-name vpn-east-stack --region us-east-1
aws cloudformation delete-stack --stack-name vpn-west-stack --region us-west-2

Write-Host "Waiting for VPN stacks to delete..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host "`n=== Tearing down On-Prem stacks ===" -ForegroundColor Cyan
aws cloudformation delete-stack --stack-name onprem-east-stack --region us-east-1
aws cloudformation delete-stack --stack-name onprem-west-stack --region us-west-2

Write-Host "`n=== Deleting TGW Peering ===" -ForegroundColor Cyan
$PeeringId = (aws ec2 describe-transit-gateway-peering-attachments `
    --filters "Name=state,Values=available" `
    --query 'TransitGatewayPeeringAttachments[0].TransitGatewayAttachmentId' `
    --output text --region us-east-1)

if ($PeeringId -ne "None" -and $PeeringId -ne "") {
    aws ec2 delete-transit-gateway-peering-attachment `
        --transit-gateway-attachment-id $PeeringId `
        --region us-east-1
    Write-Host "Deleted peering: $PeeringId" -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}

Write-Host "`n=== Tearing down TGW stacks ===" -ForegroundColor Cyan
aws cloudformation delete-stack --stack-name tgw-east-stack --region us-east-1
aws cloudformation delete-stack --stack-name tgw-west-stack --region us-west-2

Write-Host "Waiting for TGW stacks to delete..." -ForegroundColor Yellow
Start-Sleep -Seconds -60

Write-Host "`n=== Tearing down VPC stacks ===" -ForegroundColor Cyan
aws cloudformation delete-stack --stack-name vpc-east-stack --region us-east-1
aws cloudformation delete-stack --stack-name vpc-west-stack --region us-west-2

Write-Host "`n=== Tearing down starter VPC stack ===" -ForegroundColor Cyan
aws cloudformation delete-stack --stack-name starter-vpc-stack --region us-east-1

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "Teardown initiated!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Monitor progress in the AWS Console under CloudFormation in each region." -ForegroundColor Yellow
Write-Host "All stacks should be deleted within 10-15 minutes." -ForegroundColor Yellow
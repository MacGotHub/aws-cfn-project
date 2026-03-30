# ============================================
# Strongswan + Bird Config Generator
# ============================================
# Run this after deploy.ps1 to generate
# Strongswan and Bird configs for both sites
# ============================================

function Write-UnixFile {
    param($Path, $Content)
    $Content = $Content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $Content)
}

function Parse-VPNConfig {
    param($XmlFile)
    [xml]$config = Get-Content $XmlFile
    $tunnels = @()
    foreach ($tunnel in $config.vpn_connection.ipsec_tunnel) {
        $tunnels += @{
            CGW_Outside  = $tunnel.customer_gateway.tunnel_outside_address.ip_address
            CGW_Inside   = $tunnel.customer_gateway.tunnel_inside_address.ip_address
            CGW_CIDR     = $tunnel.customer_gateway.tunnel_inside_address.network_cidr
            VGW_Outside  = $tunnel.vpn_gateway.tunnel_outside_address.ip_address
            VGW_Inside   = $tunnel.vpn_gateway.tunnel_inside_address.ip_address
            CGW_ASN      = $tunnel.customer_gateway.bgp.asn
            VGW_ASN      = $tunnel.vpn_gateway.bgp.asn
            PSK          = $tunnel.ike.pre_shared_key
        }
    }
    return $tunnels
}

# Parse all 4 XML files
Write-Host "Parsing VPN config files..." -ForegroundColor Cyan
$S1E = Parse-VPNConfig "03-site-to-site-vpn\vpn-site1-east-config.xml"
$S1W = Parse-VPNConfig "03-site-to-site-vpn\vpn-site1-west-config.xml"
$S2E = Parse-VPNConfig "03-site-to-site-vpn\vpn-site2-east-config.xml"
$S2W = Parse-VPNConfig "03-site-to-site-vpn\vpn-site2-west-config.xml"

$Site1IP = $S1E[0].CGW_Outside
$Site2IP = $S2E[0].CGW_Outside
$Site1ASN = $S1E[0].CGW_ASN
$Site2ASN = $S2E[0].CGW_ASN

Write-Host "Site 1 IP: $Site1IP ASN: $Site1ASN" -ForegroundColor Yellow
Write-Host "Site 2 IP: $Site2IP ASN: $Site2ASN" -ForegroundColor Yellow

# Get Site 1 private IP from AWS
$Site1InstanceId = (aws cloudformation describe-stacks `
    --stack-name onprem-east-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`StrongswanEastInstanceId`].OutputValue' `
    --output text --region us-east-1)

$Site1PrivateIP = (aws ec2 describe-instances `
    --instance-ids $Site1InstanceId `
    --query 'Reservations[0].Instances[0].PrivateIpAddress' `
    --output text --region us-east-1)

# Get Site 2 private IP from AWS
$Site2InstanceId = (aws cloudformation describe-stacks `
    --stack-name onprem-west-stack `
    --query 'Stacks[0].Outputs[?OutputKey==`StrongswanWestInstanceId`].OutputValue' `
    --output text --region us-west-2)

$Site2PrivateIP = (aws ec2 describe-instances `
    --instance-ids $Site2InstanceId `
    --query 'Reservations[0].Instances[0].PrivateIpAddress' `
    --output text --region us-west-2)

Write-Host "Site 1 Private IP: $Site1PrivateIP" -ForegroundColor Yellow
Write-Host "Site 2 Private IP: $Site2PrivateIP" -ForegroundColor Yellow

# ── Generate Site 1 ipsec.conf ──
$Site1IpsecConf = @"
config setup
    charondebug="ike 1, knl 1, cfg 1"

conn %default
    ikelifetime=28800s
    keylife=3600s
    rekeymargin=3m
    keyingtries=%forever
    authby=secret
    keyexchange=ikev1
    mobike=no
    ike=aes128-sha1-modp1024!
    esp=aes128-sha1-modp1024!
    dpdaction=restart
    dpddelay=10s
    dpdtimeout=30s
    leftupdown=/etc/strongswan/ipsec-vti.sh
    installpolicy=yes
    compress=no
    type=tunnel

conn s1-et1
    left=$Site1PrivateIP
    leftid=$Site1IP
    right=$($S1E[0].VGW_Outside)
    rightid=$($S1E[0].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=100
    auto=start

conn s1-et2
    left=$Site1PrivateIP
    leftid=$Site1IP
    right=$($S1E[1].VGW_Outside)
    rightid=$($S1E[1].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=200
    auto=start

conn s1-wt1
    left=$Site1PrivateIP
    leftid=$Site1IP
    right=$($S1W[0].VGW_Outside)
    rightid=$($S1W[0].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=300
    auto=start

conn s1-wt2
    left=$Site1PrivateIP
    leftid=$Site1IP
    right=$($S1W[1].VGW_Outside)
    rightid=$($S1W[1].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=400
    auto=start
"@

# ── Generate Site 1 ipsec.secrets ──
$Site1Secrets = @"
$Site1IP $($S1E[0].VGW_Outside) : PSK "$($S1E[0].PSK)"
$Site1IP $($S1E[1].VGW_Outside) : PSK "$($S1E[1].PSK)"
$Site1IP $($S1W[0].VGW_Outside) : PSK "$($S1W[0].PSK)"
$Site1IP $($S1W[1].VGW_Outside) : PSK "$($S1W[1].PSK)"
"@

# ── Generate Site 1 ipsec-vti.sh ──
$Site1VtiScript = @"
#!/bin/bash
set -o nounset
set -o errexit

IP=`$(which ip)

case "`${PLUTO_VERB}" in
    up-client)
        case "`${PLUTO_CONNECTION}" in
            s1-et1) VTI_LOCAL=$($S1E[0].CGW_Inside)/$($S1E[0].CGW_CIDR); VTI_IF=vti1; VTI_KEY=100 ;;
            s1-et2) VTI_LOCAL=$($S1E[1].CGW_Inside)/$($S1E[1].CGW_CIDR); VTI_IF=vti2; VTI_KEY=200 ;;
            s1-wt1) VTI_LOCAL=$($S1W[0].CGW_Inside)/$($S1W[0].CGW_CIDR); VTI_IF=vti3; VTI_KEY=300 ;;
            s1-wt2) VTI_LOCAL=$($S1W[1].CGW_Inside)/$($S1W[1].CGW_CIDR); VTI_IF=vti4; VTI_KEY=400 ;;
        esac
        `${IP} tunnel add `${VTI_IF} mode vti local `${PLUTO_ME} remote `${PLUTO_PEER} key `${VTI_KEY}
        `${IP} link set `${VTI_IF} up mtu 1419
        `${IP} addr add `${VTI_LOCAL} dev `${VTI_IF}
        sysctl -w net.ipv4.conf.`${VTI_IF}.disable_policy=1
        sysctl -w net.ipv4.conf.`${VTI_IF}.rp_filter=2
        ;;
    down-client)
        case "`${PLUTO_CONNECTION}" in
            s1-et1) VTI_IF=vti1 ;;
            s1-et2) VTI_IF=vti2 ;;
            s1-wt1) VTI_IF=vti3 ;;
            s1-wt2) VTI_IF=vti4 ;;
        esac
        `${IP} tunnel del `${VTI_IF} || true
        ;;
esac
"@

# ── Generate Site 1 bird.conf ──
$Site1BirdConf = @"
router id $Site1IP;

log syslog all;

protocol kernel {
    export all;
    import all;
}

protocol device {
    scan time 10;
}

protocol direct {
    interface "vti*";
}

protocol bgp east_t1 {
    local $($S1E[0].CGW_Inside) as $Site1ASN;
    neighbor $($S1E[0].VGW_Inside) as $($S1E[0].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}

protocol bgp east_t2 {
    local $($S1E[1].CGW_Inside) as $Site1ASN;
    neighbor $($S1E[1].VGW_Inside) as $($S1E[1].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}

protocol bgp west_t1 {
    local $($S1W[0].CGW_Inside) as $Site1ASN;
    neighbor $($S1W[0].VGW_Inside) as $($S1W[0].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}

protocol bgp west_t2 {
    local $($S1W[1].CGW_Inside) as $Site1ASN;
    neighbor $($S1W[1].VGW_Inside) as $($S1W[1].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}
"@

# ── Generate Site 2 ipsec.conf ──
$Site2IpsecConf = @"
config setup
    charondebug="ike 1, knl 1, cfg 1"

conn %default
    ikelifetime=28800s
    keylife=3600s
    rekeymargin=3m
    keyingtries=%forever
    authby=secret
    keyexchange=ikev1
    mobike=no
    ike=aes128-sha1-modp1024!
    esp=aes128-sha1-modp1024!
    dpdaction=restart
    dpddelay=10s
    dpdtimeout=30s
    leftupdown=/etc/strongswan/ipsec-vti.sh
    installpolicy=yes
    compress=no
    type=tunnel

conn s2-et1
    left=$Site2PrivateIP
    leftid=$Site2IP
    right=$($S2E[0].VGW_Outside)
    rightid=$($S2E[0].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=100
    auto=start

conn s2-et2
    left=$Site2PrivateIP
    leftid=$Site2IP
    right=$($S2E[1].VGW_Outside)
    rightid=$($S2E[1].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=200
    auto=start

conn s2-wt1
    left=$Site2PrivateIP
    leftid=$Site2IP
    right=$($S2W[0].VGW_Outside)
    rightid=$($S2W[0].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=300
    auto=start

conn s2-wt2
    left=$Site2PrivateIP
    leftid=$Site2IP
    right=$($S2W[1].VGW_Outside)
    rightid=$($S2W[1].VGW_Outside)
    leftsubnet=0.0.0.0/0
    rightsubnet=0.0.0.0/0
    mark=400
    auto=start
"@

# ── Generate Site 2 ipsec.secrets ──
$Site2Secrets = @"
$Site2IP $($S2E[0].VGW_Outside) : PSK "$($S2E[0].PSK)"
$Site2IP $($S2E[1].VGW_Outside) : PSK "$($S2E[1].PSK)"
$Site2IP $($S2W[0].VGW_Outside) : PSK "$($S2W[0].PSK)"
$Site2IP $($S2W[1].VGW_Outside) : PSK "$($S2W[1].PSK)"
"@

# ── Generate Site 2 ipsec-vti.sh ──
$Site2VtiScript = @"
#!/bin/bash
set -o nounset
set -o errexit

IP=`$(which ip)

case "`${PLUTO_VERB}" in
    up-client)
        case "`${PLUTO_CONNECTION}" in
            s2-et1) VTI_LOCAL=$($S2E[0].CGW_Inside)/$($S2E[0].CGW_CIDR); VTI_IF=vti1; VTI_KEY=100 ;;
            s2-et2) VTI_LOCAL=$($S2E[1].CGW_Inside)/$($S2E[1].CGW_CIDR); VTI_IF=vti2; VTI_KEY=200 ;;
            s2-wt1) VTI_LOCAL=$($S2W[0].CGW_Inside)/$($S2W[0].CGW_CIDR); VTI_IF=vti3; VTI_KEY=300 ;;
            s2-wt2) VTI_LOCAL=$($S2W[1].CGW_Inside)/$($S2W[1].CGW_CIDR); VTI_IF=vti4; VTI_KEY=400 ;;
        esac
        `${IP} tunnel add `${VTI_IF} mode vti local `${PLUTO_ME} remote `${PLUTO_PEER} key `${VTI_KEY}
        `${IP} link set `${VTI_IF} up mtu 1419
        `${IP} addr add `${VTI_LOCAL} dev `${VTI_IF}
        sysctl -w net.ipv4.conf.`${VTI_IF}.disable_policy=1
        sysctl -w net.ipv4.conf.`${VTI_IF}.rp_filter=2
        ;;
    down-client)
        case "`${PLUTO_CONNECTION}" in
            s2-et1) VTI_IF=vti1 ;;
            s2-et2) VTI_IF=vti2 ;;
            s2-wt1) VTI_IF=vti3 ;;
            s2-wt2) VTI_IF=vti4 ;;
        esac
        `${IP} tunnel del `${VTI_IF} || true
        ;;
esac
"@

# ── Generate Site 2 bird.conf ──
$Site2BirdConf = @"
router id $Site2IP;

log syslog all;

protocol kernel {
    export all;
    import all;
}

protocol device {
    scan time 10;
}

protocol direct {
    interface "vti*";
}

protocol bgp east_t1 {
    local $($S2E[0].CGW_Inside) as $Site2ASN;
    neighbor $($S2E[0].VGW_Inside) as $($S2E[0].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}

protocol bgp east_t2 {
    local $($S2E[1].CGW_Inside) as $Site2ASN;
    neighbor $($S2E[1].VGW_Inside) as $($S2E[1].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}

protocol bgp west_t1 {
    local $($S2W[0].CGW_Inside) as $Site2ASN;
    neighbor $($S2W[0].VGW_Inside) as $($S2W[0].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}

protocol bgp west_t2 {
    local $($S2W[1].CGW_Inside) as $Site2ASN;
    neighbor $($S2W[1].VGW_Inside) as $($S2W[1].VGW_ASN);
    export all;
    import all;
    hold time 30;
    keepalive time 10;
}
"@

# ── Write all files ──
Write-Host "`nWriting config files..." -ForegroundColor Cyan

New-Item -Path "scripts\site1-configs" -ItemType Directory -Force | Out-Null
New-Item -Path "scripts\site2-configs" -ItemType Directory -Force | Out-Null

Write-UnixFile "scripts\site1-configs\ipsec.conf" $Site1IpsecConf
Write-UnixFile "scripts\site1-configs\ipsec.secrets" $Site1Secrets
Write-UnixFile "scripts\site1-configs\bird.conf" $Site1BirdConf
Write-UnixFile "scripts\site2-configs\ipsec.conf" $Site2IpsecConf
Write-UnixFile "scripts\site2-configs\ipsec.secrets" $Site2Secrets
Write-UnixFile "scripts\site2-configs\ipsec-vti.sh" $Site2VtiScript
Write-UnixFile "scripts\site2-configs\bird.conf" $Site2BirdConf

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "Config files generated!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Site 1 configs: scripts\site1-configs\" -ForegroundColor Yellow
Write-Host "Site 2 configs: scripts\site2-configs\" -ForegroundColor Yellow
Write-Host ""
Write-Host "To apply Site 1 configs, SSH in and run:" -ForegroundColor Yellow
Write-Host "  scp -i starter-key.pem scripts/site1-configs/* ec2-user@${Site1IP}:~/"
Write-Host "  ssh -i starter-key.pem ec2-user@${Site1IP}"
Write-Host "  sudo cp ipsec.conf ipsec.secrets ipsec-vti.sh /etc/strongswan/"
Write-Host "  sudo chmod +x /etc/strongswan/ipsec-vti.sh"
Write-Host "  sudo cp bird.conf /etc/"
Write-Host "  sudo systemctl restart strongswan && sudo systemctl restart bird"
Write-Host ""
Write-Host "To apply Site 2 configs, SSH in and run:" -ForegroundColor Yellow
Write-Host "  scp -i 02-transit-gateway\starter-key-west.pem scripts/site2-configs/* ec2-user@${Site2IP}:~/"
Write-Host "  ssh -i 02-transit-gateway\starter-key-west.pem ec2-user@${Site2IP}"
Write-Host "  sudo cp ipsec.conf ipsec.secrets ipsec-vti.sh /etc/strongswan/"
Write-Host "  sudo chmod +x /etc/strongswan/ipsec-vti.sh"
Write-Host "  sudo cp bird.conf /etc/"
Write-Host "  sudo systemctl restart strongswan && sudo systemctl restart bird"
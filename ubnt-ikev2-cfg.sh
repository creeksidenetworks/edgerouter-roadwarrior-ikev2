#!/bin/bash

echo -e " *** EdgeRouter/USG roadwarrior auto configurator *** "
echo -e " ***        (c) Creekside Networks LLC 2020       *** \n"

if [ "$1" != "" ]; then
  HOST=$1
else
  read -p "VPN Server's FQDN: " HOST
fi

IPADDRESS=$(host $HOST | grep -o "IPv4 address.*" | awk '{print $3}')

while [$IPADDRESS == ""]
do
    echo -e "\nCan not resolve server FQDN $HOST, retry...\n"
    read -p "VPN Server's FQDN: " HOST
    IPADDRESS=$(host $HOST | grep -o "IPv4 address.*" | awk '{print $3}')
done

# Please update following variables per your application
COUNTRY_CODE=US
ORGANISATION="Creekside Customer"
# end of pre-defined variables

# find out default route interface
IPSEC_INTF=$(ip -4 route | grep default | grep -o "dev.*" | awk '{print $2}') 

echo -e "Summary of configurations"
echo -e "  VPN Server FQDN = ${HOST}"
echo -e "  VPN Server IP   = ${IPADDRESS}"
echo -e "  WAN interace    = ${IPSEC_INTF}"

# pre-defined edgeos commands
ROUTER_CFGCMD=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper
ROUTER_RSACMD=/opt/vyatta/bin/sudo-users/gen_local_rsa_key.pl

# Prepare working directories
rm -rf ipsec.d
mkdir -p ipsec.d/{cacerts,certs,private,p12,reqs}

echo -e "\nGenerate self-signed CA named ${ORGANISATION} Root CA\n"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout ipsec.d/private/ca-key.pem \
    -out ipsec.d/cacerts/ca-cert.cer \
    -subj "/CN=${HOST^^} ROOT CA"

#    -subj "/C=${COUNTRY_CODE}/O=${ORGANISATION}/CN=${ORGANISATION} Root CA"


openssl x509 -text -in  ipsec.d/cacerts/ca-cert.cer

echo -e "\nGenerate server key, stored in /config/ipsec.d/rsa-keys\n"

sudo $ROUTER_RSACMD | grep 0sAw | tee localhost.pub

sudo cp /config/ipsec.d/rsa-keys/localhost.key ipsec.d/private/server-key.pem
sudo chmod +r ipsec.d/private/server-key.pem
sudo mv localhost.pub /config/ipsec.d/rsa-keys/

echo -e "\nSign server certificate for ${HOST}\n"

openssl req -new -nodes \
  -key ipsec.d/private/server-key.pem \
  -out ipsec.d/reqs/server-req.csr \
  -subj /CN=$HOST

echo "authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${HOST}
IP.1 =${IPADDRESS}" >  ipsec.d/reqs/server-req.ext

openssl x509 -req -days 3650 -CAcreateserial \
  -in  ipsec.d/reqs/server-req.csr \
  -CA ipsec.d/cacerts/ca-cert.cer \
  -CAkey ipsec.d/private/ca-key.pem  \
  -out ipsec.d/certs/server-cert.pem \
  -extfile ipsec.d/reqs/server-req.ext


openssl x509 -text -in ipsec.d/certs/server-cert.pem

sudo cp -r ipsec.d/{cacerts,private,certs} /config/ipsec.d/

echo -e "\n **** Now generate ipsec.conf & ipsec.secrets ****\n" 

echo "
# customized roadwarrior configuration by Creekside Networks LLC

config setup
    uniqueids=never

ca rootca
    cacert=/config/ipsec.d/cacerts/ca-cert.cer
    auto=add

conn default-con
    ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,aes128-sha1,3des-sha1!
    keyexchange=ikev2
    compress=no
    type=tunnel
    fragmentation=yes
    forceencaps=yes
    ikelifetime=4h
    lifetime=2h
    dpddelay=300s
    dpdtimeout=30s
    dpdaction=clear
    rekey=no
    left=%any
    leftcert=/config/ipsec.d/certs/server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightsendcert=never
    rightauth=eap-mschapv2
    eap_identity=%identity

conn winlx
    also=default-con
    rightsourceip=10.255.255.1/24
    rightdns=8.8.8.8,8.8.4.4
    auto=add

conn apple
    also=winlx
    leftid=@${HOST}
" | sudo tee /config/ipsec.d/ipsec.conf

echo "
# roadwarrior user accounts 

 : RSA /config/ipsec.d/private/server-key.pem

bob  : EAP bobpasswd
alice : EAP alicepasswd
"  | sudo tee /config/ipsec.d/ipsec.secrets

# Enable VPN configuration
echo -e "\nLet's enable road warrior VPN configuration\n"
$ROUTER_CFGCMD begin
$ROUTER_CFGCMD set vpn rsa-keys local-key file /config/ipsec.d/rsa-keys/localhost.key
$ROUTER_CFGCMD set vpn rsa-keys rsa-key-name localhost.pub rsa-key $(</config/ipsec.d/rsa-keys/localhost.pub)
$ROUTER_CFGCMD set vpn ipsec include-ipsec-conf /config/ipsec.d/ipsec.conf
$ROUTER_CFGCMD set vpn ipsec include-ipsec-secrets /config/ipsec.d/ipsec.secrets
$ROUTER_CFGCMD set vpn ipsec ipsec-interfaces interface $IPSEC_INTF
$ROUTER_CFGCMD commit
$ROUTER_CFGCMD save
$ROUTER_CFGCMD end

echo -e "\n **** completed ****\n" 

exit 0


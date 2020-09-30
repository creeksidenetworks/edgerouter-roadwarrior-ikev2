#!/bin/bash

if [ "$1" != "" ]; then
  USERNAME=$1
else
  echo "% No username specified"
  echo "% usage: $0 username"
exit
fi

# change below to fit your application
DOMAIN=creekside.lab
COUNTRY_CODE=US
ORGANISATION="Creekside Labs"
# end of change

USERID="${USERNAME}@${DOMAIN}"

echo -e "We will create client certs for ${USERID} of ${ORGANISATION}\n"

openssl genrsa -out ipsec.d/private/$USERNAME-key.pem 2048

openssl req -new -nodes \
  -key ipsec.d/private/$USERNAME-key.pem \
  -out ipsec.d/reqs/$USERNAME-req.csr \
  -subj "/C=$COUNTRY_CODE/O=$ORGANISATION/CN=$USERID"

echo "authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
#extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names

[alt_names]
email = $USERID" >  ipsec.d/reqs/$USERNAME-req.ext


openssl x509 -req -days 3650 -CAcreateserial \
  -in  ipsec.d/reqs/$USERNAME-req.csr\
  -CA ipsec.d/cacerts/ca-cert.cer \
  -CAkey ipsec.d/private/ca-key.pem  \
  -out ipsec.d/certs/$USERNAME-cert.pem \
  -extfile ipsec.d/reqs/$USERNAME-req.ext

echo -e "\nCreate pkcs12 file for ${USERID}"

openssl pkcs12 -export \
  -inkey ipsec.d/private/$USERNAME-key.pem \
  -in ipsec.d/certs/$USERNAME-cert.pem \
  -name "$USERNAME's VPN Certificate" \
  -certfile ipsec.d/cacerts/ca-cert.cer \
  -caname "$ORGANISATION Root CA" \
  -out ipsec.d/p12/$USERNAME.p12

echo ""
echo -e "\n${USERNAME}'s pkcs12 file is stored in ipsec.d/p12"

exit 0
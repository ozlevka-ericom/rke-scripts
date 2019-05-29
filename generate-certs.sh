#!/bin/bash

CURRENT_DIR=/home/ericom

# Root pair
mkdir $CURRENT_DIR/ca
cd ./ca
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial

cp $CURRENT_DIR/openssl.cnf  $CURRENT_DIR/ca/openssl.cnf
#wget -O /root/ca/openssl.cnf https://jamielinux.com/docs/openssl-certificate-authority/_downloads/root-config.txt

echo "##########"
echo "CREATE root key"
echo "##########"
openssl genrsa -aes256 -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem

echo "##########"
echo "CREATE root certificate"
echo "Fill in the Common Name!"
echo "##########"
openssl req -config openssl.cnf \
      -key private/ca.key.pem \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out certs/ca.cert.pem

chmod 444 certs/ca.cert.pem

# Intermediate
mkdir $CURRENT_DIR/ca/intermediate
cd $CURRENT_DIR/ca/intermediate
mkdir certs crl csr newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > $CURRENT_DIR/ca/intermediate/crlnumber

cp $CURRENT_DIR/intermediate.cnf $CURRENT_DIR/ca/intermediate/openssl.cnf
#wget -O /root/ca/intermediate/openssl.cnf https://jamielinux.com/docs/openssl-certificate-authority/_downloads/intermediate-config.txt
echo "##########"
echo "KEY intermediate"
echo "##########"
cd $CURRENT_DIR/ca
openssl genrsa -aes256 \
      -out intermediate/private/intermediate.key.pem 4096
chmod 400 intermediate/private/intermediate.key.pem

echo "##########"
echo "CSR intermediate"
echo "Fill in the Common Name!"
echo "##########"
openssl req -config intermediate/openssl.cnf -new -sha256 \
      -key intermediate/private/intermediate.key.pem \
      -out intermediate/csr/intermediate.csr.pem

echo "##########"
echo "SIGN intermediate"
echo "##########"
openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in intermediate/csr/intermediate.csr.pem \
      -out intermediate/certs/intermediate.cert.pem

chmod 444 intermediate/certs/intermediate.cert.pem

cat intermediate/certs/intermediate.cert.pem \
      certs/ca.cert.pem > intermediate/certs/ca-chain.cert.pem
chmod 444 intermediate/certs/ca-chain.cert.pem

echo "##########"
echo "KEY certificate"
echo "##########"
openssl genrsa -aes256 \
      -out intermediate/private/rancher.local.key.pem 2048
chmod 400 intermediate/private/rancher.local.key.pem

echo "##########"
echo "CSR certificate"
echo "Use rancher.local as Common Name"
echo "##########"
openssl req -config intermediate/openssl.cnf \
      -key intermediate/private/rancher.local.key.pem \
      -new -sha256 -out intermediate/csr/rancher.local.csr.pem

sleep 5

echo "##########"
echo "SIGN certificate"
echo "##########"
openssl ca -config intermediate/openssl.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in intermediate/csr/rancher.local.csr.pem \
      -out intermediate/certs/rancher.local.cert.pem
chmod 444 intermediate/certs/rancher.local.cert.pem

echo "##########"
echo "Create files to be used for Rancher"
echo "##########"
mkdir -p $CURRENT_DIR/ca/rancher/base64
cp $CURRENT_DIR/ca/certs/ca.cert.pem $CURRENT_DIR/ca/rancher/cacerts.pem
cat $CURRENT_DIR/ca/intermediate/certs/rancher.local.cert.pem $CURRENT_DIR/ca/intermediate/certs/intermediate.cert.pem > $CURRENT_DIR/ca/rancher/cert.pem
echo "##########"
echo "Removing passphrase from Rancher certificate key"
echo "##########"
openssl rsa -in $CURRENT_DIR/ca/intermediate/private/rancher.local.key.pem -out $CURRENT_DIR/ca/rancher/key.pem
cat $CURRENT_DIR/ca/rancher/cacerts.pem | base64 -w0 > $CURRENT_DIR/ca/rancher/base64/cacerts.base64
cat $CURRENT_DIR/ca/rancher/cert.pem | base64 -w0 > $CURRENT_DIR/ca/rancher/base64/cert.base64
cat $CURRENT_DIR/ca/rancher/key.pem | base64 -w0 > $CURRENT_DIR/ca/rancher/base64/key.base64

echo "##########"
echo "Verify certificates"
echo "##########"
openssl verify -CAfile certs/ca.cert.pem \
      intermediate/certs/intermediate.cert.pem
openssl verify -CAfile intermediate/certs/ca-chain.cert.pem \
      intermediate/certs/rancher.local.cert.pem
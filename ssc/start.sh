#/bin/bash

# Choose a secure password and store it safely
export HTTP_CERT_PWD="F)rt1fy!"

# Create a self-signed server cert + private key in a keystore
rm -rf ./certs
mkdir certs
keytool -genkeypair \
  -keyalg RSA -keysize 2048 \
  -keystore ./certs/sscKeystore.jks \
  -alias ssc-server \
  -storepass "$HTTP_CERT_PWD" \
  -keypass "$HTTP_CERT_PWD" \
  -dname "CN=ssc.local, OU=IT, O=YourOrg, L=City, ST=State, C=US"

echo -n "F)rt1fy!" > ./certs/sscKeystorePassword.txt
chmod 0644 ./certs/sscKeystorePassword.txt

docker compose --env-file ../.env up -d

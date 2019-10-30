#!/bin/bash
set -e

# Wait to settle
sleep 15

# Get our SSL domains from the Marathon app label
SSL_DOMAINS=$(curl -s ${MARATHON_URL}/v2/apps${MARATHON_APP_ID} | python -c 'import sys, json; print(json.load(sys.stdin)["app"]["labels"]["HAPROXY_0_VHOST"])')
if [ -z "$SSL_DOMAINS" ]; then
  exit 1
fi

IFS=',' read -ra ADDR <<< "$SSL_DOMAINS"
DOMAIN_ARGS=""
DOMAIN_FIRST=""
for i in "${ADDR[@]}"; do
  if [ -z $DOMAIN_FIRST ]; then
    DOMAIN_FIRST=$i
  fi
  DOMAIN_ARGS="$DOMAIN_ARGS -d $i"
done

echo "DOMAIN_ARGS: ${DOMAIN_ARGS}"
echo "DOMAIN_FIRST: ${DOMAIN_FIRST}"

echo "Running certbot to generate initial signed cert"
echo "Using server ${LETSENCRYPT_SERVER_URL}"

certbot certonly --server ${LETSENCRYPT_SERVER_URL} --standalone \
        --cert-name ${DOMAIN_FIRST} \
        --preferred-challenges http-01 $DOMAIN_ARGS \
        --email $LETSENCRYPT_EMAIL --agree-tos \
        --noninteractive --no-redirect \
        --rsa-key-size 4096 --expand

while [ true ]; do
  cat /etc/letsencrypt/live/$DOMAIN_FIRST/fullchain.pem \
    /etc/letsencrypt/live/$DOMAIN_FIRST/privkey.pem >   \
    /etc/letsencrypt/live/$DOMAIN_FIRST.pem

  echo "Posting new cert to marathon-lb"
  ./post_cert.py /etc/letsencrypt/live/$DOMAIN_FIRST.pem

  sleep 24h

  echo "About to attempt renewal"
  certbot renew
done

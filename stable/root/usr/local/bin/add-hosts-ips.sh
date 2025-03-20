#!/bin/bash
set -Eeuo pipefail

HOSTNAME="$1"
if [[ -z "$HOSTNAME" ]]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

IP_ADDRESSES=$(nslookup "$HOSTNAME" | awk '/^Address:/ {print $2}' | tail -n +2)

if [[ -z "$IP_ADDRESSES" ]]; then
    echo "Error: Unable to resolve $HOSTNAME"
    exit 1
fi

echo "Resolved $HOSTNAME to:"
echo "$IP_ADDRESSES"

HOSTS_CONTENT=$(sed "/\s$HOSTNAME$/d" /etc/hosts)
echo "$HOSTS_CONTENT" | tee /etc/hosts > /dev/null

for IP in $IP_ADDRESSES; do
    echo "$IP $HOSTNAME" | tee -a /etc/hosts
done

echo "Updated /etc/hosts with new IPs."

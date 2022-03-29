#!/bin/bash

#
# Pterodactyl Wings Daemon
#

while [ ! -f /etc/pterodactyl/config.yml ]; do
    echo "No configuration file found. Retrying in 5 seconds..."
    sleep 5
done

echo "Configuration found. Waiting for Docker..."

while [[ ! "$(curl https://docker:2376 -k 2> /dev/null)" ]]; do
    sleep 1
done

echo "Starting Wings..."

cd /etc/pterodactyl || exit
/usr/local/bin/wings
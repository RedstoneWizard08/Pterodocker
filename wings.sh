#!/bin/bash

#
# Pterodactyl Wings Daemon
#

while [ ! -f /etc/pterodactyl/config.yml ]; do
    echo "No configuration file found. Retrying in 5 seconds..."
    sleep 5
done

echo "Configuration found. Starting Docker daemon..."

service docker start

echo "Starting Wings..."

cd /etc/pterodactyl || exit
/usr/local/bin/wings
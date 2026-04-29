#!/bin/sh
mkdir -p /data/meta /data/data

# Ersätt miljövariabler i garage.toml innan Garage startas
envsubst < /etc/garage.toml > /tmp/garage.toml

nginx -c /etc/nginx/nginx.conf

exec garage -c /tmp/garage.toml "$@"

#!/usr/bin/with-contenv bashio

ipv6=($(bashio::network.ipv6_address))

echo ${ipv6[1]} #| head -n 2 | tail -n 1

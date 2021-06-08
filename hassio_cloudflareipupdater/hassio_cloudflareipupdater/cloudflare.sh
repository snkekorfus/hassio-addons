#!/usr/bin/with-contenv bashio

ipv6 = $(bashio::network.ipv6_address)

echo $ipv6[1]

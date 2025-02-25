#!/usr/bin/with-contenv bashio

CONFIG_PATH=/data/options.json

ZONE=$(jq --raw-output ".zone" $CONFIG_PATH)
HOST=$(jq --raw-output ".host" $CONFIG_PATH)
EMAIL=$(jq --raw-output ".email" $CONFIG_PATH)
API=$(jq --raw-output ".api" $CONFIG_PATH)

error=""
# Enforces required env variables
required_vars=(ZONE HOST EMAIL API)
for required_var in "${required_vars[@]}"; do
    if [[ -z ${!required_var} ]]; then
        error=1
        echo >&2 "Error: $required_var env variable not set."
    fi
done

if [[ -n $error ]]; then
    exit 1
fi

# PROXY defaults to true
PROXY=${PROXY:-true}

# TTL defaults to 1 (automatic), and is validated
TTL=${TTL:-1}
if [[ $TTL != 1 ]] && [[ $TTL -lt 120 || $TTL -gt 2147483647 ]]; then
    echo >&2 "Error: Invalid TTL value $TTL; must be either 1 (automatic) or between 120 and 2147483647 inclusive."
    exit 1
fi


while true  
do

echo "Current time: $(date "+%Y-%m-%d %H:%M:%S")"
ipv6=($(bashio::network.ipv6_address))
new_ip=${ipv6[1]::-4}
record_type="AAAA"

if [[ -z $new_ip ]]; then
    echo >&2 "Error: Something went wrong."
    exit 1
fi

# Compares with last IP address set, if any
ip_file="/data/ip.dat"
if [[ -f $ip_file ]]; then
    ip=$(<$ip_file)
    if [[ $ip = "$new_ip" ]]; then
        echo "IP is unchanged : $ip. Exiting."
        exit 0
    fi
fi

ip="$new_ip"
echo "IP: $ip"

# Fetches the zone information for the account
zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE" \
        -H "X-Auth-Email: $EMAIL" \
        -H "X-Auth-Key: $API" \
        -H "Content-Type: application/json")


# If not successful, errors out
if [[ $(jq <<<"$zone_response" -r '.success') != "true" ]]; then
    messages=$(jq <<<"$zone_response" -r '[.errors[] | .message] |join(" - ")')
    echo >&2 "Error: $messages"
    exit 1
fi

# Selects the zone id
zone_id=$(jq <<<"$zone_response" -r ".result[0].id")


# If no zone id was found for the account, errors out.
if [[ -z $zone_id ]]; then
    echo >&2 "Error: Could not determine Zone ID for $ZONE"
    exit 1
fi

echo "Zone $ZONE id : $zone_id"

# Tries to fetch the record of the host
dns_record_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?name=$HOST.$ZONE" \
        -H "X-Auth-Email: $EMAIL" \
        -H "X-Auth-Key: $API" \
        -H "Content-Type: application/json")


if [[ $(bashio::jq "$dns_record_response" ".success") = "true" ]]; then
    current_ip=$(bashio::jq "$dns_record_response" ".result[] | select(.name==\"$HOST.$ZONE\") | .content")
    dns_record_id=$(bashio::jq "$dns_record_response" ".result[] | select(.name==\"$HOST.$ZONE\") | .id")
    echo "DNS IP: $current_ip"
    if [[ $current_ip = $ip ]]; then
        echo "Current ip up-to-date. Not updating!"
    else
        echo "Current ip outdated. Updating!"
        # DNS record to add or update
        new_dns_record='{
"type":"'"$record_type"'",
"name": "'"$HOST"'",
"content": "'"$ip"'",
"ttl": '"$TTL"',
"priority": 10,
"proxied": '"$PROXY"'
}'

        dns_record_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$dns_record_id" \
            -H "X-Auth-Email: $EMAIL" \
            -H "X-Auth-Key: $API" \
            -H "Content-type: application/json" \
            --data "$new_dns_record")
        
        if [[ $(bashio::jq "$dns_record_response" ".success") = "true" ]]; then
            echo "IP was successfully updated to $ip"
        else
            echo $(bashio::jq "$dns_record_response")
        fi
    fi 
else
    echo "An error occured during the cloudflare API call"
fi


sleep 300 
done

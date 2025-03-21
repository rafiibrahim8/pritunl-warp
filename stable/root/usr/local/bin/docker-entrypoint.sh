#!/usr/bin/env bash

# Init script for Pritunl Docker container with Cloudflare Warp
# License: Apache-2.0
# Original Github: https://github.com/goofball222/pritunl.git
# Warp Version: https://github.com/rafiibrahim8/pritunl-warp.git
# Last updated date: 2025-03-21

SCRIPT_VERSION="1.0.3"

set -Eeuo pipefail

if [ "${DEBUG}" == 'true' ]; then
    set -x
fi

log() {
    echo "$(date -u +%FT) <docker-entrypoint> $*"
}

log "INFO - Script version ${SCRIPT_VERSION}"

PRITUNL=/usr/local/bin/pritunl

PRITUNL_OPTS="${PRITUNL_OPTS}"

pritunl_setup() {
    log "INFO - Insuring pritunl setup for container"

    ${PRITUNL} set-mongodb ${MONGODB_URI:-"mongodb://mongo:27017/pritunl"}

    ${PRITUNL} set app.web_systemd false

    if [ "${KEEP_OPENVPN_PERMISSION}" == 'true' ]; then
        ${PRITUNL} set vpn.drop_permissions false
    else
        ${PRITUNL} set vpn.drop_permissions true
    fi

    if [ "${REVERSE_PROXY}" == 'true' ] && [ "${WIREGUARD}" == 'false' ]; then
            ${PRITUNL} set app.reverse_proxy true
            ${PRITUNL} set app.redirect_server false
            ${PRITUNL} set app.server_ssl false
            ${PRITUNL} set app.server_port 9700
    elif [ "${REVERSE_PROXY}" == 'true' ] && [ "${WIREGUARD}" == 'true' ]; then
            ${PRITUNL} set app.reverse_proxy true
            ${PRITUNL} set app.redirect_server false
            ${PRITUNL} set app.server_ssl true
            ${PRITUNL} set app.server_port 443
    else
        ${PRITUNL} set app.reverse_proxy false
        ${PRITUNL} set app.redirect_server true
        ${PRITUNL} set app.server_ssl true
        ${PRITUNL} set app.server_port 443
    fi

    PRITUNL_OPTS="start ${PRITUNL_OPTS}"
}

exit_handler() {
    log "INFO - Exit signal received, commencing shutdown"
    pkill -15 -f ${PRITUNL}
    for i in `seq 0 20`;
        do
            [ -z "$(pgrep -f ${PRITUNL})" ] && break
            # kill it with fire if it hasn't stopped itself after 20 seconds
            [ $i -gt 19 ] && pkill -9 -f ${PRITUNL} || true
            sleep 1
    done
    log "INFO - Shutdown complete. Nothing more to see here. Have a nice day!"
    log "INFO - Exit with status code ${?}"
    exit ${?};
}

# Wait indefinitely on tail until killed
idle_handler() {
    while true
    do
        tail -f /dev/null & wait ${!}
    done
}

start_warp(){
    add-hosts-ips.sh "$(echo "$MONGODB_URI" | awk -F'[/:]' '{print $4}')"
    mkdir -p /run/dbus
    if [ -f /run/dbus/pid ]; then
        rm -f /run/dbus/pid
    fi
    dbus-daemon --config-file=/usr/share/dbus-1/system.conf
    warp-svc --accept-tos &
    # sleep to wait for the daemon to start, default 3 seconds
    sleep "$WARP_DAEMON_STARTUP_WAIT"
    if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
        if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "$REGISTER_WHEN_MDM_EXISTS" ]; then
            warp-cli --accept-tos registration new && log "Warp client registered!"
            if [ -n "$WARP_LICENSE_KEY" ]; then
                log "License key found, registering license..."
                warp-cli --accept-tos registration license "$WARP_LICENSE_KEY" && log "Warp license registered!"
            fi
        fi
    else
        log "Warp client already registered, skip registration"
    fi
    warp-cli --accept-tos connect
    sleep "$WARP_DAEMON_STARTUP_WAIT"

    log "[NAT] Enabling NAT..."
    nft add table ip nat
    nft add chain ip nat WARP_NAT { type nat hook postrouting priority -145 \; }
    nft add rule ip nat WARP_NAT oifname "CloudflareWARP" masquerade
    nft add table ip mangle
    nft add chain ip mangle forward { type filter hook forward priority mangle \; }
    nft add rule ip mangle forward tcp flags syn tcp option maxseg size set rt mtu

    nft add table ip6 nat
    nft add chain ip6 nat WARP_NAT { type nat hook postrouting priority -145 \; }
    nft add rule ip6 nat WARP_NAT oifname "CloudflareWARP" masquerade
    nft add table ip6 mangle
    nft add chain ip6 mangle forward { type filter hook forward priority mangle \; }
    nft add rule ip6 mangle forward tcp flags syn tcp option maxseg size set rt mtu
}

trap 'kill ${!}; exit_handler' SIGHUP SIGINT SIGQUIT SIGTERM

if [[ "${@}" == 'pritunl' ]];
    then
        pritunl_setup

        log "EXEC - ${PRITUNL} ${PRITUNL_OPTS}"
        exec 0<&-
        exec ${PRITUNL} ${PRITUNL_OPTS} &
        if [[ -n "$ENABLE_WARP" && "${ENABLE_WARP,,}" =~ ^(1|yes|true|on)$ ]]; then
            log "WARP is enabled!"
            log "Sleeping $BEFORE_WARP_INIT_WAIT secs..."
            sleep "$BEFORE_WARP_INIT_WAIT"
            start_warp
        fi
        log 'Calling idle_handler.....'
        idle_handler
    else
        log "EXEC - ${@}"
        exec "${@}"
fi

# Script should never make it here, but just in case exit with a generic error code if it does
exit 1;

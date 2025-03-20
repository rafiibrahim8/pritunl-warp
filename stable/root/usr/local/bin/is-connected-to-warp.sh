#!/bin/bash
if [[ -n "$ENABLE_WARP" && "${ENABLE_WARP,,}" =~ ^(1|yes|true|on)$ ]]; then
    curl -fsS "https://cloudflare.com/cdn-cgi/trace" | grep -qE "warp=(plus|on)"
fi



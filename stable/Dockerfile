FROM golang:1.23-bookworm AS gobuiler
ENV \
    GOPATH="/go" \
    GOCACHE="/tmp/gocache" \
    GO111MODULE=on

RUN set -x \
    && go install github.com/pritunl/pritunl-dns@latest \
    && go install github.com/pritunl/pritunl-web@latest

FROM python:3.11-slim-bookworm
WORKDIR /opt/pritunl

ARG VERSION
RUN set -x \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash curl ca-certificates ipset iptables openssl openvpn procps python3-setuptools \
        tzdata wireguard-tools psmisc iproute2 net-tools gnupg \
        dbus iputils-ping dnsutils \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gcc lsb-release python3-dev \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cloudflare-warp \
    && rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED \
    && cd /tmp \
    && curl -sSL https://github.com/pritunl/pritunl/archive/refs/tags/${VERSION}.tar.gz -o /tmp/${VERSION}.tar.gz \
    && tar -zxf /tmp/${VERSION}.tar.gz \
    && cd /tmp/pritunl-${VERSION} \
    && python3 setup.py build \
    && pip3 install --no-cache-dir -U -r requirements.txt \
    && mkdir -p /var/lib/pritunl \
    && python3 setup.py install \
    && DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y \
        gcc lsb-release python3-dev \
    && apt-get autoremove --purge -y \
    && apt-get clean \
    && rm -rf /root/.cache/* /tmp/* /var/lib/apt/lists/*

COPY root /
COPY --from=gobuiler /go/bin/ /usr/bin/

HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD is-connected-to-warp.sh

EXPOSE 80/tcp 443/tcp 1194/tcp 1194/udp 1195/udp 9700/tcp

ARG BUILD_DATE
ARG VCS_REF

LABEL \
    org.opencontainers.image.vendor="Ibrahim Rafi - rafiibrahim8@hotmail.com" \
    org.opencontainers.image.url="https://github.com/rafiibrahim8/pritunl-warp" \
    org.opencontainers.image.title="Pritunl Server with Cloudflare Warp" \
    org.opencontainers.image.description="Pritunl Server with Cloudflare Warp" \
    org.opencontainers.image.version=$VERSION \
    org.opencontainers.image.source="https://github.com/rafiibrahim8/pritunl-warp" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE \
    org.opencontainers.image.licenses="Apache-2.0"

ENV \
    DEBUG=false \
    PRITUNL_OPTS= \
    REVERSE_PROXY=false \
    WIREGUARD=false \
    KEEP_OPENVPN_PERMISSION=false

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["pritunl"]

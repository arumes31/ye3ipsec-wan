# Stage 1: Build strongSwan
FROM alpine:latest AS builder

# Build arguments for strongSwan version and patches
ARG Y_STRONGSWAN_VERSION=6.0.6
ARG Y_PATCH=yes

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    gmp-dev \
    openssl-dev \
    linux-pam-dev \
    iptables-dev \
    xz \
    zstd \
    curl-dev \
    ca-certificates \
    wget \
    tar \
    bz2

# Prepare source
WORKDIR /usr/local/src
RUN wget https://download.strongswan.org/strongswan-${Y_STRONGSWAN_VERSION}.tar.bz2 && \
    tar xjvf strongswan-${Y_STRONGSWAN_VERSION}.tar.bz2

# Apply patches if needed
COPY ye3ipsec_patch/ /ye3ipsec_patch/
WORKDIR /usr/local/src/strongswan-${Y_STRONGSWAN_VERSION}
RUN if [ "$Y_PATCH" = "yes" ]; then \
        cp -r /ye3ipsec_patch . && \
        [ -f ye3ipsec_patch/before_build/all/patch.sh ] && chmod +x ye3ipsec_patch/before_build/all/patch.sh && ye3ipsec_patch/before_build/all/patch.sh; \
        [ -f ye3ipsec_patch/before_build/${Y_STRONGSWAN_VERSION}/patch.sh ] && chmod +x ye3ipsec_patch/before_build/${Y_STRONGSWAN_VERSION}/patch.sh && ye3ipsec_patch/before_build/${Y_STRONGSWAN_VERSION}/patch.sh; \
    fi

# Configure and build
RUN ./configure --prefix= \
    --enable-eap-identity \
    --enable-eap-dynamic \
    --enable-eap-mschapv2 \
    --enable-md4 \
    --enable-eap-md5 \
    --enable-eap-tls \
    --enable-eap-ttls \
    --enable-eap-tnc \
    --enable-eap-gtc \
    --enable-xauth-eap \
    --enable-xauth-noauth \
    --enable-xauth-pam \
    --enable-eap-peap \
    --enable-eap-sim \
    --enable-eap-radius \
    --enable-openssl \
    --enable-vici \
    --enable-swanctl \
    --enable-charon \
    --enable-stroke \
    --enable-dhcp \
    --enable-forecast \
    --enable-farp \
    --enable-bypass-lan \
    --enable-curl && \
    NB_CORES=$(grep -c '^processor' /proc/cpuinfo) && \
    make -j$((NB_CORES+1)) -l${NB_CORES} && \
    make install DESTDIR=/tmp/strongswan

# Apply post-build patches
RUN if [ "$Y_PATCH" = "yes" ]; then \
        [ -f ye3ipsec_patch/after_build/all/patch.sh ] && chmod +x ye3ipsec_patch/after_build/all/patch.sh && ye3ipsec_patch/after_build/all/patch.sh; \
        [ -f ye3ipsec_patch/after_build/${Y_STRONGSWAN_VERSION}/patch.sh ] && chmod +x ye3ipsec_patch/after_build/${Y_STRONGSWAN_VERSION}/patch.sh && ye3ipsec_patch/after_build/${Y_STRONGSWAN_VERSION}/patch.sh; \
    fi

# Stage 2: Final Production Image
FROM alpine:latest

LABEL org.opencontainers.image.title="ye3ipsec-wan"
LABEL org.opencontainers.image.version="1.1.7"
LABEL org.opencontainers.image.description="IPSec client and server based on Strongswan and Alpine. Multi-stage build."
LABEL org.opencontainers.image.authors="arumes31"

# Runtime Environment Variables
ENV Y_LANGUAGE=fr_FR \
    Y_DEBUG=no \
    Y_IGNORE_CONFIG=no \
    Y_EXTRA_PACKAGE="net-tools traceroute tcpdump ipcalc nano nftables" \
    Y_URL_IP_CHECK=http://whatismyip.akamai.com \
    Y_URL_IP_CHECK_TIMEOUT=5 \
    Y_PATCH=yes \
    Y_SHOW_CRED=yes \
    TZ=Europe/Paris \
    Y_DATE_FORMAT="%Y-%m-%dT%H:%M:%S%z" \
    Y_PROTO_ESP=esp \
    Y_PROTO_AH=ah \
    Y_PORT_IKE=500 \
    Y_PORT_NAT=4500 \
    Y_SERVER_CERT_DN="C=FR, ST=Ile-de-France, L=Paris, O=IPSec, OU=Example" \
    Y_SERVER_CERT_DAYS=3650 \
    Y_PROPOSALS_PHASE1="aes256gcm16-prfsha384-ecp384, aes256-sha384-ecp384, aes256-sha256-ecp256, aes256-sha256-modp2048" \
    Y_PROPOSALS_PHASE2="aes256gcm16-ecp384, aes256-sha384, aes256-sha256" \
    Y_REKEY_PHASE1=86400s \
    Y_REKEY_PHASE2=28800s \
    Y_DPD_DELAY=15s \
    Y_DPD_ACTION=restart \
    Y_LOCAL_SELFCERT=yes \
    Y_LOCAL_SUBNET="0.0.0.0/0, ::/0" \
    Y_REMOTE_SUBNET=dynamic \
    Y_POOL_DHCP=no \
    Y_POOL_IPV6_ENABLE=yes \
    Y_POOL_IPV4=192.168.1.1/24 \
    Y_POOL_IPV6=fd00::c0a8:101/120 \
    Y_POOL_DNS4="1.1.1.1, 8.8.8.8" \
    Y_POOL_DNS6="2606:4700:4700::1111, 2001:4860:4860::8888" \
    Y_FIREWALL_ENABLE=no \
    Y_FIREWALL_IPSEC_PORT=yes \
    Y_FIREWALL_NAT=yes \
    Y_FIREWALL_S2S_NAT=no \
    Y_FIREWALL_MANGLE=yes \
    Y_FIREWALL_REVOCATION=yes \
    Y_FIREWALL_REVOCATION_PORT=80,8080 \
    Y_FIREWALL_INTERCLIENT=yes \
    Y_FIREWALL_LAN=yes \
    Y_FIREWALL_INTERNET=yes \
    Y_FIREWALL_COMMENT_PREFIX=ye3ipsec-wan \
    Y_CERT_ENABLE=yes \
    Y_EAP_ENABLE=yes \
    Y_PSK_ENABLE=yes \
    Y_REVOCATION_LOAD=yes \
    Y_FARP_LOAD=yes \
    Y_FORECAST_LOAD=yes \
    Y_BYPASSLAN_LOAD=no \
    Y_FILELOG_DEFAULT=1 \
    Y_FILELOG_PATH=/var/log/charon.log \
    Y_FILELOG_APPEND=yes

# Install runtime packages and copy strongSwan from builder
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    tini \
    tzdata \
    gmp \
    openssl \
    linux-pam \
    ip6tables \
    iptables \
    nftables \
    kmod \
    curl \
    openresolv \
    ca-certificates \
    $Y_EXTRA_PACKAGE

COPY --from=builder /tmp/strongswan /

# Add project files
ADD entrypoint.sh /
ADD i18n/ /i18n/
ADD swanctl/ /etc/swanctl/

# Setup permissions and links
RUN chmod +x /entrypoint.sh && \
    ln -sfn /etc/swanctl/ye3ipsec-wan/bypass_container_env.sh /etc/profile.d/bypass_container_env.sh

VOLUME "/etc/swanctl"
EXPOSE 500/udp 4500/udp

# Healthcheck for service status
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD swanctl --stats || exit 1

ENTRYPOINT ["/sbin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]

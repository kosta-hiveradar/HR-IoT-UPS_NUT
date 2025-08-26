# Smart NUT 2.8.4 with intelligent USB hotplug for Raspberry Pi ARM64
FROM debian:bookworm-slim AS builder

# Build arguments for cross-compilation
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

ENV NUT_VERSION=2.8.4

# Install build dependencies including libltdl for nut-scanner
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libusb-1.0-0-dev \
    wget \
    ca-certificates \
    autoconf \
    automake \
    libtool \
    libltdl-dev \
    libltdl7 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Download and build NUT 2.8.4 with full feature set
WORKDIR /tmp
RUN wget https://github.com/networkupstools/nut/releases/download/v${NUT_VERSION}/nut-${NUT_VERSION}.tar.gz && \
    tar xfz nut-${NUT_VERSION}.tar.gz && \
    cd nut-${NUT_VERSION} && \
    # Configure NUT with all required features
    ./configure \
        --prefix=/opt/nut \
        --sysconfdir=/opt/nut/etc \
        --with-user=nut \
        --with-group=nut \
        --with-usb=yes \
        --with-nut-scanner=yes \
        --with-nutclient=yes \
        --with-dev \
        --enable-strip \
        --disable-static \
        --without-cgi \
        --without-snmp \
        --without-neon \
        --without-ssl \
        --datadir=/opt/nut/share \
        --with-drvpath=/opt/nut/lib/nut \
        --with-statepath=/var/run/nut && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/install && \
    rm -rf /tmp/nut-${NUT_VERSION} /tmp/nut-${NUT_VERSION}.tar.gz

# Runtime image with smart hotplug support
FROM debian:bookworm-slim

ARG TARGETARCH

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libusb-1.0-0 \
    usbutils \
    libltdl7 \
    procps \
    bash && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create nut user with proper USB permissions
RUN groupadd -r nut && \
    useradd -r -g nut -d /var/run/nut -s /sbin/nologin nut && \
    usermod -a -G plugdev,dialout nut

# Copy complete NUT installation from builder
COPY --from=builder /tmp/install/opt/nut /opt/nut

# Create necessary directories with proper permissions
RUN mkdir -p \
    /var/run/nut \
    /var/log/nut \
    /opt/nut/etc \
    /var/state/ups && \
    chown -R nut:nut \
    /var/run/nut \
    /var/log/nut \
    /opt/nut/etc \
    /var/state/ups && \
    chmod 750 /var/run/nut /opt/nut/etc

# Copy standard configuration files
COPY standard_configs/ /opt/nut/etc/

# Copy smart hotplug entrypoint script
COPY docker-hotplug/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set proper ownership for config files
RUN chown -R nut:nut /opt/nut/etc/

# Set library path for NUT binaries
ENV LD_LIBRARY_PATH=/opt/nut/lib
ENV PATH="/opt/nut/bin:/opt/nut/sbin:${PATH}"

# Expose NUT server port
EXPOSE 3493

# Health check using UPS detection
HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=3 \
    CMD /opt/nut/bin/upsc -l > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
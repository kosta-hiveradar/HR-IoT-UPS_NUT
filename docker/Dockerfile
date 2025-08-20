# Multi-arch NUT 2.8.4 build for Raspberry Pi ARM64 from x86_64 host
FROM --platform=$TARGETPLATFORM debian:bullseye-slim AS builder

# Build arguments for cross-compilation
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

ENV NUT_VERSION=2.8.4

# Install build dependencies (native compilation for target arch)
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libusb-1.0-0-dev \
    wget \
    ca-certificates \
    autoconf \
    automake \
    libtool \
    && rm -rf /var/lib/apt/lists/*

# Download and build NUT 2.8.4 with cross-compilation
WORKDIR /tmp
RUN wget https://github.com/networkupstools/nut/releases/download/v${NUT_VERSION}/nut-${NUT_VERSION}.tar.gz && \
    tar xfz nut-${NUT_VERSION}.tar.gz && \
    cd nut-${NUT_VERSION} && \
    # Configure NUT 2.8.4 for native compilation
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

# Runtime image for target platform
FROM --platform=$TARGETPLATFORM debian:bullseye-slim

ARG TARGETARCH

# Install runtime dependencies for target architecture
RUN apt-get update && apt-get install -y --no-install-recommends \
    libusb-1.0-0 \
    usbutils \
    && rm -rf /var/lib/apt/lists/*

# Create nut user with proper USB permissions for Raspberry Pi
RUN groupadd -r nut && \
    useradd -r -g nut -d /var/run/nut -s /sbin/nologin nut && \
    usermod -a -G plugdev,dialout nut

# Copy NUT binaries from builder (cross-compiled for ARM64)
COPY --from=builder /tmp/install/opt/nut/bin/upsc /opt/nut/bin/
COPY --from=builder /tmp/install/opt/nut/bin/nut-scanner /opt/nut/bin/
COPY --from=builder /tmp/install/opt/nut/sbin/upsd /opt/nut/sbin/
COPY --from=builder /tmp/install/opt/nut/sbin/upsmon /opt/nut/sbin/
COPY --from=builder /tmp/install/opt/nut/sbin/upsdrvctl /opt/nut/sbin/
COPY --from=builder /tmp/install/opt/nut/lib/ /opt/nut/lib/
COPY --from=builder /tmp/install/opt/nut/share/nut/ /opt/nut/share/nut/

# Create necessary directories with proper permissions
RUN mkdir -p /var/run/nut /opt/nut/etc /var/state/ups && \
    chown -R nut:nut /var/run/nut /opt/nut/etc /var/state/ups && \
    chmod 750 /var/run/nut /opt/nut/etc

# Copy entrypoint optimized for IoT/RPi
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Configuration optimized for auto-detection and 2.8.4 features
RUN echo "MODE=standalone" > /opt/nut/etc/nut.conf && \
    echo "[auto-ups]" > /opt/nut/etc/ups.conf && \
    echo "    driver = usbhid-ups" >> /opt/nut/etc/ups.conf && \
    echo "    port = auto" >> /opt/nut/etc/ups.conf && \
    echo "    desc = \"Auto-detected USB UPS\"" >> /opt/nut/etc/ups.conf && \
    echo "    # NUT 2.8.4 timeout improvements" >> /opt/nut/etc/ups.conf && \
    echo "    interrupt_pipe_no_events_tolerance = 5" >> /opt/nut/etc/ups.conf && \
    chown nut:nut /opt/nut/etc/*.conf

# Set library path for cross-compiled binaries
ENV LD_LIBRARY_PATH=/opt/nut/lib
ENV PATH="/opt/nut/bin:/opt/nut/sbin:${PATH}"

# Expose NUT server port for IoT dashboard
EXPOSE 3493

ENTRYPOINT ["/entrypoint.sh"]


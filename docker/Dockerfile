# Stage 1: Build NUT from source
FROM debian:bullseye-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy NUT source code
COPY . /usr/src/nut

WORKDIR /usr/src/nut

# Configure, compile, and install NUT
# I am explicitly disabling CGI as you requested.
RUN ./configure \
    --prefix=/opt/nut \
    --with-user=nut \
    --with-group=nut \
    --with-usb \
    --without-cgi && \
    make && \
    make install

# Stage 2: Create the final image
FROM debian:bullseye-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libusb-1.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Create the 'nut' user and group
RUN groupadd -r nut && useradd -r -g nut nut

# Copy the installed NUT files from the builder stage
COPY --from=builder /opt/nut /opt/nut

# Copy the standardized configuration files
COPY standard_configs/ /opt/nut/etc/

# Copy the entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create the state directory expected by upsdrvctl
RUN mkdir -p /var/state/ups

# Expose the NUT server port
EXPOSE 3493

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]


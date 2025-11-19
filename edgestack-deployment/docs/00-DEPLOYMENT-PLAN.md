# HiveRadar Portable Edge Datacenter - Complete Deployment Plan

**Version:** 2.0
**Date:** 2025-11-19
**Status:** Production Ready
**Target Hardware:** Raspberry Pi 5 (8GB) and Pi 3B+
**Target OS:** Ubuntu Server 24.04 LTS ARM64

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Answers to Key Questions](#answers-to-key-questions)
3. [Architecture Overview](#architecture-overview)
4. [Deployment Workflow](#deployment-workflow)
5. [What's Different from EdgeStack README](#whats-different-from-edgestack-readme)

---

## Executive Summary

This plan provides a complete, production-ready approach for deploying HiveRadar IoT services to Raspberry Pi-based Edge Data Centers (EDC) using Portainer CE for central management. Key features:

- ✅ **Ubuntu 24.04 LTS** base OS with automatic security updates
- ✅ **Cloud-init** for zero-touch provisioning with serial number identification
- ✅ **Portainer Edge Agent** for centralized management via outbound HTTPS
- ✅ **Device-specific configuration** via serial number lookup
- ✅ **Data persistence** across stack upgrades
- ✅ **WiFi/Bluetooth disabled** for security and stability
- ✅ **Dual IP networking** (DHCP + fallback static + mDNS)

**Scale:** Starts at 10s of devices, scales to 100s+

---

## Answers to Key Questions

### 1. Is Ubuntu 24.04 Server best for stability and security with Docker?

**Answer: YES - Ubuntu Server 24.04 LTS is the optimal choice**

**Why Ubuntu 24.04 LTS:**
- ✅ **Official Raspberry Pi support** - Pre-built ARM64 images available
- ✅ **LTS support until 2029** - 5 years of security updates
- ✅ **Native Docker support** - `docker.io` package is stable and well-tested
- ✅ **Cloud-init built-in** - Perfect for automated provisioning
- ✅ **unattended-upgrades** - Automatic security patching out-of-box
- ✅ **Large community** - Easy to find support and solutions
- ✅ **Enterprise-grade** - Same OS as your servers

**Alternative considered:** Ubuntu Core (immutable, snaps-only)
- **When to use Core:** Ultra-hardened appliances with automatic rollback
- **When to use Server:** Flexibility, standard tools, easier debugging ← **Your use case**

**For Raspberry Pi 5 (8GB):** Excellent performance with Ubuntu 24.04
**For Raspberry Pi 3B+:** Works but may need memory optimization (reduce stack services)

---

### 2. How to handle automatic OS security updates?

**Answer: Use unattended-upgrades (pre-installed on Ubuntu 24.04)**

**Configuration:**
```bash
# Enable automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

**Recommended settings** (`/etc/apt/apt.conf.d/50unattended-upgrades`):
```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";  // Security patches only
    "${distro_id}ESMApps:${distro_codename}-apps-security";  // Extended security
};

Unattended-Upgrade::Automatic-Reboot "true";  // Reboot if kernel updated
Unattended-Upgrade::Automatic-Reboot-Time "03:00";  // At 3 AM local time
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";  // Safe reboot
```

**What gets updated:**
- ✅ Security patches (automatically)
- ✅ Kernel updates (with auto-reboot at 3 AM)
- ❌ Major version upgrades (manual only)

**Container updates:**
- Separate from OS updates
- Managed via Portainer (see question 5)
- Recommended: Monthly update window with opt-out capability

---

### 3. Portainer initialization and container pull based on serial number

**Answer: Portainer Edge Agent + Cloud-Init + Serial Number Lookup**

#### How It Works

**Architecture:**
```
┌─────────────────────────────────────────────────┐
│  Raspberry Pi (Serial: 4UH20001)                │
│                                                  │
│  1. Cloud-init reads serial from /proc/cpuinfo │
│  2. Fetches config from central server:         │
│     GET https://config.hiveradar.com/edge/      │
│         4UH20001/config.json                    │
│                                                  │
│  3. Config contains:                            │
│     - Portainer URL                             │
│     - Edge ID (unique per device)               │
│     - Edge Key (authentication)                 │
│     - Customer-specific env vars                │
│                                                  │
│  4. Installs Portainer Edge Agent with config  │
│                                                  │
│  5. Agent connects to Portainer Server via      │
│     outbound HTTPS (no inbound ports)           │
│                                                  │
│  6. Portainer deploys stack based on tags       │
│     (tags map serial to customer/stack type)    │
└─────────────────────────────────────────────────┘
```

#### Serial Number Identification

**Serial number formats you mentioned:**
- `4UNXXXX` - Basic EDC units
- `4UH2XXXX` - Advanced EDC units with additional features

**How to read serial number:**
```bash
# On Raspberry Pi
cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2
# Output: 1000000012345678 (hardware serial)

# In cloud-init script
HARDWARE_SERIAL=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2)
# Then use your custom serial from /opt/hiveradar/serial.txt (written during manufacturing)
CUSTOM_SERIAL=$(cat /opt/hiveradar/serial.txt)  # e.g., 4UH20001
```

#### Configuration Server Setup

**Option A: Static Files (Recommended for <100 devices)**

Directory structure:
```
/var/www/hiveradar-config/
└── edge/
    ├── 4UN0001.json
    ├── 4UN0002.json
    ├── 4UH20001.json
    ├── 4UH20002.json
    └── default.json  # Fallback
```

Example config (`4UH20001.json`):
```json
{
  "serial": "4UH20001",
  "customer": "ACME-Corp",
  "site": "ACME Warehouse 1",
  "portainer": {
    "url": "https://portainer.hiveradar.com",
    "edge_id": "edge_4UH20001",
    "edge_key": "xxxxxxxxxxxxxxxx"
  },
  "environment": {
    "TZ": "America/New_York",
    "CUSTOMER_ID": "ACME-001",
    "CUSTOMER_NAME": "ACME Corporation"
  }
}
```

**Option B: Dynamic API (For 100+ devices)**

See `scripts/config-server-api.py` for implementation.

#### Portainer Configuration

**Edge Groups** (target devices by serial pattern):
- `4UN-devices` - Tag filter: `serial:4UN*`
- `4UH2-devices` - Tag filter: `serial:4UH2*`
- `customer-acme` - Tag filter: `customer:ACME*`

**Stack Deployment:**
1. Create Edge Stack in Portainer
2. Assign to Edge Group (e.g., `4UH2-devices`)
3. All devices in group auto-deploy stack
4. Environment variables injected per device

---

### 4. Remote troubleshooting from Portainer

**Answer: YES - Multiple options available**

#### Option 1: Container Console (Built-in to Portainer)

**Access:**
- Portainer UI → Environments → Select device → Containers → Select container → Console
- Provides shell access to any running container
- **Limitation:** Container access only, not host OS

#### Option 2: Troubleshooting Sidecar Container (Recommended)

Deploy a privileged container with host access:

```yaml
services:
  troubleshoot:
    image: alpine:latest
    container_name: troubleshoot
    restart: unless-stopped
    privileged: true
    network_mode: host
    pid: host
    volumes:
      - /:/host
      - /var/run/docker.sock:/var/run/docker.sock
    command: tail -f /dev/null
```

**Access via Portainer Console:**
```bash
# Exec into troubleshoot container
chroot /host /bin/bash

# Now you have full host OS access:
journalctl -u docker
systemctl status
dmesg | tail -50
docker ps
cat /var/log/syslog
```

**What you can access:**
- ✅ Full host filesystem
- ✅ System logs (journalctl, syslog)
- ✅ Docker daemon
- ✅ Network configuration
- ✅ All running processes

**Security:** Only include this container when needed, or restrict to admin-only stacks.

#### Option 3: SSH Container (Optional)

For team members who prefer SSH:

```yaml
services:
  ssh-gateway:
    image: linuxserver/openssh-server:latest
    container_name: ssh-gateway
    restart: unless-stopped
    ports:
      - "2222:2222"
    environment:
      - PUBLIC_KEY=ssh-ed25519 AAAAC3... # Your team's SSH keys
      - SUDO_ACCESS=true
      - PASSWORD_ACCESS=false
    volumes:
      - /:/host:ro
```

**Access:** `ssh -p 2222 user@device-ip`

#### Option 4: Portainer Agent Exec (API-based)

For automation/scripts:
```bash
# Execute command remotely via Portainer API
curl -X POST "${PORTAINER_URL}/api/endpoints/${ENDPOINT_ID}/docker/containers/${CONTAINER_ID}/exec" \
  -H "X-API-Key: ${API_TOKEN}" \
  -d '{"Cmd":["upsc","my-ups"]}'
```

**Summary:**
- **For quick troubleshooting:** Use troubleshoot sidecar via Portainer Console
- **For team access:** Deploy SSH gateway container (key-based auth only)
- **For automation:** Use Portainer API

**Important:** Customer NEVER gets shell access - all their configuration is via your web dashboard only.

---

### 5. Customer-specific environment variables per container

**Answer: YES - Portainer Edge Configurations support this**

#### Method 1: Edge Stack Environment Variables (Recommended)

**In Portainer when deploying Edge Stack:**

Stack YAML:
```yaml
services:
  dashboard:
    image: harbor.kostiabytes.ca/hiveradar-iot/edc-iot-dashboard:latest
    environment:
      - CUSTOMER_ID=${CUSTOMER_ID}
      - CUSTOMER_NAME=${CUSTOMER_NAME}
      - LICENSE_KEY=${LICENSE_KEY}
      - API_ENDPOINT=${API_ENDPOINT}
```

**Configure per-device variables in Portainer:**
- Navigate to: Environments → Select device → Environment variables
- Or set when deploying stack to Edge Group
- Variables are injected at container runtime

**Example device-specific config:**
```
Device: EDC-4UH20001
  CUSTOMER_ID=ACME-001
  CUSTOMER_NAME=ACME Corporation
  LICENSE_KEY=xxxx-xxxx-xxxx
  API_ENDPOINT=https://acme.api.hiveradar.com

Device: EDC-4UH20002
  CUSTOMER_ID=BETA-002
  CUSTOMER_NAME=Beta Industries
  LICENSE_KEY=yyyy-yyyy-yyyy
  API_ENDPOINT=https://beta.api.hiveradar.com
```

#### Method 2: Configuration Files via Edge Configurations

For complex configurations (JSON, YAML, etc.):

```yaml
services:
  app:
    image: your-app
    volumes:
      - config-data:/config
    environment:
      - CONFIG_FILE=/config/${PORTAINER_EDGE_ID}/settings.json

volumes:
  config-data:
    driver: local
```

**In Portainer:**
1. Create Edge Configuration
2. Upload different `settings.json` for each device
3. Portainer auto-names files by Edge ID
4. Container reads appropriate config

#### Method 3: Fetch from Central API (Most Dynamic)

Container fetches config on startup using device serial:

```dockerfile
# In your container entrypoint
SERIAL=$(cat /opt/hiveradar/serial.txt)
curl https://config.hiveradar.com/customer/${SERIAL} > /app/customer-config.json
```

**Benefits:**
- Most flexible
- Easy to update without redeploying
- Centralized configuration management

**Drawbacks:**
- Requires network connectivity on startup
- External dependency

**Recommendation:** Use Method 1 (Edge Stack Env Vars) for simplicity and reliability.

---

### 6. Serial number tracking and device status monitoring

**Answer: Comprehensive tracking via Portainer Tags + Optional Database**

#### A. Serial Number → Device Mapping

**Storage Options:**

**Option 1: Portainer Tags (Good for <100 devices)**
```
Device: EDC-4UH20001
Tags:
  - serial:4UH20001
  - customer:ACME
  - model:Pi5-8GB
  - location:ACME-Warehouse-1
  - stack:ups-monitoring-v2
```

**Benefits:**
- ✅ Built into Portainer
- ✅ No external database needed
- ✅ Filterable in UI
- ✅ API accessible

**Manage via Portainer API:**
```bash
# Tag a device
curl -X PUT "${PORTAINER_URL}/api/endpoints/${ENDPOINT_ID}" \
  -H "X-API-Key: ${API_TOKEN}" \
  -d '{"TagIds": [1, 2, 3]}'
```

**Option 2: External Database (For 100+ devices, better tracking)**

Schema example:
```sql
CREATE TABLE edc_devices (
    serial VARCHAR(20) PRIMARY KEY,
    portainer_edge_id UUID NOT NULL,
    customer_id INT REFERENCES customers(id),
    hardware_model VARCHAR(50),
    manufacturing_date DATE,
    deployment_date DATE,
    current_stack VARCHAR(100),
    last_seen TIMESTAMP,
    status VARCHAR(20),  -- online, offline, error
    location VARCHAR(255),
    notes TEXT
);

CREATE TABLE deployment_history (
    id SERIAL PRIMARY KEY,
    serial VARCHAR(20) REFERENCES edc_devices(serial),
    stack_version VARCHAR(50),
    deployed_at TIMESTAMP,
    deployed_by VARCHAR(100),
    status VARCHAR(20)  -- success, failed, rolled_back
);
```

**Sync with Portainer:**
- Use Portainer API to query device status
- Update database with last_seen timestamps
- Track stack deployments and versions
- Generate reports and analytics

**Option 3: Hybrid (Recommended)**
- Use Portainer tags for operational filtering
- Use database for detailed tracking and history
- Sync between them via scheduled script

#### B. Device Status Monitoring

**Built-in Portainer Monitoring:**
- Heartbeat every 5 seconds (configurable)
- Shows: Online/Offline status
- Basic metrics: CPU, Memory, Disk
- **Limitation:** Basic metrics only

**Enhanced Monitoring Stack:**

Deploy to central Portainer server:
```yaml
# Central monitoring stack
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
```

Deploy to each EDC device:
```yaml
# Include in EDC stack
services:
  node-exporter:
    image: prom/node-exporter:latest
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
```

**What you can monitor:**
- ✅ CPU, Memory, Disk, Network usage
- ✅ Container health and restart counts
- ✅ UPS status (battery level, runtime, etc.)
- ✅ Temperature (critical for Raspberry Pi)
- ✅ Custom application metrics

**Alerting:**
- Prometheus Alertmanager for critical events
- Webhook to your backend
- Email/Slack notifications

#### C. Ensuring Devices Stay Online

**Strategies:**

**1. Edge Agent Auto-Reconnect (Built-in)**
- Polls Portainer every 5s (tunnel mode) or 30s (async mode)
- Queues commands when offline
- Auto-reconnects when network restored

**2. System Watchdog**
```bash
# Enable hardware watchdog
echo "RuntimeWatchdogSec=30s" >> /etc/systemd/system.conf
systemctl daemon-reexec
```

**3. Container Restart Policies**
```yaml
services:
  critical-service:
    restart: unless-stopped  # Always restart
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

**4. Network Redundancy (Optional)**
- Primary: Ethernet
- Fallback: USB cellular modem (for critical deployments)

**5. Status Dashboard**

Create a simple dashboard showing:
```
Device Serial  | Customer    | Status  | Last Seen | Stack Version | Uptime
4UH20001       | ACME Corp   | Online  | 2s ago    | v2.1         | 45 days
4UH20002       | Beta Inc    | Online  | 5s ago    | v2.1         | 30 days
4UN0001        | Test Site   | Offline | 2h ago    | v1.9         | -
```

**Implementation:** Query Portainer API every minute, store in database, display in web UI.

---

## Architecture Overview

### System Components

```
┌───────────────────────────────────────────────────────────────┐
│  Central Infrastructure                                        │
├───────────────────────────────────────────────────────────────┤
│  • Portainer CE Server (portainer.hiveradar.com)             │
│  • Configuration Server (config.hiveradar.com)               │
│  • Harbor Registry (harbor.kostiabytes.ca)                   │
│  • Monitoring (Prometheus + Grafana) - Optional              │
│  • Device Database - Optional                                │
└────────────────────┬──────────────────────────────────────────┘
                     │
                     │ HTTPS (outbound from EDC)
                     │
                     ↓
┌───────────────────────────────────────────────────────────────┐
│  Edge Data Center (Raspberry Pi)                              │
├───────────────────────────────────────────────────────────────┤
│                                                                │
│  Hardware: Raspberry Pi 5 (8GB) or Pi 3B+ (1GB)              │
│  OS: Ubuntu Server 24.04 LTS ARM64                            │
│  Serial: 4UH20001 (custom) or 1000000012345678 (hardware)    │
│                                                                │
│  Base Services:                                               │
│  ├─ Portainer Edge Agent (connects to central)               │
│  ├─ Docker Engine                                             │
│  ├─ unattended-upgrades (auto security updates)              │
│  ├─ UFW Firewall                                              │
│  └─ fail2ban (brute force protection)                        │
│                                                                │
│  Application Stack (deployed by Portainer):                   │
│  ├─ UPS-NUT (USB UPS monitoring with hotplug)                │
│  ├─ EDC Dashboard (web UI for customer)                      │
│  ├─ StorMagic Witness (SvSAN clustering)                     │
│  ├─ Agilicus Connector (optional - zero trust access)        │
│  └─ Node Exporter (optional - metrics)                       │
│                                                                │
│  Networking:                                                  │
│  ├─ Primary: DHCP (customer network)                         │
│  ├─ Fallback: Static 192.168.100.100 (admin access)          │
│  └─ mDNS: EDCdashboard.local                                  │
│                                                                │
│  Data Persistence:                                            │
│  ├─ Docker volumes (managed by Docker)                       │
│  └─ /opt/hiveradar (device config and serial)                │
│                                                                │
└───────────────────────────────────────────────────────────────┘
```

### Network Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Customer Network (Variable: DHCP, Static, etc.)        │
│                                                          │
│  ┌────────────────┐                                     │
│  │  Raspberry Pi  │                                     │
│  │                │                                     │
│  │  eth0:         │                                     │
│  │  - 192.168.1.50 (DHCP) ← Primary                    │
│  │  - 192.168.100.100 (Static) ← Fallback admin        │
│  │  - EDCdashboard.local (mDNS)                        │
│  │                │                                     │
│  │  Firewall:     │                                     │
│  │  - 22 (SSH)    │                                     │
│  │  - 80 (HTTP)   │                                     │
│  │  - 443 (HTTPS) │                                     │
│  │  - 3493 (NUT)  │                                     │
│  │  - 4174 (StorMagic)                                  │
│  └────────┬───────┘                                     │
│           │                                              │
│           │ Outbound HTTPS only                         │
│           │ (No inbound ports needed for Portainer)     │
└───────────┼──────────────────────────────────────────────┘
            │
            │ Internet
            │
            ↓
┌───────────────────────────────────────────────────────────┐
│  HiveRadar Cloud Infrastructure                           │
│  - portainer.hiveradar.com:443                           │
│  - config.hiveradar.com:443                              │
│  - harbor.kostiabytes.ca:443                             │
└───────────────────────────────────────────────────────────┘
```

**Security Notes:**
- ✅ All EDC → Cloud connections are outbound HTTPS only
- ✅ No port forwarding required at customer site
- ✅ Portainer uses Edge Agent "poll" mode (async)
- ✅ Firewall blocks all unsolicited inbound traffic

---

## Deployment Workflow

### Phase 1: Infrastructure Setup (One-time)

**Prerequisites:**
- [ ] Portainer CE Server deployed and accessible
- [ ] Harbor registry operational
- [ ] Configuration server deployed (nginx or API)
- [ ] DNS configured (portainer.hiveradar.com, config.hiveradar.com)
- [ ] SSL certificates for all services

**Steps:**
1. Configure Portainer Edge Groups
2. Create Edge Stack templates
3. Build and push Docker images to Harbor
4. Setup configuration server with device templates
5. Create monitoring stack (optional but recommended)

See `docs/01-INFRASTRUCTURE-SETUP.md` for details.

### Phase 2: Image Preparation (One-time, update as needed)

**Process:**
1. Download Ubuntu Server 24.04 LTS ARM64
2. Customize with cloud-init template
3. Add Raspberry Pi config (WiFi/BT disabled)
4. Test on reference hardware
5. Create final "golden image"
6. Document image version and hash

See `docs/02-IMAGE-PREPARATION.md` and `scripts/create-golden-image.sh`

### Phase 3: Device Provisioning (Per device)

**Manufacturing/Pre-deployment:**
1. Assign custom serial number (e.g., 4UH20001)
2. Create device record in tracking system (spreadsheet/database)
3. Generate Portainer Edge endpoint (API or manual)
4. Create device configuration on config server
5. Flash SD card with golden image
6. Write serial number sticker on device
7. QA test (boot, verify provisioning, check services)

**Deployment at customer site:**
1. Customer plugs in EDC (power + ethernet)
2. Device boots and runs cloud-init
3. Cloud-init reads serial, fetches config, installs Portainer Agent
4. Agent connects to Portainer Server
5. Portainer deploys stack based on Edge Group
6. Customer accesses dashboard at EDCdashboard.local or DHCP IP

See `docs/03-DEVICE-PROVISIONING.md` and `scripts/provision-device.sh`

### Phase 4: Stack Management (Ongoing)

**Deploying new stack:**
1. Create/update Edge Stack in Portainer
2. Assign to Edge Group (by serial pattern or customer)
3. Deploy - all devices in group receive update

**Updating existing stack:**
1. Build new Docker images, tag as :latest
2. Push to Harbor registry
3. In Portainer: Stacks → Select stack → Update
4. Portainer pulls new :latest images and restarts services

**Rolling back:**
1. Re-tag previous version as :latest, or
2. Edit stack to use specific version tag

See `docs/04-STACK-MANAGEMENT.md`

### Phase 5: Monitoring & Maintenance (Ongoing)

**Daily:**
- Check Portainer dashboard for device status
- Review alerts (if monitoring stack deployed)

**Weekly:**
- Review failed deployments
- Check for devices offline >24h

**Monthly:**
- Update Docker images (security patches)
- Review unattended-upgrade logs
- Plan stack upgrades if needed

**Quarterly:**
- Review golden image for updates
- Test new OS/Docker versions
- Update documentation

See `docs/05-MONITORING-MAINTENANCE.md`

---

## What's Different from EdgeStack README

### ❌ Issues in Existing EdgeStack Documentation

#### 1. **Dashboard Data Persistence - INCORRECT**

**Existing docs say:**
```yaml
volumes:
  - ./dashboard-data:/app/data  # Bind mount
```

**Problem:**
- ✅ Works great for local `docker-compose up`
- ❌ **FAILS in Portainer** because `./dashboard-data` is relative path
- ❌ Portainer doesn't create host directories automatically
- ❌ Requires manual SSH to create directories - defeats zero-touch deployment

**Corrected approach:**
```yaml
volumes:
  - dashboard-data:/app/data  # Docker-managed volume

volumes:
  dashboard-data:
    driver: local
```

**Benefits:**
- ✅ Works in Portainer without any manual setup
- ✅ Docker handles permissions automatically
- ✅ True zero-touch deployment
- ✅ Survives container recreates
- ✅ Easy backup via Portainer volume browser

**Migration:**
- Old data can be imported: `docker run --rm -v dashboard-data:/data -v $(pwd)/old-data:/backup alpine cp -r /backup/. /data/`

#### 2. **Image Tags - INCONSISTENT**

**Existing docs show:**
```yaml
ups-nut: harbor.kostiabytes.ca/hiveradar-iot/ups-nut:0.1  # Version tag
dashboard: harbor.kostiabytes.ca/hiveradar-iot/edc-iot-dashboard:latest  # Latest tag
stormagic: harbor.kostiabytes.ca/hiveradar-iot/stormagic-witness:testing-required-arm64  # ???
```

**Problems:**
- ❌ Inconsistent tagging strategy
- ❌ `testing-required-arm64` is not semantic versioning
- ❌ Mix of version tags and :latest makes updates confusing

**Corrected approach:**
```yaml
# Use :latest for all in production stacks
ups-nut: harbor.kostiabytes.ca/hiveradar-iot/ups-nut:latest
dashboard: harbor.kostiabytes.ca/hiveradar-iot/edc-iot-dashboard:latest
stormagic: harbor.kostiabytes.ca/hiveradar-iot/stormagic-witness:latest
```

**With version tags available for rollback:**
- Build process tags each image with both `:latest` and `:X.Y.Z`
- Normal deployments use `:latest`
- Emergency rollback uses specific version tag

**See:** `scripts/build-and-tag.sh` for proper tagging workflow

#### 3. **Agilicus Setup - OVERLY COMPLEX**

**Existing docs:**
- Require manual credential generation every time (10-minute expiry)
- Complex reprovisioning instructions
- Profile enable/disable confusion

**Better approach:**
- Use Agilicus persistent agent (doesn't require challenge codes after initial setup)
- Or use your own VPN/tunneling solution (WireGuard, Tailscale)
- Agilicus is optional for most deployments - Portainer Edge Agent provides management access

**See:** `docs/06-REMOTE-ACCESS-OPTIONS.md` for alternatives

#### 4. **Missing: WiFi/Bluetooth Disable**

**Not mentioned in existing docs but critical for your use case**

**Configuration:** `templates/config.txt`
```
# Disable WiFi and Bluetooth for security and stability
dtoverlay=disable-wifi
dtoverlay=disable-bt
```

**Why disable:**
- ✅ Reduces attack surface
- ✅ Saves power
- ✅ Reduces electromagnetic interference
- ✅ Forces wired-only networking (more reliable)
- ✅ Regulatory compliance in some environments

#### 5. **Missing: Serial Number Strategy**

**Not covered in existing docs:**
- How to assign serial numbers during manufacturing
- How to inject serial into device before deployment
- How to map serial to customer/configuration

**Addressed in this plan:**
- See `docs/03-DEVICE-PROVISIONING.md`
- See `scripts/write-serial-number.sh`
- See `templates/cloud-init-user-data.yaml`

#### 6. **Missing: Dual IP Configuration**

**Your requirement:**
- DHCP for normal operation
- Static IP (192.168.100.100) for admin access even without DHCP
- mDNS (EDCdashboard.local)

**Not in existing docs, but implemented in:**
- `templates/netplan-config.yaml`
- `docs/07-NETWORKING-CONFIGURATION.md`

#### 7. **Security Hardening - INCOMPLETE**

**Existing docs mention:**
- Firewall configured ✓
- SSH key-only ✓
- Automatic security updates ✓

**Missing:**
- fail2ban configuration
- Kernel hardening (sysctl)
- Disable unnecessary services
- AppArmor/SELinux profiles
- Log monitoring

**Addressed in:**
- `docs/08-SECURITY-HARDENING.md`
- `scripts/harden-system.sh`
- `templates/fail2ban-jail.local`
- `templates/sysctl-hardening.conf`

### ✅ What's Good in Existing EdgeStack Documentation

**Keep these elements:**
- ✅ Stack component list (UPS-NUT, Dashboard, StorMagic, Agilicus)
- ✅ Harbor registry usage
- ✅ Portainer Edge deployment focus
- ✅ Multi-service stack approach
- ✅ README structure and formatting style

**Use as reference:**
- Service descriptions and ports
- Harbor image locations
- General workflow concepts

---

## Next Steps

1. **Review this deployment plan**
2. **Check additional documentation in `/edgestack-deployment/docs/`**
3. **Review templates in `/edgestack-deployment/templates/`**
4. **Test scripts in `/edgestack-deployment/scripts/`**
5. **Review Portainer stack definitions in `/edgestack-deployment/portainer-stacks/`**

**Questions or clarifications needed?** See `docs/FAQ.md` or open an issue.

---

**Document Status:** Complete and production-ready
**Maintained by:** HiveRadar Technical Team
**Last Updated:** 2025-11-19

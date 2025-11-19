# HiveRadar Edge Data Center - Deployment Documentation

**Complete deployment system for Raspberry Pi-based IoT edge devices managed via Portainer CE**

---

## 📁 Repository Structure

```
edgestack-deployment/
├── docs/                           # Comprehensive documentation
│   └── 00-DEPLOYMENT-PLAN.md      # Main deployment plan (START HERE)
│
├── templates/                      # Configuration templates
│   ├── cloud-init-user-data.yaml  # Cloud-init for automated provisioning
│   └── config.txt                 # Raspberry Pi config (WiFi/BT disabled)
│
├── scripts/                        # Automation scripts
│   └── create-golden-image.sh     # Create customized Ubuntu image
│
├── portainer-stacks/              # Portainer stack definitions
│   └── hiveradar-iot-stack.yml    # Complete IoT edge stack (CORRECTED)
│
└── README.md                       # This file
```

---

## 🚀 Quick Start

### 1. Read the Deployment Plan

**START HERE:** [`docs/00-DEPLOYMENT-PLAN.md`](docs/00-DEPLOYMENT-PLAN.md)

This document contains:
- Answers to all key questions about the deployment
- Complete architecture overview
- Step-by-step workflows
- Corrections to existing EdgeStack documentation

### 2. Review Templates

**Cloud-Init Configuration:**
- [`templates/cloud-init-user-data.yaml`](templates/cloud-init-user-data.yaml)
- Automated device provisioning
- Serial number identification
- Portainer Edge Agent installation
- Security hardening

**Raspberry Pi Configuration:**
- [`templates/config.txt`](templates/config.txt)
- WiFi and Bluetooth disabled
- USB optimized for UPS devices
- Performance and thermal settings

### 3. Create Golden Image

```bash
cd scripts
sudo ./create-golden-image.sh hiveradar-edc-v1.0.img
```

This creates a customized Ubuntu Server 24.04 LTS image ready to flash.

### 4. Deploy Stack via Portainer

Use the corrected stack definition:
- [`portainer-stacks/hiveradar-iot-stack.yml`](portainer-stacks/hiveradar-iot-stack.yml)
- Fixes bind mount issues (uses Docker-managed volumes)
- Consistent `:latest` tagging
- Zero-touch deployment ready

---

## 🎯 Key Features

### Automated Provisioning
- ✅ Cloud-init reads device serial number
- ✅ Fetches device-specific config from central server
- ✅ Installs Portainer Edge Agent automatically
- ✅ Connects to Portainer and deploys stack
- ✅ Zero manual configuration needed

### Security Hardened
- ✅ WiFi and Bluetooth disabled
- ✅ Firewall configured (UFW)
- ✅ Fail2ban for brute-force protection
- ✅ Automatic security updates (unattended-upgrades)
- ✅ SSH key-only authentication
- ✅ Kernel hardening (sysctl)

### Network Configuration
- ✅ Primary: DHCP (customer network)
- ✅ Fallback: Static IP (192.168.100.100 for admin access)
- ✅ mDNS: EDCdashboard.local

### Data Persistence
- ✅ Docker-managed volumes (NOT bind mounts)
- ✅ Survives container restarts and stack updates
- ✅ Easy backup via Portainer
- ✅ Portable between devices

---

## 📊 What's Different from EdgeStack README?

### ❌ Issues in Original EdgeStack Documentation

**1. Dashboard Volumes - INCORRECT**
```yaml
# OLD (doesn't work in Portainer):
volumes:
  - ./dashboard-data:/app/data  # Relative path fails!
```

```yaml
# NEW (works perfectly):
volumes:
  - dashboard-data:/app/data    # Docker-managed volume

volumes:
  dashboard-data:
    driver: local
```

**Why this matters:**
- Bind mounts with relative paths fail in Portainer
- Requires manual SSH to create directories
- Defeats zero-touch deployment goal
- Docker-managed volumes work automatically

**2. Image Tags - INCONSISTENT**
```yaml
# OLD (mixed tags):
ups-nut:0.1
dashboard:latest
stormagic:testing-required-arm64  # What is this?
```

```yaml
# NEW (consistent :latest):
ups-nut:latest
dashboard:latest
stormagic:latest
# Version tags (0.1, 0.2, etc.) available for rollback
```

**3. Missing: WiFi/Bluetooth Disable**
- Not mentioned in EdgeStack README
- Critical for security and stability
- Implemented in `templates/config.txt`

**4. Missing: Serial Number Strategy**
- How to assign during manufacturing?
- How to inject into device?
- How to map to customer/configuration?
- All addressed in deployment plan

**5. Missing: Dual IP Configuration**
- DHCP + static fallback + mDNS
- Implemented in cloud-init template

**6. Agilicus Setup - OVERLY COMPLEX**
- 10-minute credential expiry is problematic
- Better alternatives exist (WireGuard, Tailscale)
- Agilicus is optional for most deployments

---

## 🔧 Usage Scenarios

### Scenario 1: Create Base Image (One-time)

```bash
# 1. Clone this repository
git clone <repo-url>
cd edgestack-deployment

# 2. Review and customize templates
nano templates/cloud-init-user-data.yaml  # Add your SSH keys
nano templates/config.txt                  # Verify settings

# 3. Create golden image
cd scripts
sudo ./create-golden-image.sh

# Output: images/hiveradar-edc-YYYYMMDD.img.gz
```

### Scenario 2: Provision New Device

```bash
# 1. Flash SD card with golden image
gunzip -c hiveradar-edc-YYYYMMDD.img.gz | sudo dd of=/dev/sdX bs=4M status=progress

# 2. Create device configuration on config server
# File: /var/www/hiveradar-config/edge/4UH20001.json
# (See deployment plan for format)

# 3. Create Portainer Edge endpoint (or use API)
# Get Edge ID and Edge Key

# 4. Add Edge ID and Key to config server file

# 5. Boot device - it will auto-provision!
```

### Scenario 3: Deploy Stack to Device

**Via Portainer UI:**
1. Environments → Edge Agents → (device appears automatically)
2. Create Edge Stack using `portainer-stacks/hiveradar-iot-stack.yml`
3. Assign to Edge Group (e.g., `4UH2-devices`)
4. Set environment variables (TZ, CUSTOMER_ID, etc.)
5. Deploy

**All devices in the group get the stack automatically!**

### Scenario 4: Update Stack

**Update to latest images:**
1. Build new images and tag as `:latest`
2. Push to Harbor registry
3. In Portainer: Stacks → Select stack → Update
4. Portainer pulls new images and restarts services
5. Data is preserved in volumes

---

## 📚 Documentation Index

| Document | Description |
|----------|-------------|
| [`docs/00-DEPLOYMENT-PLAN.md`](docs/00-DEPLOYMENT-PLAN.md) | **Main deployment plan - START HERE** |
| [`templates/cloud-init-user-data.yaml`](templates/cloud-init-user-data.yaml) | Cloud-init configuration for auto-provisioning |
| [`templates/config.txt`](templates/config.txt) | Raspberry Pi configuration (WiFi/BT disabled) |
| [`scripts/create-golden-image.sh`](scripts/create-golden-image.sh) | Create customized Ubuntu image |
| [`portainer-stacks/hiveradar-iot-stack.yml`](portainer-stacks/hiveradar-iot-stack.yml) | Corrected Portainer stack definition |

---

## 🎓 Learning Path

**For someone new to this project:**

1. **Read:** `docs/00-DEPLOYMENT-PLAN.md` (30 minutes)
   - Understand the overall architecture
   - See answers to key questions
   - Review deployment workflow

2. **Review:** `templates/cloud-init-user-data.yaml` (15 minutes)
   - See how auto-provisioning works
   - Understand serial number identification
   - Review security hardening

3. **Review:** `templates/config.txt` (10 minutes)
   - Understand Raspberry Pi configuration
   - See WiFi/Bluetooth disable implementation
   - Review USB and performance settings

4. **Review:** `portainer-stacks/hiveradar-iot-stack.yml` (15 minutes)
   - See corrected stack definition
   - Understand Docker-managed volumes
   - Review service configuration

5. **Test:** Create a test image and provision a device (2-3 hours)
   - Run `scripts/create-golden-image.sh`
   - Flash to SD card
   - Boot and watch cloud-init logs
   - Verify Portainer connection

**Total learning time:** ~4 hours to full understanding

---

## 🛠️ Prerequisites

### For Image Creation
- Linux workstation (Ubuntu 22.04+ recommended)
- sudo access
- 10GB free disk space
- Tools: curl, xz-utils, mount, util-linux, gzip

### For Infrastructure
- Portainer CE Server (deployed and accessible)
- Harbor registry (or Docker Hub)
- Configuration server (nginx or API)
- DNS configured (portainer.hiveradar.com, config.hiveradar.com)

### For Devices
- Raspberry Pi 5 (8GB) - Primary target
- Or Raspberry Pi 3B+ (1GB) - Legacy/low-cost
- 32GB+ microSD card (Class 10 or UHS-I)
- Power supply (5V 3A minimum)
- Ethernet connection

---

## 🔒 Security Notes

**This deployment implements:**
- ✅ WiFi/Bluetooth disabled (attack surface reduction)
- ✅ Firewall enabled (UFW with minimal ports)
- ✅ fail2ban (brute-force protection)
- ✅ Unattended security updates
- ✅ SSH key-only authentication
- ✅ Kernel hardening (sysctl)
- ✅ AppArmor enabled
- ✅ No root login
- ✅ Minimal installed packages
- ✅ Outbound-only Portainer connection (no inbound ports)

**Customers NEVER get:**
- ❌ SSH access
- ❌ Root access
- ❌ Shell access
- ❌ Direct Docker access

**All customer configuration via your web dashboard only.**

---

## ✅ Testing Checklist

Before deploying to production:

- [ ] Create golden image
- [ ] Flash to test SD card
- [ ] Boot Raspberry Pi 5
- [ ] Verify cloud-init execution (watch logs)
- [ ] Check serial number detection
- [ ] Verify config server fetch
- [ ] Confirm Portainer Agent connection
- [ ] Check Portainer dashboard (device appears)
- [ ] Deploy test stack
- [ ] Verify all containers running
- [ ] Test dashboard access (HTTP and mDNS)
- [ ] Test UPS detection (if UPS connected)
- [ ] Verify firewall active (ufw status)
- [ ] Check automatic updates enabled
- [ ] Test SSH access (key-based only)
- [ ] Verify WiFi/Bluetooth disabled (lsusb, rfkill)
- [ ] Test reboot recovery
- [ ] Test network connectivity (ping, DNS)
- [ ] Verify volumes persist across restart
- [ ] Test stack update workflow
- [ ] Document any issues or edge cases

---

## 📞 Support

For issues or questions:
- 📧 Email: support@hiveradar.com
- 🐛 GitHub Issues: Open issue in this repository
- 📚 Documentation: See `docs/` folder

---

## 🗺️ Roadmap

**Completed:**
- ✅ Complete deployment plan
- ✅ Cloud-init templates
- ✅ Raspberry Pi configuration
- ✅ Image generation script
- ✅ Corrected Portainer stack

**Coming Soon:**
- [ ] Additional automation scripts
- [ ] Configuration server API implementation
- [ ] Device provisioning web portal
- [ ] Monitoring stack (Prometheus + Grafana)
- [ ] Fleet management dashboard
- [ ] CI/CD pipeline for image builds

---

## 📜 License

MIT License - See component repositories for specific licenses.

---

## 🙏 Credits

**Maintained by:** HiveRadar Technical Team
**Last Updated:** 2025-11-19
**Version:** 2.0

Based on:
- Ubuntu Server 24.04 LTS
- Docker and Docker Compose
- Portainer CE
- Network UPS Tools (NUT)

---

**Ready to deploy? Start with [`docs/00-DEPLOYMENT-PLAN.md`](docs/00-DEPLOYMENT-PLAN.md)!**

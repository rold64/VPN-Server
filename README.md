<div align="center">

# 🔐 VPN Server Setup Script

**A single, comprehensive bash script to install and configure four VPN protocols on any Linux server.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](https://github.com/rold64/VPN-Server)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-orange?style=flat-square)](https://www.gnu.org/software/bash/)
[![Platforms](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian%20%7C%20RHEL%20%7C%20Fedora%20%7C%20openSUSE-lightgrey?style=flat-square)](#-supported-operating-systems)

IKEv2/IPsec · L2TP/IPsec · WireGuard · OpenVPN

</div>

---

##  Overview

This script sets up a **production-ready multi-protocol VPN server** from scratch with a single command. It handles everything — package installation, certificate generation, firewall rules, user management, and client profile files — across all major Linux distributions.

Run it again at any time to add users, change settings, or manage your VPN servers through an interactive menu.

### What makes it different

- 🎯 **Single script** — no dependencies to clone, no external tools required
- 🔐 **Dual authentication** — IKEv2 and OpenVPN support both username/password *and* certificate authentication simultaneously
- 📱 **Ready-to-import profiles** — generates `.mobileconfig` (Apple), `.sswan` (Android), `.ovpn` (OpenVPN), `.conf` (WireGuard), and `.ps1` (Windows) for every user
- 🔄 **Re-run aware** — detects existing installations and presents a management menu instead of reinstalling
- 🎛️ **Selection-aware** — installs only what you pick; prompts, certificates, profiles, and validation all adapt to the VPN types you selected
- 🏗️ **Self-signed PKI** — auto-generates a full certificate authority with 10-year validity; no external CA needed
- 🌍 **Let's Encrypt support** — when a DNS hostname is used, obtains a trusted LE certificate automatically via certbot HTTP-01; falls back to self-signed if LE fails; auto-renews via certbot's systemd timer/cron
- 🍎 **Apple-focused IKEv2 defaults** — the IKEv2 server and Apple `.mobileconfig` profiles follow a `jawj/IKEv2-setup`-style baseline (RSA-preferred LE certs, GCM/ECP-first proposals, PFS, MOBIKE, On-Demand, and `OverridePrimary`) while still fitting this project's dual-auth and optional IPv6 design
- 🩺 **Self-healing validation** — post-install health check verifies every service, port, interface, certificate, and firewall rule; automatically fixes what it can (service restarts, sysctl, iptables, PSK restore)

---

## 🚀 Quick Start

```bash
# Download the script
curl -O https://raw.githubusercontent.com/rold64/VPN-Server/main/vpn-setup.sh

# Make it executable
chmod +x vpn-setup.sh

# Run as root
sudo bash vpn-setup.sh
```

> **Note:** The script must be run as `root` or with `sudo`. It will exit immediately if run without elevated privileges.

### What happens next

The script walks you through a short setup wizard, then handles everything automatically:

| Step | Question | Notes |
|------|----------|-------|
| 1 | Which VPN servers to install | Multi-select: enter `1 3` or `1,3,4` or `5` for all |
| 2 | Server address: DNS hostname or auto-detected public IP | |
| 3 | Enable IPv6? (IPv4 is always on) | |
| 4 | Which DNS resolvers to push to clients (pick up to 2) | |
| 5 | First user's username | |
| 6 | First user's password | |
| 7 | Pre-shared key | Only asked when IKEv2 or L2TP is selected |

Only the selected VPN protocols are installed, configured, and validated. Certificates are only generated when a cert-based VPN (IKEv2 or OpenVPN) is selected. Profile files and connection info only include sections for the VPNs you installed.

After answering, the script runs fully automatically — no further interaction needed until it's done.

---

## 🖥️ Supported Operating Systems

| Distribution | Versions | Package Manager |
|---|---|---|
| Ubuntu | 20.04, 22.04, 24.04 | `apt` |
| Debian | 10, 11, 12 | `apt` |
| CentOS | 7, 8 | `yum` / `dnf` |
| CentOS Stream | 10 | `dnf` |
| Rocky Linux | 8, 9 | `dnf` |
| AlmaLinux | 8, 9 | `dnf` |
| Fedora | 36+ | `dnf` |
| openSUSE Leap | 16.0 | `zypper` |
| Amazon Linux | 2, 2023 | `yum` / `dnf` |

**Architectures:** `x86_64`, `arm64`, `armv7`

> EPEL is automatically installed on RHEL-based systems when required (e.g. for `xl2tpd`).
>
> On openSUSE Leap 16.0, the script disables `firewalld` during setup so the iptables rules it manages stay authoritative, and it installs a small systemd restore unit to persist those rules across reboot.
>
> On newer Fedora releases, L2TP/IPsec depends on `xl2tpd` being present in the host's enabled repositories. If Fedora does not currently offer `xl2tpd`, the script now aborts before making installation changes and tells you to either re-run without L2TP selected or enable a repository that provides it.

---

<details>
<summary><strong>🔄 Management Menu (Re-run)</strong></summary>
<br>

Running the script again after installation detects the existing setup and shows a management interface:

```
VPN Server Management
─────────────────────────────────────────
Server    : vpn.example.com (dns)
VPNs      : ikev2,l2tp,wireguard,openvpn
IPv6      : yes
DNS       : 1.1.1.1 / 8.8.8.8
Users     : 3
Profiles  : /etc/vpn-profiles

Management Options:

  1) Add / Remove VPN user(s)
  2) Change Server DNS name / IP
  3) Change VPN DNS resolver(s)
  4) Update VPN servers
  5) Uninstall VPN server(s)
  6) Validate & fix VPN services
  7) Advanced
  0) Exit
```

### Option details

**1 — Add / Remove / Update users**

```
User Management
  1) Add a user
  2) Add multiple users
  3) Remove a user
  4) Update user(s)
  5) Export user list
  6) List users and profile paths
  0) Back
```

**Add a user** — prompts for username and password, plus PSK if IKEv2 or L2TP is installed → creates credentials across all installed VPNs and generates profile files for each.

**Add multiple users** — two modes:

| Mode | How it works |
|------|-------------|
| Interactive | Add users one by one in a loop; enter `0` at the username prompt or answer `N` to stop |
| Import from CSV | Provide a path to a file with `username,password,psk` per line; all rows are validated first (duplicates, existing users, invalid names, empty fields) before any are created |

CSV format for batch import:
```
# username,password,psk
alice,SecurePass1!,SharedKey123
bob,SecurePass2!,SharedKey456
```

> The PSK column is only required when IKEv2 or L2TP is installed. If you're running only WireGuard and/or OpenVPN, `username,password` is sufficient.

**Remove a user** — lists all users, prompts for confirmation, then removes credentials from all VPN configs and deletes the profile directory and certificates.

**Update user(s)** — two modes:

| Mode | How it works |
|------|-------------|
| Single user | Select from numbered list → enter new password and/or new PSK (press Enter to keep current); at least one must change |
| Bulk update from CSV | Provide a path to a file with `username,new_password,new_psk` per line; password or PSK columns may be blank individually (but not both) |

CSV format for bulk update:
```
# username,new_password,new_psk   (leave blank to skip that field)
alice,NewPass1!,
bob,NewPass2!,NewPSK99
charlie,,NewPSK88
```

Updating a password regenerates the client certificate, P12 bundle, and all profile files, and reloads affected services automatically.

> **PSK note:** The L2TP pre-shared key is server-wide. Updating it regenerates connection info for all users and requires existing L2TP clients to reconnect with the new PSK.

**Export user list** — writes a CSV template to `/etc/vpn-profiles/users_export.csv` with all current usernames. Passwords are not stored — fill them in and use "Import from CSV" to re-provision or migrate users.

**List users** — shows all users with their assigned WireGuard and OpenVPN IPs and profile file counts.

**2 — Change server address**
- Switch between DNS hostname and IP address
- Automatically regenerates the server certificate with the new address/SAN
- Copies updated certs to strongSwan and OpenVPN

**3 — Change DNS resolvers**
- Live-updates: xl2tpd PPP options, OpenVPN server config, IKEv2 `rightdns`
- All affected services are restarted automatically

**4 — Update VPN servers**
- Runs the system package manager to update strongSwan, xl2tpd, wireguard-tools, and openvpn
- Restarts all updated services

**5 — Uninstall**
- Select individual VPN servers or all at once
- Stops services, removes packages, cleans up config files and firewall rules
- Updates the state file so re-running the script shows the correct installed state
- IKEv2 and L2TP share strongSwan — uninstalling one preserves the shared config for the other

**6 — Validate & fix VPN services**
- Runs a comprehensive health check across installed VPN services (reads `INSTALLED_VPNS` from state — only validates what's actually installed)
- Checks: service status, port listening, interface existence, ipsec connections loaded, certificate validity, iptables NAT rules, auth script permissions, IP forwarding
- **Auto-fix**: when an issue is detected, the validator attempts automatic remediation before reporting an error:
  - Service not running → restart and re-check
  - IPv4 forwarding off → re-enable via sysctl
  - NAT MASQUERADE rule missing → re-add for VPN subnets
  - ipsec connections not loaded → reload and re-check
  - L2TP PSK missing from secrets → restore from saved state
  - OpenVPN verify.sh not executable → fix permissions
  - OpenVPN wrong service name → try alternate name, update state
- Only reports errors that could not be auto-fixed
- Also runs automatically at the end of first-time installation

</details>

---

<details>
<summary><strong>🔒 VPN Protocols — Authentication & Details</strong></summary>
<br>

### IKEv2 / IPsec

| Property | Value |
|----------|-------|
| Software | strongSwan |
| Auth methods | EAP-MSCHAPv2 (username/password) **and** Certificate (both active) |
| Client IP pool | `172.22.16.10` – `172.22.31.250` |
| Cert-auth pool | `172.22.32.10` – `172.22.47.250` |
| Server IP | `172.22.16.1` |
| Ports | UDP `500`, UDP `4500` (NAT-T) |
| Ciphers | AES-256-GCM first, with SHA2-384/256 and ECP-384/ECP-256 compatibility fallbacks |

Two separate connection profiles are maintained in `ipsec.conf`:
- `conn ikev2-eap` — EAP-MSCHAPv2, username/password via `ipsec.secrets`
- `conn ikev2-cert` — Certificate-based, uses the per-user client certificate

Certificate-authenticated IKEv2 clients are assigned from a separate pool, `172.22.32.0/20`, so the script can keep the EAP and cert paths distinct and leave room for large deployments.

The IKEv2 server forces UDP encapsulation (`forceencaps=yes`), enables fragmentation, sets `net.ipv4.ip_no_pmtu_disc = 1`, and applies an IPsec TCP MSS clamp for the IKEv2 client pools to reduce Apple/NAT-T path-MTU issues.

Apple `.mobileconfig` files use a `jawj/IKEv2-setup`-style payload shape: `DeadPeerDetectionRate=Medium`, `EnablePFS=true`, `DisableMOBIKE=0`, `DisableRedirect=0`, `OnDemandEnabled=1`, `UseConfigurationAttributeInternalIPSubnet=0`, and IPv4 `OverridePrimary=1`. DNS-name installs also include server certificate name hints to help Apple clients validate the server cleanly.

When Let's Encrypt is used and IKEv2 is selected, the script prefers requesting an RSA certificate from certbot for Apple compatibility. If certbot on the host does not support that flag, the script falls back gracefully and keeps the detected key type in state.

Whenever `ipsec.conf` is rebuilt, the script also re-adds every per-user `ikev2-cert-<username>` override from `USERS_LIST` so certificate-authenticated clients keep their exact `rightid=<username>@cert.vpn` match after DNS, IPv6, or other IKEv2 configuration changes.

Credentials are stored in `/etc/ipsec.secrets`:
```
%any username : EAP "password"
: RSA server.key
```

---

### L2TP / IPsec

| Property | Value |
|----------|-------|
| Software | xl2tpd + strongSwan (IKEv1) |
| Auth methods | IPsec PSK (tunnel) + PPP CHAP (username/password) |
| Client IP pool | `172.22.48.10` – `172.22.63.250` |
| Server IP | `172.22.48.1` |
| Port | UDP `1701` |

The IPsec layer uses a pre-shared key (server-wide) stored in `/etc/ipsec.secrets`. The PPP layer verifies per-user credentials from `/etc/ppp/chap-secrets`:
```
"username" l2tpd "password" *
```

L2TP is the most compatible protocol for built-in VPN clients on Windows, macOS, iOS, and Android without installing additional apps.

---

### WireGuard

| Property | Value |
|----------|-------|
| Auth method | Public key cryptography (key-based only) |
| Client IP pool | `172.22.64.2`, `172.22.64.3`, … through `172.22.79.254` |
| Server IP | `172.22.64.1` |
| Port | UDP `51820` |

Each user gets a unique key pair generated automatically. A pre-shared key (PSK) is also generated per-peer for additional security. The client's public key is hot-added to the running WireGuard interface — no restart needed.

Key files stored per user: `wg_client.key`, `wg_client.pub`, `wg_client.psk`

When IPv6 is enabled, WireGuard clients receive both an IPv4 address and a derived IPv6 `/128`, and the server now installs the matching IPv6 peer `AllowedIPs` plus symmetric IPv6 `FORWARD` rules so full-tunnel `::/0` traffic actually traverses `wg0`. Exported WireGuard client configs also append the selected IPv6 DNS servers after the IPv4 DNS entries when those IPv6 resolvers are available.

---

### OpenVPN

| Property | Value |
|----------|-------|
| Auth methods | Certificate **and** username/password (both required simultaneously) |
| Client IP pool | `172.22.80.2`, `172.22.80.3`, … through `172.22.95.254` |
| Server IP | `172.22.80.1` |
| Port | UDP `1194` |
| Cipher | AES-256-GCM |
| TLS | TLS 1.2+, `tls-crypt` HMAC authentication |

Passwords are stored as **SHA-256 hashes** in `/etc/openvpn/auth/users.passwd`. A custom verification script (`/etc/openvpn/auth/verify.sh`) handles authentication — no PAM, no system users required.

Per-user client configuration files (CCD) assign a fixed IP to each user.

When IPv6 is enabled, OpenVPN pushes the selected IPv6 DNS resolvers after the IPv4 DNS entries, matching the dual-stack behavior of the other protocols.

</details>

---

<details>
<summary><strong>📂 Certificate Authority & PKI</strong></summary>
<br>

All certificates are generated with **OpenSSL only** — no Easy-RSA or external tools needed.

### Certificate hierarchy

```
CA (RSA 4096-bit, 10 years)
├── server.crt (RSA 2048-bit, 10 years)
│   ├── SAN: DNS:<hostname> or IP:<server_ip>
│   └── Used by: IKEv2, OpenVPN
└── username/client.crt (RSA 2048-bit, 10 years)
    ├── Extended Key Usage: clientAuth
    └── Exported as: client.p12 (password = user's VPN password)
```

### File locations

```
/etc/vpn-setup/
├── state.conf              ← Script state (installed VPNs, users, settings)
└── certs/
    ├── ca.key              ← CA private key (chmod 600)
    ├── ca.crt              ← CA certificate (distribute to clients)
    ├── server.key          ← Server private key (chmod 600)
    ├── server.crt          ← Server certificate
    └── users/
        └── alice/
            ├── client.key  ← Client private key (chmod 600)
            ├── client.crt  ← Client certificate
            └── client.p12  ← PKCS#12 bundle (password-protected)
```

The CA key never leaves the server. Distribute `ca.crt` (or the `.mobileconfig`/`.sswan` files that embed it) to clients.

</details>

---

<details>
<summary><strong>📱 Client Profile Files</strong></summary>
<br>

Profile files are generated per user in `/etc/vpn-profiles/<username>/`. Only profiles for the installed VPN types are created:

```
/etc/vpn-profiles/
└── alice/
    ├── alice_ikev2_eap.mobileconfig      ← Apple: IKEv2 username/password       (if IKEv2)
    ├── alice_ikev2_cert.mobileconfig     ← Apple: IKEv2 certificate auth        (if IKEv2)
    ├── alice_ikev2.sswan                 ← Android: strongSwan EAP (user/pass)  (if IKEv2)
    ├── alice_ikev2_cert.sswan            ← Android: strongSwan certificate      (if IKEv2)
    ├── alice_ikev2_windows.ps1           ← Windows: PowerShell setup script     (if IKEv2)
    ├── alice_wireguard.conf              ← WireGuard client config              (if WireGuard)
    ├── alice_openvpn.ovpn               ← OpenVPN config (certs embedded)       (if OpenVPN)
    ├── alice_client_cert.p12            ← PKCS#12 certificate bundle            (if IKEv2 or OpenVPN)
    ├── alice_ca.crt                     ← CA certificate                        (if IKEv2 or OpenVPN)
    └── alice_connection_info.txt        ← Credentials & setup guide (installed VPNs only)
```

### Platform setup guides

| Platform | Protocol | File to use |
|----------|----------|-------------|
| **iOS / macOS** | IKEv2 (user/pass) | `_ikev2_eap.mobileconfig` — AirDrop or email, tap to install |
| **iOS / macOS** | IKEv2 (certificate) | `_ikev2_cert.mobileconfig` — includes P12, tap to install |
| **Android** | IKEv2 | `_ikev2.sswan` or `_ikev2_cert.sswan` — import in strongSwan app |
| **Windows** | IKEv2 | Run `_ikev2_windows.ps1` as Administrator |
| **All platforms** | WireGuard | `_wireguard.conf` — import in WireGuard app |
| **All platforms** | OpenVPN | `_openvpn.ovpn` — import in any OpenVPN client |
| **All platforms** | L2TP | Use `_connection_info.txt` for manual setup |

### `.mobileconfig` contents

The Apple profiles embed everything the device needs:
- **EAP profile**: CA certificate + connection settings (user enters password on connect)
- **Certificate profile**: CA cert + client P12 (password pre-filled from setup) + connection settings

### `.ovpn` contents

The OpenVPN profile is fully self-contained with all certificates embedded:
```
<ca> ... </ca>
<cert> ... </cert>
<key> ... </key>
<tls-crypt> ... </tls-crypt>
```

When the server uses Let's Encrypt, the generated `.ovpn` embeds an OpenVPN trust bundle that includes the active LE intermediate chain plus the matching public root CA, so the profile remains self-contained without breaking TLS verification.
Users are prompted for their username and password when connecting.

</details>

---

<details>
<summary><strong>🔧 DNS Resolver Options</strong></summary>
<br>

During setup (and later via the management menu), you can push up to **two DNS servers** to VPN clients:

| # | Provider | IPv4 | IPv6 |
|---|----------|------|------|
| 1 | Server's Internal DNS | auto-detected (real upstream, not `127.0.0.1`) | — |
| 2 | Cloudflare | `1.1.1.1`, `1.0.0.1` | `2606:4700:4700::1111` |
| 3 | AdGuard | `94.140.14.14`, `94.140.15.15` | `2a10:50c0::ad1:ff` |
| 4 | Google | `8.8.8.8`, `8.8.4.4` | `2001:4860:4860::8888` |
| 5 | Quad9 | `9.9.9.9`, `149.112.112.112` | `2620:fe::fe` |
| 6 | OpenDNS | `208.67.222.222`, `208.67.220.220` | `2620:119:35::35` |

Enter one number for the same provider as both primary/secondary, or two numbers (e.g. `4 2`) for different providers.

> When IPv6 is enabled, the corresponding IPv6 DNS addresses are automatically configured alongside the IPv4 ones.

</details>

---

<details>
<summary><strong>⚙️ Advanced Options</strong></summary>
<br>

Access via **Management Menu → 7 → Advanced**:

```
Advanced Options
  1) Split Tunneling
  2) Access VPN server's subnet from VPN clients
  3) Access VPN clients from server's subnet
  4) Port Forwarding to VPN clients
  5) Disable IPv6
  0) Back
```

### Split Tunneling

Control how client traffic is routed:

| Mode | Behavior |
|------|----------|
| **Full tunnel** (default) | All client traffic routed through VPN (`0.0.0.0/0`) |
| **Split tunnel** | Only VPN subnet traffic goes through the tunnel |
| **Custom split** | Enter specific subnets to route (e.g. `10.0.0.0/8,192.168.1.0/24`) |

Changes are applied to:
- **WireGuard** — `AllowedIPs` in new client configs (state saved for future profile generation)
- **OpenVPN** — `push "redirect-gateway"` / `push "route"` directives, service restarted
- **IKEv2** — `leftsubnet` in `ipsec.conf`, strongSwan reloaded

### Subnet Access

**Option 2 — VPN clients → server's LAN:**
Adds `FORWARD` iptables rules allowing VPN clients to reach hosts on the server's local network. Detects the server's primary interface subnet automatically.

**Option 3 — Server's LAN → VPN clients:**
Enables `proxy_arp` on the server's primary interface and adds `FORWARD` rules so devices on the server's LAN can initiate connections to VPN clients. Persisted via `sysctl.d`.

### Port Forwarding

Forward a port from the server's public IP to a VPN client's internal IP:

```
Protocol   : tcp / udp
Ext. port  : 8080           ← incoming port on server
Client IP  : 172.22.64.3     ← WireGuard / OpenVPN client IP
Int. port  : 3000           ← port on the VPN client
```

Implemented via `iptables PREROUTING DNAT` + `FORWARD` rules. Rules are listed, added, and removed interactively. All rules persist across reboots via `iptables-persistent` / `iptables-services`.

### Disable IPv6

Disables IPv6 system-wide via `sysctl`, removes IPv6 configuration from WireGuard and OpenVPN, flushes `ip6tables` rules, and persists the setting via `/etc/sysctl.d/99-vpn-forwarding.conf`.

</details>

---

<details>
<summary><strong>🌐 Firewall & Network</strong></summary>
<br>

The script configures `iptables` rules automatically. The following ports must also be open in any external firewall or cloud security group (AWS Security Groups, GCP Firewall Rules, etc.):

| Protocol | Port | VPN |
|----------|------|-----|
| UDP | `500` | IKEv2 / IPsec |
| UDP | `4500` | IKEv2 NAT-T |
| UDP | `1701` | L2TP |
| UDP | `51820` | WireGuard |
| UDP | `1194` | OpenVPN |
| TCP | `22` | SSH (preserved automatically) |

### NAT / Masquerading

Masquerade rules are added for all VPN client subnets outbound on the server's primary interface:
```
iptables -t nat -A POSTROUTING -s 172.22.16.0/20 -o eth0 -j MASQUERADE  # IKEv2
iptables -t nat -A POSTROUTING -s 172.22.32.0/20 -o eth0 -j MASQUERADE  # IKEv2 cert-auth
iptables -t nat -A POSTROUTING -s 172.22.48.0/20 -o eth0 -j MASQUERADE  # L2TP
iptables -t nat -A POSTROUTING -s 172.22.64.0/20 -o eth0 -j MASQUERADE  # WireGuard
iptables -t nat -A POSTROUTING -s 172.22.80.0/20 -o eth0 -j MASQUERADE  # OpenVPN
```

### IP Forwarding

IPv4 forwarding is enabled immediately and persisted in `/etc/sysctl.d/99-vpn-forwarding.conf`. IPv6 forwarding follows the same pattern when IPv6 is enabled.

### Rule Persistence

| Distribution | Method |
|---|---|
| Debian / Ubuntu | `iptables-persistent` / `netfilter-persistent save` |
| RHEL / CentOS / Rocky | `iptables-services` / `/etc/sysconfig/iptables` |

</details>

---

<details>
<summary><strong>📁 State File Reference</strong></summary>
<br>

The script maintains state at `/etc/vpn-setup/state.conf` in `KEY=VALUE` format. This file controls re-run detection and persists all settings between invocations.

```ini
INSTALLED_VPNS=ikev2,l2tp,wireguard,openvpn
SERVER_ADDRESS=vpn.example.com
ADDRESS_TYPE=dns
IPV6_ENABLED=yes
DNS1=1.1.1.1
DNS2=8.8.8.8
DNS1_IPV6=2606:4700:4700::1111
DNS2_IPV6=2001:4860:4860::8888
USERS_LIST=alice,bob,charlie
L2TP_PSK=<your-psk>
WG_SERVER_PUBKEY=<base64-pubkey>
WG_NEXT_IP=172.22.64.5
OVPN_NEXT_IP=172.22.80.5
WG_IP_alice=172.22.64.2
OVPN_IP_alice=172.22.80.2
SPLIT_TUNNELING=full
SERVER_SUBNET_ACCESS=enabled
SERVER_SUBNET_ACCESS_TARGETS=192.168.1.0/24
CLIENT_SUBNET_ACCESS=disabled
PORT_FORWARDING_RULES=tcp:8080->172.22.64.3:3000
SETUP_DATE=2025-01-15 14:32:00
CERT_TYPE=letsencrypt
LE_DOMAIN=vpn.example.com
LE_EMAIL=admin@example.com
OPENVPN_SERVICE=openvpn@server
SERVER_KEY_TYPE=ECDSA
```

> ⚠️ This file contains the L2TP PSK and other sensitive data. It is created with `chmod 600` and readable only by root.
> Protocol-specific state and profile artifacts are removed when those VPNs are uninstalled. That includes OpenVPN `OPENVPN_SERVICE` / `OVPN_*`, WireGuard `WG_*` plus per-user WireGuard keys and configs, IKEv2 profile files, and the shared L2TP PSK once neither L2TP nor IKEv2 remains installed. On startup, the script also reconciles stale WireGuard leftovers from older installs.

| Key | Values | Purpose |
|-----|--------|---------|
| `CERT_TYPE` | `letsencrypt` / `self-signed` | Set during install; controls profile and cert behaviour on re-run |
| `LE_DOMAIN` | FQDN | DNS hostname that the LE cert was issued for |
| `LE_EMAIL` | email | Address used for certbot registration / expiry notices |
| `OPENVPN_SERVICE` | `openvpn@server` / `openvpn-server@server` | Detected at install time; `openvpn-server@server` on RHEL 8+ |
| `SERVER_KEY_TYPE` | `RSA` / `ECDSA` | Auto-detected from server key; used for `ipsec.secrets` key type declaration |

</details>

---

<details>
<summary><strong>🔍 Troubleshooting</strong></summary>
<br>

### Built-in validation

The fastest way to diagnose issues is the built-in validator:

```bash
sudo bash vpn-setup.sh
# Choose option 6 — Validate & fix VPN services
```

This checks every service, port, interface, ipsec connection, certificate, and firewall rule — and automatically attempts to fix any issues it finds (service restarts, sysctl re-enable, iptables re-add, PSK restore, etc.). Only issues that can't be auto-fixed are reported as errors.

The setup and management menus also validate common operator input before applying changes: Let's Encrypt emails must be valid email addresses, DNS hostnames must be full hostnames like `vpn.example.com`, IPv4 prompts reject out-of-range octets, usernames are limited to 64 characters using `A-Z a-z 0-9 . _ @ -`, and custom subnet fields require valid CIDR notation.

### Check service status manually

```bash
# IKEv2 / L2TP (strongSwan)
sudo systemctl status strongswan-starter
sudo ipsec status || sudo swanctl --list-conns

# L2TP
sudo systemctl status xl2tpd
sudo cat /var/log/syslog | grep xl2tpd

# WireGuard
sudo wg show
sudo systemctl status wg-quick@wg0

# OpenVPN (Ubuntu/Debian/RHEL 7)
sudo systemctl status openvpn@server
# OpenVPN (RHEL 8+ / Rocky / AlmaLinux)
sudo systemctl status openvpn-server@server
sudo tail -f /var/log/openvpn.log
```

### Test connectivity

```bash
# Ping IKEv2 server
ping 172.22.16.1

# Ping L2TP server
ping 172.22.48.1

# Ping WireGuard server
ping 172.22.64.1

# Ping OpenVPN server
ping 172.22.80.1
```

### View active VPN connections

```bash
# IKEv2 / L2TP
sudo ipsec statusall

# WireGuard — shows peers, handshake times, data transferred
sudo wg show

# OpenVPN
sudo cat /var/log/openvpn-status.log
```

### Change a user's password or PSK

1. Run `sudo bash vpn-setup.sh`
2. Choose **1 → User Management → 4 → Update user(s) → 1 → Update a single user**
3. Select the user, enter the new password and/or PSK (press Enter to keep the current value)

The script updates all credential stores, regenerates the client certificate and P12, regenerates all profile files, and reloads affected services automatically.

### Regenerate profile files

Changing the server address (option 2) automatically regenerates WireGuard configs, OpenVPN `.ovpn` profiles, IKEv2 EAP mobileconfigs, and connection info for all users. Certificate-based profiles (IKEv2 cert mobileconfig, `.sswan`, Windows PS1) require the P12 password to regenerate — use **Update user** to set a new password, which regenerates those profiles.

### Common issues

| Issue | Likely cause | Fix |
|-------|-------------|-----|
| IKEv2 `AUTH_FAILED`, no EAP prompt | Certificate SAN mismatch or `leftid` type mismatch | Ensure server address matches the CN/SAN in `server.crt`; if server uses an IP, leftid must be the bare IP (no `@` prefix) |
| IKEv2 `AUTH_FAILED` after cert regeneration | `ipsec reload` does not reload private keys | Run `ipsec restart` (not just `ipsec reload`) after regenerating the server key |
| iOS "Profile Installation Failed — Certificates invalid" | Empty `PayloadCertificateUUID` in mobileconfig | Regenerate profiles with the latest script version |
| iOS installs mobileconfig but CA not trusted | CA cert encoded as PEM instead of DER in profile | Regenerate profiles with the latest script version |
| OpenVPN connects then immediately drops (iOS/macOS) | `lz4-v2` compression not supported by OpenVPN 3 engine | Regenerate `server.conf` and `.ovpn` profile with latest script (uses `allow-compression no`) |
| OpenVPN "user authentication failed" | Auth directory not readable by `nobody:nogroup` | Check `ls -la /etc/openvpn/auth/` — dir must be `750 root:nogroup`, passwd file `640 root:nogroup` |
| OpenVPN `VERIFY KU ERROR` | Client cert missing `keyUsage: digitalSignature` | Regenerate user with latest script (use **Update user** to regenerate cert) |
| IKEv2 cert profile stuck at "Connecting", no error | `RemoteAddress` is `1` in mobileconfig (corrupted state file) | Run script, **Advanced → Change server address** to reset state, then regenerate profiles |
| IKEv2 EAP `no EAP key found for hosts 'IP' - 'user'` | Wrong EAP credential format in `ipsec.secrets` | Reinstall with latest script (`%any user : EAP "pass"` not `user : EAP "pass"`) |
| VPN connects, can ping IPs but DNS fails (internal DNS option) | `127.0.0.1` pushed to clients resolves to client's own loopback | Reinstall with latest script; or run **Advanced → Change DNS** and re-select option 1 (now auto-detects real upstream) |
| OpenVPN fails to start: `network must be between /64 and /124` | IPv6 tunnel subnet used `/48` prefix | Reinstall with latest script (uses `/64`); or edit `server.conf`: `server-ipv6 fdab:82a1:6c44:40::/64` |
| OpenVPN fails to start: `invalid network/netmask combination` | `server` directive received CIDR notation (`172.22.80.0/20`) instead of plain network | Reinstall with latest script; or edit `server.conf`: `server 172.22.80.0 255.255.240.0` |
| OpenVPN `Failed to start openvpn@server.service` on RHEL 8+ | RHEL 8+ uses `openvpn-server@server` unit name, not `openvpn@server` | Reinstall with latest script (auto-detects service name); or: `systemctl start openvpn-server@server` |
| All L2TP users get "authentication failed" immediately after setup | PSK was never written to `ipsec.secrets` (grep matched header comment) | Reinstall with latest script; or manually add `%any %any : PSK "yourpsk"` to `/etc/ipsec.secrets` and run `ipsec reload` |
| WireGuard: re-adding a user causes duplicate `[Peer]` block in `wg0.conf` | Old peer block not removed before appending new one | Reinstall with latest script; or manually remove the duplicate `[Peer]` block from `/etc/wireguard/wg0.conf` and run `systemctl restart wg-quick@wg0` |
| WireGuard: new user added but cannot connect (peer not active on interface) | `wg addconf` hot-reload failed silently; peer in config but not loaded | Run `systemctl restart wg-quick@wg0` to reload config from file |
| After updating PSK, IKEv2 certificate profiles stop working for all users | PSK-only update was regenerating cert mobileconfigs with a blank P12 password | Reinstall with latest script; or re-run **Update user** with each user's password to regenerate the cert profiles correctly |
| `connection_info.txt` shows blank password after PSK update | PSK-only update regenerated connection info without access to plaintext password | Expected behaviour in latest script (shows `[unchanged]` placeholder); re-run **Update user** with the password to get a populated file |
| Management menu warns "SERVER_ADDRESS looks corrupt" on startup | State file has a bad value (e.g. `SERVER_ADDRESS=1`) | Go to **Management Menu → 2) Change Server Address** to reset the value, then regenerate profiles |
| Adding many users via batch/CSV is slow — services restart after every user | `skip_restart` not propagated to L2TP and OpenVPN add functions | Reinstall with latest script; batch add now does a single restart per service after all users are written |
| PSK with `\|`, `&`, or `\` silently not saved to state file | `save_state()` used `\|` as sed delimiter; special chars in value corrupt the substitution | Fixed in latest script — `sed_escape_replacement()` now applied to value before write |
| OpenVPN auth: user with regex username (e.g. `.*`) could match wrong credential line in `verify.sh` | BRE `grep "^${USERNAME}:"` treats username as a pattern | Fixed — `grep -F` used in auth script; username treated as literal string |
| Removing a port forwarding rule removes the wrong rule | BRE `grep -v "^${rule}$"` — dots in IP addresses are wildcards | Fixed — `grep -Fv` used for fixed-string rule matching |
| L2TP connects then drops | Firewall blocking ESP packets | Open protocol `50` (ESP) and `51` (AH) in cloud firewall |
| WireGuard: no internet | NAT not working | Check `iptables -t nat -L -n`, verify `ip_forward` is `1` |
| `xl2tpd` not found (RHEL) | EPEL not enabled | Script installs EPEL automatically; check `dnf repolist` |
| Uninstalling IKEv2 broke L2TP (or vice versa) | Old script removed shared `ipsec.conf`/`ipsec.secrets` when uninstalling one protocol | Fixed — uninstall now only removes protocol-specific entries; shared strongSwan files/packages are kept when the other protocol is still installed |
| OpenVPN auth broken on RHEL: `Permission denied` on `users.passwd` | Auth directory owned by `root:nogroup` but RHEL uses `nobody` group | Fixed — script detects RHEL and uses `root:nobody` |
| IKEv2 with Let's Encrypt: stuck connecting, no `AUTH_FAILED` error | Certbot 2.0+ defaults to ECDSA keys; `ipsec.secrets` was hardcoded to `: RSA server.key` — strongSwan can't load an EC key as RSA | Fixed — script auto-detects LE key type (RSA or ECDSA) and writes the correct declaration in `ipsec.secrets`; deploy hook also detects on each renewal |
| strongSwan `unable to bind socket: Address already in use` (Ubuntu 24.04) | Two strongSwan services fighting over ports 500/4500: `strongswan.service` (swanctl) and `strongswan-starter.service` (ipsec.conf) | Fixed — script detects and uses the correct service; masks the swanctl-based service to prevent conflicts |
| Post-install validation says strongSwan is down on Ubuntu 24.04 even though IKE ports are listening and `ipsec statusall` is healthy | `strongswan-starter.service` is a transient starter unit and becomes `inactive` after launching `charon`, so `systemctl is-active` is a false signal | Fixed — validation now treats starter-based installs as healthy when `charon` is running, even if the starter unit itself is transiently `inactive` |
| User creation prints `sed: ... unterminated 's' command` while saving state or assigning per-user IPs | `save_state()` updated existing keys with inline `sed -i "s|...|...|"`, which is fragile when values or generated data interact badly with sed replacement parsing | Fixed — `save_state()` now rewrites the state file with `awk` instead of substitution-based `sed` |
| IKEv2/L2TP IPsec is down after first-run user creation on Ubuntu 24.04 even though the install reached validation | Raw `ipsec restart` calls on the starter-based path can leave stale `charon`/starter pid files behind; later starts think the daemon is still running when it is not | Fixed — strongSwan restarts now go through a helper that stops starter cleanly, removes stale pid files, and starts the correct service again |
| Adding or removing users prints `sed: -e expression #1, char 21: unterminated 's' command` before editing `ipsec.secrets`, `chap-secrets`, or per-user conn blocks | `sed_escape_pattern()` tried to escape BRE metacharacters by piping through an invalid `sed` expression, so the helper itself failed before returning the escaped username | Fixed — `sed_escape_pattern()` now uses pure Bash escaping for `\`, `/`, `.`, `*`, `[`, `]`, `^`, and `$`, avoiding recursive reliance on `sed` |
| `state.conf` becomes readable by non-root users after menu actions that update state | Rewriting the file through a temp path can drop the original `0600` mode if the new file inherits a looser umask before replace | Fixed — `save_state()` re-applies `chmod 600` after swapping in the rewritten file |
| Opening status/validation screens on Ubuntu 24.04 unexpectedly changes the strongSwan service layout or still shows `inactive` while IKE works | Service discovery was mutating host state by masking `strongswan`, and the summary screen still trusted `systemctl is-active strongswan-starter` | Fixed — service detection is now read-only, masking happens only in install/restart paths, and the summary uses the same starter-aware health check as validation |
| Let's Encrypt renewal succeeds but IKEv2/L2TP keeps serving the old certificate until a manual restart | The generated certbot deploy hook called `restart_strongswan`, but that function does not exist inside the standalone hook script | Fixed — the deploy hook now contains its own strongSwan restart logic, including the Ubuntu 24.04 starter-based recovery path |
| OpenVPN username/password auth fails even though `verify.sh` and `users.passwd` exist | OpenVPN drops to `nobody:nogroup` or `nobody:nobody`, but `verify.sh` was still owned by `root:root`, so the dropped-privilege process could fail to execute it | Fixed — `verify.sh` now inherits the same group ownership as the auth directory and password file |
| Creating a new user can leave VPN backends and `state.conf` out of sync after a mid-flight failure | `create_vpn_user()` did not stop on per-VPN add failures, so a failed WireGuard/OpenVPN add could still register the user and generate profiles | Fixed — user creation now aborts on backend failures and rolls back earlier protocol additions before touching shared state |
| Auto-detected "server IP" can become a private RFC1918 address when public IP lookup services fail | The fallback path used the source IP from `ip route get`, which is often a private interface address on cloud/NAT hosts rather than the true public IP | Fixed — fallback addresses are now accepted only when they are public IPv4 addresses |
| Interrupted or non-interactive runs can spin forever at top-level prompts | Major prompt loops validated empty variables but did not check whether `read` itself hit EOF | Fixed — the main setup wizard and top-level management prompt now abort cleanly when stdin closes instead of looping forever |
| CentOS Stream 10 validates strongSwan as failed even though services and ports are healthy | EL10 stores live strongSwan config under `/etc/strongswan/`, may not expose an `ipsec` CLI in `PATH`, and still reports loaded connections through `swanctl`; the old validator assumed `/etc/ipsec.*`, `ipsec statusall`, and `iproute2` everywhere | Fixed — the script now routes strongSwan config/secrets by distro, treats starter-based installs as healthy when `charon` is running, falls back to `swanctl --list-conns` / `swanctl --load-all` when `ipsec` is unavailable, and installs `iproute` on RHEL-family systems |
| OpenVPN starts on Ubuntu/Debian but fails on RHEL 8+/CentOS Stream 10 with `Error opening configuration file: server.conf` | `openvpn-server@server` runs from `/etc/openvpn/server` and expects `server.conf` there, while Debian-family `openvpn@server` expects `/etc/openvpn/server.conf` | Fixed — the script now detects the OpenVPN service name first and writes/edits the config at the matching path |

</details>

---

<details>
<summary><strong>🛡️ Security Considerations</strong></summary>
<br>

### What the script does to harden the server

- Enables `rp_filter = 0` (required for VPN routing), disables ICMP redirects
- Sets `accept_redirects = 0` and `send_redirects = 0` to prevent routing attacks
- OpenVPN uses `tls-crypt` (pre-shared HMAC key) to authenticate TLS handshakes before any certificate exchange — protects against DoS and scanning
- OpenVPN enforces `remote-cert-tls client` to prevent MITM
- IKEv2 uses AES-256-GCM with PFS (Perfect Forward Secrecy) via ECP-384
- Passwords are **never stored in plaintext** for OpenVPN (SHA-256 hash only)
- **IPv6 leak prevention** — when IPv6 is disabled, `ip6tables FORWARD DROP` policy blocks all IPv6 forwarding so traffic cannot leak around the tunnel on dual-stack networks
- WireGuard and OpenVPN use **separate IPv6 subnets** (`fdab:82a1:6c44:30::/64` and `fdab:82a1:6c44:40::/64`) to prevent address collisions when both are installed
- **Default DROP policies** — `iptables -P INPUT DROP` and `iptables -P FORWARD DROP` are set after allowing SSH, loopback, and established connections, so any traffic not explicitly permitted is blocked
- **L2TP uses SHA2 ciphers** — IKE and ESP proposals include AES-256-SHA2_256 as the preferred option, with SHA1 and 3DES retained for legacy client compatibility
- **Port forwarding deduplication** — `iptables -C` check prevents duplicate DNAT/FORWARD rules if the same port forwarding rule is added twice
- **Port 80 cleanup on interrupt** — a trap ensures the temporary port 80 firewall rule opened for Let's Encrypt HTTP-01 challenges is removed even if the script is interrupted mid-certbot

### What you should do additionally

- **Restrict SSH**: Limit SSH access to known IPs, use key-based auth only
- **Cloud firewall**: Open only the specific UDP ports listed above — do not open all ports
- **Rotate the CA** periodically if operating in a high-security environment (requires re-issuing all certs)
- **Monitor logs**: `/var/log/openvpn.log`, `journalctl -u strongswan`, `journalctl -u wg-quick@wg0`
- **Backup** `/etc/vpn-setup/` and `/etc/vpn-profiles/` — these contain all keys and credentials

### Certificate validity

All certificates are issued for **10 years** (3650 days). For production environments with stricter requirements, edit `CERT_DAYS` at the top of the script before running.

### L2TP PSK note

The L2TP pre-shared key is a **server-wide** secret — all L2TP clients use the same PSK. This is standard L2TP/IPsec design. Per-user authentication is handled by PPP CHAP (username/password). Avoid using easily-guessable PSKs.

</details>

---

<details>
<summary><strong>📦 What Gets Installed</strong></summary>
<br>

The script installs only what is needed for the VPN types you select:

| Package | Purpose | Installed when |
|---------|---------|----------------|
| `strongswan` | IKEv2 and L2TP/IPsec daemon | IKEv2 or L2TP selected |
| `libstrongswan-extra-plugins` | EAP-MSCHAPv2 support | Debian/Ubuntu + IKEv2 |
| `strongswan-plugin-eap-mschapv2` | EAP-MSCHAPv2 support | Older RHEL-family releases where the plugin is split from `strongswan` |
| `xl2tpd` | L2TP daemon | L2TP selected |
| `ppp` | PPP for L2TP user auth | L2TP selected |
| `wireguard-tools` | WireGuard CLI | WireGuard selected |
| `openvpn` | OpenVPN daemon | OpenVPN selected |
| `openssl` | Certificate generation | Always |
| `curl` | Public IP detection | Always |
| `python3` | WireGuard peer removal helper | Always |
| `iptables-persistent` | Firewall rule persistence | Debian/Ubuntu |
| `iptables-services` | Firewall rule persistence | RHEL/CentOS |
| `epel-release` | Extra packages repository | RHEL-based + L2TP |

</details>

---

<details>
<summary><strong>🏗️ Script Architecture</strong></summary>
<br>

The script is organized into logical sections within a single `vpn-setup.sh` file (~5,900 lines):

```
vpn-setup.sh
├── Constants & IP ranges
├── Color output & UI helpers
├── Utility functions
│   ├── UUID generation
│   ├── String escaping (escape_ipsec, escape_ppp, sed_escape_pattern, sed_escape_replacement)
│   ├── IP increment / next-IP tracking
│   ├── iptables helpers (fw_add, fw_delete, save_iptables)
│   └── get_openvpn_svc()  — detects openvpn@server vs openvpn-server@server, cached
├── OS detection (apt / dnf / yum)
├── State management (KEY=VALUE, /etc/vpn-setup/state.conf)
├── Setup wizard (7 interactive questions + LE email when DNS hostname given)
├── System preparation
│   ├── Package update
│   ├── Dependency installation
│   ├── IP forwarding (sysctl)
│   └── Base iptables rules + NAT
├── Certificate generation (CA → server → per-user → P12)
├── Let's Encrypt support
│   ├── validate_dns_resolves()  — checks hostname → server IP before attempting
│   ├── install_certbot()        — apt / dnf / yum
│   ├── obtain_letsencrypt_cert() — certbot standalone HTTP-01, copies to CERTS_DIR
│   ├── _write_le_deploy_hooks() — deploy/pre/post hooks under /etc/letsencrypt/renewal-hooks/
│   └── is_letsencrypt()         — helper, reads CERT_TYPE from state
├── VPN installation
│   ├── install_ikev2()     → ipsec.conf, ipsec.secrets, firewall
│   ├── install_l2tp()      → xl2tpd.conf, ppp options, chap-secrets
│   ├── install_wireguard() → wg0.conf, server key pair
│   └── install_openvpn()   → server.conf, ta.key, dh.pem, verify.sh (service name auto-detected)
├── User management
│   ├── create_vpn_user()   → adds to all installed VPNs
│   ├── remove_vpn_user()   → removes from all + deletes profiles
│   └── per-VPN add/remove  — all credential writes use delete-before-add, sed patterns escaped
├── Profile generation
│   ├── IKEv2 EAP mobileconfig (Apple; CA payload omitted in LE mode)
│   ├── IKEv2 certificate mobileconfig (Apple, with embedded P12; CA payload omitted in LE mode)
│   ├── strongSwan .sswan (Android, EAP + certificate variants)
│   ├── PowerShell setup script (Windows)
│   ├── WireGuard .conf (with client keys embedded)
│   ├── OpenVPN .ovpn (LE trust bundle with root CA, or own CA in <ca> block depending on CERT_TYPE)
│   └── Plain-text connection info
├── Management menu (re-run detection)
│   ├── User management
│   │   ├── Add single user
│   │   ├── Batch add (interactive loop / CSV import)
│   │   ├── Remove user
│   │   ├── Update user(s) (single / bulk CSV)
│   │   ├── Export user list (CSV template)
│   │   └── List users with IPs and profile counts
│   ├── Server address change
│   ├── DNS change
│   ├── Update / Uninstall
│   ├── Validate & fix services (with auto-remediation)
│   └── Advanced options
│       ├── Split tunneling
│       ├── Subnet access
│       ├── Port forwarding
│       ├── Let's Encrypt renewal (shown only when CERT_TYPE=letsencrypt)
│       └── IPv6 disable
├── Post-install validation (§33)
│   ├── check_port_listening()     — ss/netstat UDP port check
│   ├── validate_ikev2()           — service, ports 500/4500, ipsec connections, cert, NAT
│   ├── validate_l2tp()            — xl2tpd, port 1701, strongSwan, L2TP-PSK conn, PSK in secrets
│   ├── validate_wireguard()       — service, port 51820, wg0 interface, config file
│   ├── validate_openvpn()         — service, port 1194, tun0, config, verify.sh, cert EKU
│   └── validate_vpn_installation() — orchestrator, IPv4 forwarding, CA cert expiry
└── main() — detects first run vs re-run
```

### Key design principles

- **No `set -e`** — errors are handled explicitly with `|| { print_error "..."; exit 1; }` for critical operations and `|| true` for best-effort ones
- **State-driven** — all configuration is driven from `/etc/vpn-setup/state.conf`; the script can be interrupted and re-run safely
- **Non-destructive** — existing config files are backed up with timestamps before being overwritten
- **Idempotent iptables** — all `fw_add` calls check with `iptables -C` before adding, preventing duplicate rules
- **Delete-before-add credential writes** — `ipsec.secrets`, `chap-secrets`, and `users.passwd` are updated by deleting the old line then appending the new one; no `sed s|...|user_value|` patterns that could be broken by special characters in passwords
- **sed injection safety** — all `sed` patterns that include usernames or other user-controlled data are run through `sed_escape_pattern()` to escape BRE metacharacters (`.`, `*`, `[`, `]`, etc.)
- **Linux-safe line endings** — `.gitattributes` forces `LF` for shell scripts, configs, docs, and PowerShell output files so uploads to Linux hosts don't break on `CRLF`

</details>

---

## 📋 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

Made with ❤️ for sysadmins who don't want to manage four separate VPN scripts.

</div>

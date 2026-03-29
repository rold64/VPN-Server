<div align="center">

# 🔐 VPN Server Setup Script

**A single, comprehensive bash script to install and configure four VPN protocols on any Linux server.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue?style=flat-square)](https://github.com/rold64/VPN-Server)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.0%2B-orange?style=flat-square)](https://www.gnu.org/software/bash/)
[![Platforms](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian%20%7C%20RHEL%20%7C%20Fedora-lightgrey?style=flat-square)](#-supported-operating-systems)

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
- 🏗️ **Self-signed PKI** — auto-generates a full certificate authority with 10-year validity; no external CA needed
- 🌍 **Let's Encrypt support** — when a DNS hostname is used, obtains a trusted LE certificate automatically via certbot HTTP-01; falls back to self-signed if LE fails; auto-renews via certbot's systemd timer/cron

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

The script walks you through **7 setup questions**, then handles everything automatically:

| Step | Question |
|------|----------|
| 1 | Which VPN servers to install (IKEv2, L2TP, WireGuard, OpenVPN, or All) |
| 2 | Server address: DNS hostname or auto-detected public IP |
| 3 | Enable IPv6? (IPv4 is always on) |
| 4 | Which DNS resolvers to push to clients (pick up to 2) |
| 5 | First user's username |
| 6 | First user's password |
| 7 | Pre-shared key (used for IKEv2 PSK mode and L2TP/IPsec) |

After answering, the script runs fully automatically — no further interaction needed until it's done.

---

## 🖥️ Supported Operating Systems

| Distribution | Versions | Package Manager |
|---|---|---|
| Ubuntu | 20.04, 22.04, 24.04 | `apt` |
| Debian | 10, 11, 12 | `apt` |
| CentOS | 7, 8 | `yum` / `dnf` |
| Rocky Linux | 8, 9 | `dnf` |
| AlmaLinux | 8, 9 | `dnf` |
| Fedora | 36+ | `dnf` |
| Amazon Linux | 2, 2023 | `yum` / `dnf` |

**Architectures:** `x86_64`, `arm64`, `armv7`

> EPEL is automatically installed on RHEL-based systems when required (e.g. for `xl2tpd`).

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
Profiles  : /etc/VPN User Profiles

Management Options:

  1) Add / Remove VPN user(s)
  2) Change Server DNS name / IP
  3) Change VPN DNS resolver(s)
  4) Update VPN servers
  5) Uninstall VPN server(s)
  6) Advanced
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

**Add a user** — prompts for username, password, and PSK → creates credentials across all installed VPNs and generates all profile files.

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

**Export user list** — writes a CSV template to `/etc/VPN User Profiles/users_export.csv` with all current usernames. Passwords are not stored — fill them in and use "Import from CSV" to re-provision or migrate users.

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
| Client IP pool | `10.10.10.10` – `10.10.10.250` |
| Server IP | `10.10.10.1` |
| Ports | UDP `500`, UDP `4500` (NAT-T) |
| Ciphers | AES-256-GCM, SHA2-256/512, ECP-384 |

Two separate connection profiles are maintained in `ipsec.conf`:
- `conn ikev2-eap` — EAP-MSCHAPv2, username/password via `ipsec.secrets`
- `conn ikev2-cert` — Certificate-based, uses the per-user client certificate

Credentials are stored in `/etc/ipsec.secrets`:
```
username : EAP "password"
: RSA server.key
```

---

### L2TP / IPsec

| Property | Value |
|----------|-------|
| Software | xl2tpd + strongSwan (IKEv1) |
| Auth methods | IPsec PSK (tunnel) + PPP CHAP (username/password) |
| Client IP pool | `192.168.42.10` – `192.168.42.250` |
| Server IP | `192.168.42.1` |
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
| Client IP pool | `10.20.20.2`, `10.20.20.3`, … |
| Server IP | `10.20.20.1` |
| Port | UDP `51820` |

Each user gets a unique key pair generated automatically. A pre-shared key (PSK) is also generated per-peer for additional security. The client's public key is hot-added to the running WireGuard interface — no restart needed.

Key files stored per user: `wg_client.key`, `wg_client.pub`, `wg_client.psk`

---

### OpenVPN

| Property | Value |
|----------|-------|
| Auth methods | Certificate **and** username/password (both required simultaneously) |
| Client IP pool | `10.8.0.2`, `10.8.0.3`, … |
| Server IP | `10.8.0.1` |
| Port | UDP `1194` |
| Cipher | AES-256-GCM |
| TLS | TLS 1.2+, `tls-crypt` HMAC authentication |

Passwords are stored as **SHA-256 hashes** in `/etc/openvpn/auth/users.passwd`. A custom verification script (`/etc/openvpn/auth/verify.sh`) handles authentication — no PAM, no system users required.

Per-user client configuration files (CCD) assign a fixed IP to each user.

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

For each user, profile files are generated in:

```
/etc/VPN User Profiles/
└── alice/
    ├── alice_ikev2_eap.mobileconfig      ← Apple: IKEv2 username/password
    ├── alice_ikev2_cert.mobileconfig     ← Apple: IKEv2 certificate auth
    ├── alice_ikev2.sswan                 ← Android: strongSwan EAP (user/pass)
    ├── alice_ikev2_cert.sswan            ← Android: strongSwan certificate
    ├── alice_ikev2_windows.ps1           ← Windows: PowerShell setup script
    ├── alice_wireguard.conf              ← WireGuard client config
    ├── alice_openvpn.ovpn               ← OpenVPN config (certs embedded)
    ├── alice_client_cert.p12            ← PKCS#12 certificate bundle
    ├── alice_ca.crt                     ← CA certificate
    └── alice_connection_info.txt        ← All credentials & manual setup guide
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

Access via **Management Menu → 6 → Advanced**:

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
Client IP  : 10.20.20.3     ← WireGuard / OpenVPN client IP
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
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE  # IKEv2
iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o eth0 -j MASQUERADE # L2TP
iptables -t nat -A POSTROUTING -s 10.20.20.0/24 -o eth0 -j MASQUERADE  # WireGuard
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE    # OpenVPN
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
WG_NEXT_IP=10.20.20.5
OVPN_NEXT_IP=10.8.0.5
WG_IP_alice=10.20.20.2
OVPN_IP_alice=10.8.0.2
SPLIT_TUNNELING=full
SERVER_SUBNET_ACCESS=enabled:192.168.1.0/24
CLIENT_SUBNET_ACCESS=disabled
PORT_FORWARDING_RULES=tcp:8080->10.20.20.3:3000
SETUP_DATE=2025-01-15 14:32:00
CERT_TYPE=letsencrypt
LE_DOMAIN=vpn.example.com
LE_EMAIL=admin@example.com
OPENVPN_SERVICE=openvpn@server
```

> ⚠️ This file contains the L2TP PSK and other sensitive data. It is created with `chmod 600` and readable only by root.

| Key | Values | Purpose |
|-----|--------|---------|
| `CERT_TYPE` | `letsencrypt` / `self-signed` | Set during install; controls profile and cert behaviour on re-run |
| `LE_DOMAIN` | FQDN | DNS hostname that the LE cert was issued for |
| `LE_EMAIL` | email | Address used for certbot registration / expiry notices |
| `OPENVPN_SERVICE` | `openvpn@server` / `openvpn-server@server` | Detected at install time; `openvpn-server@server` on RHEL 8+ |

</details>

---

<details>
<summary><strong>🔍 Troubleshooting</strong></summary>
<br>

### Check service status

```bash
# IKEv2 / L2TP (strongSwan)
sudo systemctl status strongswan
sudo ipsec status

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
ping 10.10.10.1

# Ping L2TP server
ping 192.168.42.1

# Ping WireGuard server
ping 10.20.20.1

# Ping OpenVPN server
ping 10.8.0.1
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

If you need to re-generate profile files (e.g. after changing the server address), use the Update user option with the same credentials — or remove and re-add the user. The CA and server certificate are preserved — only user certs are regenerated.

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
| OpenVPN fails to start: `network must be between /64 and /124` | IPv6 tunnel subnet used `/48` prefix | Reinstall with latest script (uses `/64`); or edit `server.conf`: `server-ipv6 fddd:2c4:2c4:2c4::/64` |
| OpenVPN fails to start: `invalid network/netmask combination` | `server` directive received CIDR notation (`10.8.0.0/24`) instead of plain network | Reinstall with latest script; or edit `server.conf`: `server 10.8.0.0 255.255.255.0` |
| OpenVPN `Failed to start openvpn@server.service` on RHEL 8+ | RHEL 8+ uses `openvpn-server@server` unit name, not `openvpn@server` | Reinstall with latest script (auto-detects service name); or: `systemctl start openvpn-server@server` |
| All L2TP users get "authentication failed" immediately after setup | PSK was never written to `ipsec.secrets` (grep matched header comment) | Reinstall with latest script; or manually add `%any %any : PSK "yourpsk"` to `/etc/ipsec.secrets` and run `ipsec reload` |
| WireGuard: re-adding a user causes duplicate `[Peer]` block in `wg0.conf` | Old peer block not removed before appending new one | Reinstall with latest script; or manually remove the duplicate `[Peer]` block from `/etc/wireguard/wg0.conf` and run `systemctl restart wg-quick@wg0` |
| L2TP connects then drops | Firewall blocking ESP packets | Open protocol `50` (ESP) and `51` (AH) in cloud firewall |
| WireGuard: no internet | NAT not working | Check `iptables -t nat -L -n`, verify `ip_forward` is `1` |
| `xl2tpd` not found (RHEL) | EPEL not enabled | Script installs EPEL automatically; check `dnf repolist` |

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

### What you should do additionally

- **Restrict SSH**: Limit SSH access to known IPs, use key-based auth only
- **Cloud firewall**: Open only the specific UDP ports listed above — do not open all ports
- **Rotate the CA** periodically if operating in a high-security environment (requires re-issuing all certs)
- **Monitor logs**: `/var/log/openvpn.log`, `journalctl -u strongswan`, `journalctl -u wg-quick@wg0`
- **Backup** `/etc/vpn-setup/` and `/etc/VPN User Profiles/` — these contain all keys and credentials

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
| `strongswan-plugin-eap-mschapv2` | EAP-MSCHAPv2 support | RHEL + IKEv2 |
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

The script is organized into logical sections within a single `vpn-setup.sh` file (~5,350 lines):

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
│   ├── OpenVPN .ovpn (LE chain or own CA in <ca> block depending on CERT_TYPE)
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
│   └── Advanced options
│       ├── Split tunneling
│       ├── Subnet access
│       ├── Port forwarding
│       ├── Let's Encrypt renewal (shown only when CERT_TYPE=letsencrypt)
│       └── IPv6 disable
└── main() — detects first run vs re-run
```

### Key design principles

- **No `set -e`** — errors are handled explicitly with `|| { print_error "..."; exit 1; }` for critical operations and `|| true` for best-effort ones
- **State-driven** — all configuration is driven from `/etc/vpn-setup/state.conf`; the script can be interrupted and re-run safely
- **Non-destructive** — existing config files are backed up with timestamps before being overwritten
- **Idempotent iptables** — all `fw_add` calls check with `iptables -C` before adding, preventing duplicate rules
- **Delete-before-add credential writes** — `ipsec.secrets`, `chap-secrets`, and `users.passwd` are updated by deleting the old line then appending the new one; no `sed s|...|user_value|` patterns that could be broken by special characters in passwords
- **sed injection safety** — all `sed` patterns that include usernames or other user-controlled data are run through `sed_escape_pattern()` to escape BRE metacharacters (`.`, `*`, `[`, `]`, etc.)

</details>

---

## 📋 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

Made with ❤️ for sysadmins who don't want to manage four separate VPN scripts.

</div>

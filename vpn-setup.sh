#!/usr/bin/env bash
#==============================================================================
# VPN Server Setup Script v1.0.0
# Supports: IKEv2/IPsec, L2TP/IPsec, WireGuard, OpenVPN
# Auth:     IKEv2 (EAP + Certificate), L2TP (PSK + PPP), WireGuard (Keys),
#           OpenVPN (Certificate + Username/Password)
# OS:       Ubuntu/Debian, RHEL/CentOS/Rocky/Alma/Oracle, Fedora
#==============================================================================

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="VPN Server Setup"

#==============================================================================
# TABLE OF CONTENTS
#   Search: §N  (e.g. grep -n '§15' vpn-setup.sh)
#------------------------------------------------------------------------------
#  §1   Constants & directory paths                        ~line   54
#  §2   Colors & output functions                         ~line  104
#  §3   Utility functions                                 ~line  188
#  §4   OS detection                                      ~line  365
#  §5   State management                                  ~line  479
#  §6   Service management                                ~line  595
#  §7   Firewall helpers (iptables)                       ~line  645
#  §8   Root check & pre-flight                           ~line  702
#  §9   Public IP detection                               ~line  714
#  §10  DNS configuration maps                            ~line  757
#  §11  Setup wizard — gathering information              ~line  862
#  §12  System preparation: deps, IP forward, firewall    ~line 1138
#  §13  Let's Encrypt certificate support                 ~line 1273
#  §14  Certificate generation (OpenSSL, self-signed)     ~line 1432
#  §15  IKEv2 installation & configuration (strongSwan)   ~line 1615
#  §16  L2TP/IPsec installation & configuration           ~line 1863
#  §17  WireGuard installation & configuration            ~line 2083
#  §18  OpenVPN installation & configuration              ~line 2318
#  §19  User management (add / remove / update)           ~line 2613
#  §20  Profile generation (mobileconfig, ovpn, wg, ps1)  ~line 2699
#  §21  Re-run management menu                            ~line 3472
#  §22  User management menu                              ~line 3525
#  §23  Change server address                             ~line 4292
#  §24  Change DNS resolvers                              ~line 4439
#  §25  Update VPN servers                                ~line 4535
#  §26  Uninstall VPN servers                             ~line 4591
#  §27  Advanced menu                                     ~line 4717
#  §28  Advanced: split tunneling                         ~line 4775
#  §29  Advanced: access VPN server's subnet              ~line 4905
#  §30  Advanced: access VPN clients from subnet          ~line 4983
#  §31  Advanced: port forwarding to VPN clients          ~line 5044
#  §32  Advanced: disable IPv6                            ~line 5217
#  §33  Post-install validation                           ~line 5390
#  §34  First run setup orchestrator                      ~line 5630
#  §35  Main entry point                                  ~line 5770
#==============================================================================

#==============================================================================
# §1  CONSTANTS & DIRECTORY PATHS
#==============================================================================

STATE_DIR="/etc/vpn-setup"
STATE_FILE="${STATE_DIR}/state.conf"
CERTS_DIR="${STATE_DIR}/certs"
PROFILES_BASE="/etc/vpn-profiles"
OPENVPN_DIR="/etc/openvpn"
LE_CERTS_BASE="/etc/letsencrypt/live"

# VPN IP Ranges
IKEV2_SERVER_IP="10.10.10.1"
IKEV2_SUBNET="10.10.10.0/24"
IKEV2_POOL_START="10.10.10.10"
IKEV2_POOL_END="10.10.10.250"
IKEV2_POOL="${IKEV2_POOL_START}-${IKEV2_POOL_END}"

L2TP_SERVER_IP="192.168.42.1"
L2TP_SUBNET="192.168.42.0/24"
L2TP_POOL_START="192.168.42.10"
L2TP_POOL_END="192.168.42.250"
L2TP_POOL="${L2TP_POOL_START}-${L2TP_POOL_END}"

WG_SERVER_IP="10.20.20.1"
WG_SUBNET="10.20.20.0/24"
WG_FIRST_CLIENT="10.20.20.2"
WG_POOL_END="10.20.20.254"

OVPN_SERVER_IP="10.8.0.1"
OVPN_SUBNET="10.8.0.0/24"
OVPN_FIRST_CLIENT="10.8.0.2"
OVPN_POOL_END="10.8.0.254"

# Ports
IKEV2_PORT="500"
IKEV2_NAT_PORT="4500"
L2TP_PORT="1701"
WG_PORT="51820"
OVPN_PORT="1194"

# Certificate validity (10 years)
CERT_DAYS=3650

# VPN type identifiers
VPN_IKEV2="ikev2"
VPN_L2TP="l2tp"
VPN_WG="wireguard"
VPN_OVPN="openvpn"

#==============================================================================
# §2  COLORS & OUTPUT FUNCTIONS
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║         ${SCRIPT_NAME} v${SCRIPT_VERSION}          ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}${BOLD}── $1 ──────────────────────────────────────────────────${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC}   $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERR]${NC}  $1" >&2
}

print_step() {
    echo -e "${CYAN}  ➤${NC}  $1"
}

print_done() {
    echo -e "${GREEN}  ✔${NC}  $1"
}

print_prompt() {
    echo -e "${YELLOW}  ?${NC}  $1"
}

ask_yn() {
    # Usage: ask_yn "Question?" [default: y/n]
    local question="$1"
    local default="${2:-y}"
    local options
    if [ "$default" = "y" ]; then
        options="[Y/n]"
    else
        options="[y/N]"
    fi
    while true; do
        echo -en "${YELLOW}  ?${NC}  ${question} ${DIM}${options}${NC} "
        read -r reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) print_warning "Please answer y or n." ;;
        esac
    done
}

press_enter() {
    echo ""
    echo -en "${DIM}  Press Enter to continue...${NC}"
    read -r
}

#==============================================================================
# §3  UTILITY FUNCTIONS
#==============================================================================

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:lower:]' '[:upper:]'
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]'
    else
        # Fallback: generate pseudo-UUID from /dev/urandom
        od -x /dev/urandom | head -1 | awk '{OFS="-"; print toupper($2$3), toupper($4), toupper($5), toupper($6), toupper($7$8$9)}'
    fi
}

# Escape a string for use in ipsec.secrets quoted values
# Escapes: \ → \\  and  " → \"
escape_ipsec() {
    local val="$1"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    printf '%s' "$val"
}

# Escape a string for use in chap-secrets quoted values
# Escapes: \ → \\  and  " → \"
escape_ppp() {
    local val="$1"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    printf '%s' "$val"
}

# Escape a string for use as a BRE pattern in sed (not for replacements)
# Escapes: . * [ ] ^ $ \  /
sed_escape_pattern() {
    printf '%s' "$1" | sed 's/[]\[.*^$\\\/]/\\&/g'
}

# Escape a string for use in the replacement part of a sed s/// command
# (delimiter is |) — escapes: \  &  and |
sed_escape_replacement() {
    local val="$1"
    val="${val//\\/\\\\}"
    val="${val//&/\\&}"
    val="${val//|/\\|}"
    printf '%s' "$val"
}

# Hash a password with SHA-256 for OpenVPN credentials file
hash_password() {
    local password="$1"
    printf '%s' "$password" | sha256sum | awk '{print $1}'
}

# Base64 encode a file (single line, no wrapping)
b64_file() {
    base64 -w 0 "$1" 2>/dev/null || base64 "$1"
}

# Base64-encode a PEM certificate as DER (required for Apple mobileconfig <data> elements)
b64_cert() {
    openssl x509 -in "$1" -outform DER 2>/dev/null | base64 -w 0 2>/dev/null || \
    openssl x509 -in "$1" -outform DER 2>/dev/null | base64
}

# Check if a value is in a comma-separated list
in_list() {
    local needle="$1"
    local haystack="$2"
    echo "$haystack" | tr ',' '\n' | grep -Fxq "$needle"
}

# Add a value to a comma-separated list (no duplicates)
add_to_list() {
    local item="$1"
    local list="$2"
    if [ -z "$list" ]; then
        echo "$item"
    elif in_list "$item" "$list"; then
        echo "$list"
    else
        echo "${list},${item}"
    fi
}

# Remove a value from a comma-separated list
remove_from_list() {
    local item="$1"
    local list="$2"
    echo "$list" | tr ',' '\n' | grep -Fxv "$item" | tr '\n' ',' | sed 's/,$//'
}

# Increment an IP address by 1
increment_ip() {
    local ip="$1"
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$ip"
    i4=$((i4 + 1))
    if [ "$i4" -gt 254 ]; then
        i4=2
        i3=$((i3 + 1))
    fi
    echo "${i1}.${i2}.${i3}.${i4}"
}

# Get the next available WireGuard client IP
next_wg_ip() {
    local current
    current=$(get_state "WG_NEXT_IP")
    if [ -z "$current" ]; then
        current="$WG_FIRST_CLIENT"
    fi
    # Sanity check: if the next IP has drifted outside the /24 pool, the pool is exhausted
    local pool_third="${WG_POOL_END%.*}"  # "10.20.20"
    local current_third="${current%.*}"
    if [ "$current_third" != "$pool_third" ]; then
        print_error "WireGuard IP pool exhausted (pool end: ${WG_POOL_END}). Cannot add more users."
        return 1
    fi
    local current_last="${current##*.}"
    if [ "$current_last" -gt "${WG_POOL_END##*.}" ]; then
        print_error "WireGuard IP pool exhausted (pool end: ${WG_POOL_END}). Cannot add more users."
        return 1
    fi
    echo "$current"
}

# Get the next available OpenVPN client IP
next_ovpn_ip() {
    local current
    current=$(get_state "OVPN_NEXT_IP")
    if [ -z "$current" ]; then
        current="$OVPN_FIRST_CLIENT"
    fi
    # Sanity check: if the next IP has drifted outside the /24 pool, the pool is exhausted
    local pool_third="${OVPN_POOL_END%.*}"  # "10.8.0"
    local current_third="${current%.*}"
    if [ "$current_third" != "$pool_third" ]; then
        print_error "OpenVPN IP pool exhausted (pool end: ${OVPN_POOL_END}). Cannot add more users."
        return 1
    fi
    local current_last="${current##*.}"
    if [ "$current_last" -gt "${OVPN_POOL_END##*.}" ]; then
        print_error "OpenVPN IP pool exhausted (pool end: ${OVPN_POOL_END}). Cannot add more users."
        return 1
    fi
    echo "$current"
}

# Check if a command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Run a command silently, print error on failure
run_silent() {
    local desc="$1"
    shift
    if ! "$@" &>/dev/null; then
        print_error "Failed: ${desc}"
        return 1
    fi
    return 0
}

# Run a command with output suppressed unless debug mode
run_quiet() {
    if [ "${VPN_DEBUG:-0}" = "1" ]; then
        "$@"
    else
        "$@" &>/dev/null
    fi
}

# Get the primary network interface name
get_primary_iface() {
    ip route | grep default | awk '{print $5}' | head -1
}
#==============================================================================
# §4  OS DETECTION
#==============================================================================

OS_ID=""
OS_VERSION=""
OS_LIKE=""
PKG_MANAGER=""
PKG_UPDATE=""
PKG_INSTALL=""
PKG_REMOVE=""
SVC_START="systemctl start"
SVC_STOP="systemctl stop"
SVC_RESTART="systemctl restart"
SVC_ENABLE="systemctl enable"
SVC_STATUS="systemctl status"
ARCH=""

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
    elif [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    else
        print_error "Cannot detect OS. Unsupported system."
        exit 1
    fi

    case "$OS_ID" in
        ubuntu|debian|raspbian)
            PKG_MANAGER="apt"
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            PKG_REMOVE="apt-get remove -y -qq"
            ;;
        centos|rhel|rocky|almalinux|ol|amzn)
            if cmd_exists dnf; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf check-update -q || true"
                PKG_INSTALL="dnf install -y -q"
                PKG_REMOVE="dnf remove -y -q"
            else
                PKG_MANAGER="yum"
                PKG_UPDATE="yum check-update -q || true"
                PKG_INSTALL="yum install -y -q"
                PKG_REMOVE="yum remove -y -q"
            fi
            ;;
        fedora)
            PKG_MANAGER="dnf"
            PKG_UPDATE="dnf check-update -q || true"
            PKG_INSTALL="dnf install -y -q"
            PKG_REMOVE="dnf remove -y -q"
            ;;
        alpine)
            PKG_MANAGER="apk"
            PKG_UPDATE="apk update -q"
            PKG_INSTALL="apk add -q"
            PKG_REMOVE="apk del -q"
            ;;
        *)
            # Try to determine from ID_LIKE
            if echo "$OS_LIKE" | grep -qi "debian\|ubuntu"; then
                PKG_MANAGER="apt"
                PKG_UPDATE="apt-get update -qq"
                PKG_INSTALL="apt-get install -y -qq"
                PKG_REMOVE="apt-get remove -y -qq"
                OS_ID="debian"
            elif echo "$OS_LIKE" | grep -qi "rhel\|fedora"; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf check-update -q || true"
                PKG_INSTALL="dnf install -y -q"
                PKG_REMOVE="dnf remove -y -q"
                OS_ID="rhel"
            else
                print_error "Unsupported OS: ${OS_ID}"
                exit 1
            fi
            ;;
    esac

    print_success "Detected OS: ${OS_ID} ${OS_VERSION} (Package manager: ${PKG_MANAGER})"
}

detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64)  ARCH="x86_64" ;;
        aarch64) ARCH="arm64"  ;;
        armv7*)  ARCH="armv7"  ;;
        armv6*)  ARCH="armv6"  ;;
        i386|i686) ARCH="i386" ;;
        *)
            print_warning "Unknown architecture: ${machine}. Continuing anyway."
            ARCH="$machine"
            ;;
    esac
    print_success "Detected architecture: ${ARCH}"
}

is_debian_based() {
    [ "$PKG_MANAGER" = "apt" ]
}

is_rhel_based() {
    [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "yum" ]
}

#==============================================================================
# §5  STATE MANAGEMENT
#==============================================================================

# Initialize the state directory and file
init_state() {
    mkdir -p "${STATE_DIR}" "${CERTS_DIR}/users"
    chmod 700 "${STATE_DIR}"
    if [ ! -f "$STATE_FILE" ]; then
        touch "$STATE_FILE"
        chmod 600 "$STATE_FILE"
    fi
}

# Save or update a key=value in the state file
save_state() {
    local key="$1"
    local value="$2"
    init_state
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        # Update existing key — escape value so |, &, \ don't corrupt the sed expression
        local escaped_value
        escaped_value=$(sed_escape_replacement "$value")
        sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$STATE_FILE"
    else
        # Add new key
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
}

# Get a value from the state file
get_state() {
    local key="$1"
    if [ -f "$STATE_FILE" ]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- | head -1
    fi
}

# Load all state variables into the current shell
load_all_state() {
    if [ -f "$STATE_FILE" ]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [ -z "$key" ] && continue
            # Export to current environment
            export "STATE_${key}=${value}"
        done < "$STATE_FILE"
        # Also load the common ones as regular variables
        INSTALLED_VPNS=$(get_state "INSTALLED_VPNS")
        SERVER_ADDRESS=$(get_state "SERVER_ADDRESS")
        ADDRESS_TYPE=$(get_state "ADDRESS_TYPE")
        IPV6_ENABLED=$(get_state "IPV6_ENABLED")
        DNS1=$(get_state "DNS1")
        DNS2=$(get_state "DNS2")
        DNS1_V6=$(get_state "DNS1_IPV6")
        DNS2_V6=$(get_state "DNS2_IPV6")
        USERS_LIST=$(get_state "USERS_LIST")
        L2TP_PSK=$(get_state "L2TP_PSK")
        WG_SERVER_PUBKEY=$(get_state "WG_SERVER_PUBKEY")
    fi
}

# Check if a VPN type is installed (per state file)
vpn_is_installed() {
    local vpn_type="$1"
    local installed
    installed=$(get_state "INSTALLED_VPNS")
    in_list "$vpn_type" "$installed"
}

# Check if we have a prior installation
has_prior_install() {
    [ -f "$STATE_FILE" ] && [ -n "$(get_state "INSTALLED_VPNS")" ]
}

# Add a VPN type to the installed list
mark_vpn_installed() {
    local vpn_type="$1"
    local current
    current=$(get_state "INSTALLED_VPNS")
    save_state "INSTALLED_VPNS" "$(add_to_list "$vpn_type" "$current")"
}

# Remove a VPN type from the installed list
mark_vpn_uninstalled() {
    local vpn_type="$1"
    local current
    current=$(get_state "INSTALLED_VPNS")
    save_state "INSTALLED_VPNS" "$(remove_from_list "$vpn_type" "$current")"
}

# Add a user to the users list in state
register_user() {
    local username="$1"
    local current
    current=$(get_state "USERS_LIST")
    save_state "USERS_LIST" "$(add_to_list "$username" "$current")"
}

# Remove a user from the users list in state
deregister_user() {
    local username="$1"
    local current
    current=$(get_state "USERS_LIST")
    save_state "USERS_LIST" "$(remove_from_list "$username" "$current")"
}

# Get list of users as a newline-separated list
get_users_list() {
    get_state "USERS_LIST" | tr ',' '\n' | grep -v '^$'
}

# Count users
count_users() {
    get_users_list | grep -c '.' || echo "0"
}

#==============================================================================
# §6  SERVICE MANAGEMENT
#==============================================================================

service_start() {
    local svc="$1"
    systemctl start "$svc" 2>/dev/null || true
}

service_stop() {
    local svc="$1"
    systemctl stop "$svc" 2>/dev/null || true
}

service_restart() {
    local svc="$1"
    systemctl restart "$svc" 2>/dev/null || true
}

service_enable() {
    local svc="$1"
    systemctl enable "$svc" 2>/dev/null || true
}

service_is_active() {
    local svc="$1"
    systemctl is-active "$svc" &>/dev/null
}

# Return the correct OpenVPN systemd service name for this OS.
# Debian/Ubuntu and RHEL 7 use openvpn@server; RHEL 8+ uses openvpn-server@server.
# Result is cached in _OPENVPN_SVC after first call and saved to state during install.
_OPENVPN_SVC=""
get_openvpn_svc() {
    if [ -n "$_OPENVPN_SVC" ]; then
        printf '%s' "$_OPENVPN_SVC"
        return
    fi
    local saved
    saved=$(get_state "OPENVPN_SERVICE" 2>/dev/null)
    if [ -n "$saved" ]; then
        _OPENVPN_SVC="$saved"
    elif systemctl cat "openvpn-server@server" &>/dev/null; then
        _OPENVPN_SVC="openvpn-server@server"
    else
        _OPENVPN_SVC="openvpn@server"
    fi
    printf '%s' "$_OPENVPN_SVC"
}

#==============================================================================
# §7  FIREWALL HELPERS (iptables)
#==============================================================================

# Save iptables rules persistently
save_iptables() {
    if is_debian_based; then
        if cmd_exists netfilter-persistent; then
            netfilter-persistent save &>/dev/null || true
        elif cmd_exists iptables-save; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
            if [ "$(get_state "IPV6_ENABLED")" = "yes" ]; then
                ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
            fi
        fi
    elif is_rhel_based; then
        if service_is_active "iptables"; then
            service_restart "iptables"
        fi
        if cmd_exists iptables-save; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
    fi
}

fw_add() {
    # Add iptables rule if not already present
    if ! iptables -C "$@" &>/dev/null; then
        iptables -A "$@"
    fi
}

fw_insert() {
    # Insert iptables rule at position 1 if not already present
    # Syntax: iptables -I CHAIN 1 <rule> (position must come right after chain name)
    local chain="$1"
    shift
    if ! iptables -C "$chain" "$@" &>/dev/null; then
        iptables -I "$chain" 1 "$@"
    fi
}

fw_delete() {
    # Delete iptables rule if present
    if iptables -C "$@" &>/dev/null; then
        iptables -D "$@"
    fi
}

fw6_add() {
    if [ "$(get_state "IPV6_ENABLED")" = "yes" ]; then
        if ! ip6tables -C "$@" &>/dev/null; then
            ip6tables -A "$@"
        fi
    fi
}
#==============================================================================
# §8  ROOT CHECK & PRE-FLIGHT
#==============================================================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root or with sudo."
        print_error "Try: sudo bash $0"
        exit 1
    fi
}

#==============================================================================
# §9  PUBLIC IP DETECTION
#==============================================================================

get_public_ip() {
    local ip=""
    # Try multiple services for reliability
    for svc in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://checkip.amazonaws.com" \
        "https://ipecho.net/plain" \
        "https://api4.my-ip.io/ip"; do
        ip=$(curl -s --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        if echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            echo "$ip"
            return 0
        fi
    done
    # Fallback: try to get from primary interface
    ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    return 1
}

get_public_ipv6() {
    local ip=""
    for svc in \
        "https://api6.ipify.org" \
        "https://ipv6.icanhazip.com" \
        "https://api6.my-ip.io/ip"; do
        ip=$(curl -s --max-time 5 -6 "$svc" 2>/dev/null | tr -d '[:space:]')
        if echo "$ip" | grep -qE '^[0-9a-fA-F:]+$' && echo "$ip" | grep -q ':'; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

#==============================================================================
# §10  DNS CONFIGURATION MAPS
#==============================================================================

detect_system_dns() {
    # Detect the server's real upstream DNS resolvers (not loopback stubs).
    # Returns "dns1 dns2" space-separated. If only one is found, dns2=dns1.
    # Skips 127.x.x.x addresses — those are unreachable from VPN clients.
    local all=""

    # Priority 1: systemd-resolved global upstream (Ubuntu 18+, Debian 10+)
    if command -v resolvectl >/dev/null 2>&1; then
        all=$(resolvectl dns 2>/dev/null \
              | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
              | grep -v '^127\.' | head -2 | tr '\n' ' ')
    fi

    # Priority 2: /run/systemd/resolve/resolv.conf (real upstream, not 127.0.0.53 stub)
    if [ -z "$all" ] && [ -f /run/systemd/resolve/resolv.conf ]; then
        all=$(grep "^nameserver" /run/systemd/resolve/resolv.conf \
              | awk '{print $2}' | grep -v '^127\.' | head -2 | tr '\n' ' ')
    fi

    # Priority 3: /etc/resolv.conf, skip loopback addresses
    if [ -z "$all" ]; then
        all=$(grep "^nameserver" /etc/resolv.conf \
              | awk '{print $2}' | grep -v '^127\.' | head -2 | tr '\n' ' ')
    fi

    # Priority 4: NetworkManager
    if [ -z "$all" ] && command -v nmcli >/dev/null 2>&1; then
        all=$(nmcli dev show 2>/dev/null | grep "IP4\.DNS" \
              | awk '{print $2}' | grep -v '^127\.' | head -2 | tr '\n' ' ')
    fi

    local dns1 dns2
    dns1=$(echo "$all" | awk '{print $1}')
    dns2=$(echo "$all" | awk '{print $2}')
    [ -z "$dns2" ] && dns2="$dns1"
    echo "$dns1 $dns2"
}

validate_dns_resolves() {
    # Returns 0 if hostname resolves to this server's IP, 1 if no resolution, 2 if wrong IP.
    local hostname="$1"
    local server_ip
    server_ip=$(get_public_ip)

    local resolved_ip=""
    if command -v getent >/dev/null 2>&1; then
        resolved_ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)
    fi
    if [ -z "$resolved_ip" ] && command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short "$hostname" A 2>/dev/null | grep -E '^[0-9]' | head -1)
    fi
    if [ -z "$resolved_ip" ] && command -v host >/dev/null 2>&1; then
        resolved_ip=$(host "$hostname" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
    fi

    if [ -z "$resolved_ip" ]; then
        return 1
    fi
    if [ -n "$server_ip" ] && [ "$resolved_ip" != "$server_ip" ]; then
        return 2
    fi
    return 0
}

get_dns_ipv4() {
    # Returns "primary secondary" for a given DNS choice number
    case "$1" in
        1) detect_system_dns ;;                     # Internal — detect real upstream
        2) echo "1.1.1.1 1.0.0.1" ;;              # Cloudflare
        3) echo "94.140.14.14 94.140.15.15" ;;    # AdGuard
        4) echo "8.8.8.8 8.8.4.4" ;;              # Google
        5) echo "9.9.9.9 149.112.112.112" ;;      # Quad9
        6) echo "208.67.222.222 208.67.220.220" ;; # OpenDNS
        *) echo "8.8.8.8 8.8.4.4" ;;
    esac
}

get_dns_ipv6() {
    case "$1" in
        1) echo "" ;;                                                   # Internal (no IPv6)
        2) echo "2606:4700:4700::1111 2606:4700:4700::1001" ;;        # Cloudflare
        3) echo "2a10:50c0::ad1:ff 2a10:50c0::ad2:ff" ;;             # AdGuard
        4) echo "2001:4860:4860::8888 2001:4860:4860::8844" ;;        # Google
        5) echo "2620:fe::fe 2620:fe::9" ;;                           # Quad9
        6) echo "2620:119:35::35 2620:119:53::53" ;;                  # OpenDNS
        *) echo "" ;;
    esac
}

get_dns_name() {
    case "$1" in
        1) echo "Server's Internal DNS" ;;
        2) echo "Cloudflare" ;;
        3) echo "AdGuard" ;;
        4) echo "Google" ;;
        5) echo "Quad9" ;;
        6) echo "OpenDNS" ;;
        *) echo "Unknown" ;;
    esac
}

#==============================================================================
# §11  SETUP WIZARD — GATHERING INFORMATION
#==============================================================================

# Global variables for setup answers
SETUP_VPNS=""         # comma-separated: ikev2,l2tp,wireguard,openvpn
SETUP_ADDRESS=""      # IP or DNS hostname
SETUP_ADDR_TYPE=""    # "ip" or "dns"
SETUP_IPV6="no"       # "yes" or "no"
SETUP_DNS1=""         # Primary DNS IP
SETUP_DNS2=""         # Secondary DNS IP
SETUP_DNS1_V6=""      # Primary DNS IPv6
SETUP_DNS2_V6=""      # Secondary DNS IPv6
SETUP_USERNAME=""
SETUP_PASSWORD=""
SETUP_PSK=""
SETUP_LE_EMAIL=""     # Email for Let's Encrypt certificate (DNS mode only)

ask_vpn_selection() {
    print_section "VPN Server Selection"
    echo -e "  Select which VPN servers to install:"
    echo ""
    echo -e "  ${BOLD}1)${NC} IKEv2/IPsec   ${DIM}(strongSwan — username/password + certificate auth)${NC}"
    echo -e "  ${BOLD}2)${NC} L2TP/IPsec    ${DIM}(xl2tpd + strongSwan — username/password + PSK auth)${NC}"
    echo -e "  ${BOLD}3)${NC} WireGuard     ${DIM}(key-based auth — fastest modern VPN)${NC}"
    echo -e "  ${BOLD}4)${NC} OpenVPN       ${DIM}(username/password + certificate auth)${NC}"
    echo -e "  ${BOLD}5)${NC} All of the above"
    echo ""

    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter choice [1-5]: "
        read -r vpn_choice
        case "$vpn_choice" in
            1) SETUP_VPNS="$VPN_IKEV2"; break ;;
            2) SETUP_VPNS="$VPN_L2TP"; break ;;
            3) SETUP_VPNS="$VPN_WG"; break ;;
            4) SETUP_VPNS="$VPN_OVPN"; break ;;
            5) SETUP_VPNS="${VPN_IKEV2},${VPN_L2TP},${VPN_WG},${VPN_OVPN}"; break ;;
            *) print_warning "Please enter a number between 1 and 5." ;;
        esac
    done

    echo ""
    echo -e "  ${GREEN}Selected:${NC} ${SETUP_VPNS}"
}

ask_server_address() {
    print_section "Server Address"

    local detected_ip
    echo -en "  ${DIM}Detecting public IP...${NC}"
    detected_ip=$(get_public_ip)
    if [ -z "$detected_ip" ]; then
        print_warning "\n  Could not auto-detect public IP."
        detected_ip="<unknown>"
    else
        echo -e " ${GREEN}${detected_ip}${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}1)${NC} Use a DNS hostname  ${DIM}(e.g. vpn.example.com)${NC}"
    echo -e "  ${BOLD}2)${NC} Use server IP       ${DIM}(detected: ${detected_ip})${NC}"
    echo ""

    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter choice [1-2]: "
        read -r addr_choice
        case "$addr_choice" in
            1)
                SETUP_ADDR_TYPE="dns"
                echo ""
                while true; do
                    echo -en "${YELLOW}  ?${NC}  Enter DNS hostname: "
                    read -r SETUP_ADDRESS
                    if [ -z "$SETUP_ADDRESS" ]; then
                        print_warning "  Hostname cannot be empty."
                    elif ! echo "$SETUP_ADDRESS" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$'; then
                        print_warning "  Invalid hostname. Use only letters, digits, dots, and hyphens."
                    else
                        break
                    fi
                done
                echo ""
                echo -e "  ${DIM}A Let's Encrypt certificate will be requested for this hostname.${NC}"
                echo -e "  ${DIM}Requires the hostname to resolve to this server and port 80 to be reachable.${NC}"
                while true; do
                    echo -en "${YELLOW}  ?${NC}  Email for Let's Encrypt (required): "
                    read -r SETUP_LE_EMAIL
                    if [ -n "$SETUP_LE_EMAIL" ]; then
                        break
                    else
                        print_warning "  Email cannot be empty."
                    fi
                done
                break
                ;;
            2)
                SETUP_ADDR_TYPE="ip"
                if [ "$detected_ip" = "<unknown>" ]; then
                    echo ""
                    while true; do
                        echo -en "${YELLOW}  ?${NC}  Enter server IP manually: "
                        read -r SETUP_ADDRESS
                        if echo "$SETUP_ADDRESS" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
                            break
                        else
                            print_warning "  Please enter a valid IPv4 address."
                        fi
                    done
                else
                    SETUP_ADDRESS="$detected_ip"
                    echo -e "  ${GREEN}Using:${NC} ${SETUP_ADDRESS}"
                fi
                break
                ;;
            *) print_warning "Please enter 1 or 2." ;;
        esac
    done
}

ask_ipv6_support() {
    print_section "IPv6 Support"
    echo -e "  IPv4 is always enabled. You can optionally enable IPv6 as well."
    echo ""
    if ask_yn "Enable IPv6 support?" "n"; then
        SETUP_IPV6="yes"
        print_success "  IPv6 will be enabled."
    else
        SETUP_IPV6="no"
        print_info "  IPv6 disabled. IPv4 only."
    fi
}

ask_dns_servers() {
    print_section "DNS Resolver Selection"
    echo -e "  Select up to two DNS servers for VPN clients."
    echo -e "  ${DIM}(Enter two numbers separated by space, or one number for both primary/secondary)${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Server's Internal DNS  ${DIM}(auto-detected)${NC}"
    echo -e "  ${BOLD}2)${NC} Cloudflare             ${DIM}(1.1.1.1, 1.0.0.1)${NC}"
    echo -e "  ${BOLD}3)${NC} AdGuard                ${DIM}(94.140.14.14, 94.140.15.15)${NC}"
    echo -e "  ${BOLD}4)${NC} Google                 ${DIM}(8.8.8.8, 8.8.4.4)${NC}"
    echo -e "  ${BOLD}5)${NC} Quad9                  ${DIM}(9.9.9.9, 149.112.112.112)${NC}"
    echo -e "  ${BOLD}6)${NC} OpenDNS                ${DIM}(208.67.222.222, 208.67.220.220)${NC}"
    echo ""

    local d1 d2
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter choice(s) [e.g. '4' or '4 2']: "
        read -r dns_input
        d1=$(echo "$dns_input" | awk '{print $1}')
        d2=$(echo "$dns_input" | awk '{print $2}')
        if [ -z "$d2" ]; then
            d2="$d1"
        fi
        if echo "$d1" | grep -qE '^[1-6]$' && echo "$d2" | grep -qE '^[1-6]$'; then
            break
        else
            print_warning "  Please enter valid choices (1-6)."
        fi
    done

    # Get DNS IPs — when same provider chosen for both, use its secondary IP for DNS2
    local dns1_pair dns2_pair
    dns1_pair=$(get_dns_ipv4 "$d1")
    dns2_pair=$(get_dns_ipv4 "$d2")
    SETUP_DNS1=$(echo "$dns1_pair" | awk '{print $1}')
    if [ "$d1" = "$d2" ]; then
        SETUP_DNS2=$(echo "$dns2_pair" | awk '{print $2}')
    else
        SETUP_DNS2=$(echo "$dns2_pair" | awk '{print $1}')
    fi

    # If internal DNS selected but detection failed, fall back to Cloudflare
    if { [ "$d1" = "1" ] || [ "$d2" = "1" ]; }; then
        if [ -z "$SETUP_DNS1" ] && [ -z "$SETUP_DNS2" ]; then
            print_warning "  Could not detect system DNS. Falling back to Cloudflare (1.1.1.1)."
            SETUP_DNS1="1.1.1.1"
            SETUP_DNS2="1.0.0.1"
        elif [ -z "$SETUP_DNS1" ]; then
            print_warning "  Could not detect system DNS for primary. Using Cloudflare (1.1.1.1)."
            SETUP_DNS1="1.1.1.1"
        elif [ -z "$SETUP_DNS2" ]; then
            print_warning "  Could not detect system DNS for secondary. Using Cloudflare (1.0.0.1)."
            SETUP_DNS2="1.0.0.1"
        fi
    fi

    if [ "$SETUP_IPV6" = "yes" ]; then
        local v6_1 v6_2
        v6_1=$(get_dns_ipv6 "$d1" | awk '{print $1}')
        if [ "$d1" = "$d2" ]; then
            v6_2=$(get_dns_ipv6 "$d2" | awk '{print $2}')
        else
            v6_2=$(get_dns_ipv6 "$d2" | awk '{print $1}')
        fi
        SETUP_DNS1_V6="$v6_1"
        SETUP_DNS2_V6="$v6_2"
    fi

    echo ""
    echo -e "  ${GREEN}Primary DNS:${NC}   $(get_dns_name "$d1") — ${SETUP_DNS1}"
    echo -e "  ${GREEN}Secondary DNS:${NC} $(get_dns_name "$d2") — ${SETUP_DNS2}"
}

ask_user_credentials() {
    print_section "First VPN User Setup"
    echo -e "  Configure the first VPN user account."
    echo -e "  ${DIM}Special characters are supported and will be properly escaped.${NC}"
    echo ""

    # Username
    while true; do
        echo -en "${YELLOW}  ?${NC}  Username: "
        read -r SETUP_USERNAME
        if [ -z "$SETUP_USERNAME" ]; then
            print_warning "  Username cannot be empty."
        elif echo "$SETUP_USERNAME" | grep -qE '^[a-zA-Z0-9._@-]+$'; then
            break
        else
            print_warning "  Username should contain only letters, numbers, '.', '_', '@', '-'."
            if ask_yn "  Use this username anyway?" "n"; then
                break
            fi
        fi
    done

    # Password
    local pass1 pass2
    while true; do
        echo -en "${YELLOW}  ?${NC}  Password (hidden): "
        read -rs pass1
        echo ""
        echo -en "${YELLOW}  ?${NC}  Confirm password: "
        read -rs pass2
        echo ""
        if [ -z "$pass1" ]; then
            print_warning "  Password cannot be empty."
        elif [ "$pass1" != "$pass2" ]; then
            print_warning "  Passwords do not match. Please try again."
        else
            SETUP_PASSWORD="$pass1"
            break
        fi
    done

    # Pre-shared key (PSK) — used for IKEv2 PSK mode and L2TP/IPsec
    local psk1 psk2
    echo ""
    echo -e "  ${DIM}The Pre-Shared Key (PSK) is used for IKEv2 PSK-mode and L2TP/IPsec${NC}"
    echo -e "  ${DIM}authentication. L2TP clients will need this key.${NC}"
    while true; do
        echo -en "${YELLOW}  ?${NC}  Pre-Shared Key (hidden): "
        read -rs psk1
        echo ""
        echo -en "${YELLOW}  ?${NC}  Confirm Pre-Shared Key: "
        read -rs psk2
        echo ""
        if [ -z "$psk1" ]; then
            print_warning "  PSK cannot be empty."
        elif [ "$psk1" != "$psk2" ]; then
            print_warning "  PSKs do not match. Please try again."
        else
            SETUP_PSK="$psk1"
            break
        fi
    done

    echo ""
    print_success "Credentials captured for user: ${BOLD}${SETUP_USERNAME}${NC}"
}

confirm_setup() {
    print_section "Setup Summary"
    echo -e "  ${BOLD}VPN Servers:${NC}    ${SETUP_VPNS}"
    echo -e "  ${BOLD}Server Address:${NC} ${SETUP_ADDRESS} (${SETUP_ADDR_TYPE})"
    echo -e "  ${BOLD}IPv6:${NC}           ${SETUP_IPV6}"
    echo -e "  ${BOLD}Primary DNS:${NC}    ${SETUP_DNS1}"
    echo -e "  ${BOLD}Secondary DNS:${NC}  ${SETUP_DNS2}"
    echo -e "  ${BOLD}First User:${NC}     ${SETUP_USERNAME}"
    echo ""
    if ! ask_yn "Proceed with installation?" "y"; then
        print_info "Installation cancelled."
        exit 0
    fi
}
#==============================================================================
# §12  SYSTEM PREPARATION: DEPENDENCIES, IP FORWARDING, FIREWALL
#==============================================================================

system_update() {
    print_section "System Update"
    print_step "Updating package lists..."
    eval "$PKG_UPDATE" || print_warning "Package list update had warnings (continuing)"
    print_success "System packages updated."
}

install_base_dependencies() {
    print_section "Installing Base Dependencies"

    local common_pkgs="curl wget openssl ca-certificates iptables iproute2"

    if is_debian_based; then
        print_step "Installing base packages (Debian/Ubuntu)..."
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL net-tools $common_pkgs python3 python3-pip" || true
        # iptables-persistent for saving rules
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL iptables-persistent" || true
    elif is_rhel_based; then
        print_step "Installing base packages (RHEL/CentOS/Fedora)..."
        eval "$PKG_INSTALL net-tools $common_pkgs python3 python3-pip" || true
        # Install iptables-services for persistence
        eval "$PKG_INSTALL iptables-services" || true
        systemctl enable iptables 2>/dev/null || true
        # Install EPEL for additional packages
        install_epel
    fi

    print_success "Base dependencies installed."
}

install_epel() {
    if is_rhel_based && ! rpm -q epel-release &>/dev/null; then
        print_step "Installing EPEL repository..."
        case "$OS_ID" in
            centos|rhel)
                eval "$PKG_INSTALL epel-release" || \
                    rpm -ivh "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" &>/dev/null || true
                ;;
            rocky|almalinux|ol)
                eval "$PKG_INSTALL epel-release" || true
                ;;
            amzn)
                amazon-linux-extras install epel -y &>/dev/null || true
                ;;
        esac
        print_success "EPEL repository installed."
    fi
}

setup_ip_forwarding() {
    print_section "IP Forwarding"
    print_step "Enabling IPv4 forwarding..."

    # Enable immediately
    sysctl -w net.ipv4.ip_forward=1 &>/dev/null
    sysctl -w net.ipv4.conf.all.forwarding=1 &>/dev/null

    # Persist via sysctl.d
    cat > /etc/sysctl.d/99-vpn-forwarding.conf << 'SYSCTL_EOF'
# VPN Server IP Forwarding
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1

# Security settings
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
SYSCTL_EOF

    if [ "$(get_state "IPV6_ENABLED")" = "yes" ] || [ "$SETUP_IPV6" = "yes" ]; then
        print_step "Enabling IPv6 forwarding..."
        sysctl -w net.ipv6.conf.all.forwarding=1 &>/dev/null
        cat >> /etc/sysctl.d/99-vpn-forwarding.conf << 'SYSCTL6_EOF'
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
SYSCTL6_EOF
    fi

    sysctl -p /etc/sysctl.d/99-vpn-forwarding.conf &>/dev/null || true
    print_success "IP forwarding enabled and persisted."
}

setup_firewall_base() {
    print_section "Firewall Configuration"
    local iface
    iface=$(get_primary_iface)
    print_step "Setting up base iptables rules (interface: ${iface})..."

    # Accept established/related
    fw_insert FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    fw_insert INPUT  -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Allow loopback
    fw_add INPUT -i lo -j ACCEPT
    fw_add OUTPUT -o lo -j ACCEPT

    # SSH (don't lock ourselves out)
    fw_add INPUT -p tcp --dport 22 -j ACCEPT

    # Enable NAT/masquerading for all VPN subnets
    if ! iptables -t nat -C POSTROUTING -s "${IKEV2_SUBNET}" -o "${iface}" -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${IKEV2_SUBNET}" -o "${iface}" -j MASQUERADE
    fi
    if ! iptables -t nat -C POSTROUTING -s "${L2TP_SUBNET}" -o "${iface}" -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${L2TP_SUBNET}" -o "${iface}" -j MASQUERADE
    fi
    if ! iptables -t nat -C POSTROUTING -s "${WG_SUBNET}" -o "${iface}" -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${WG_SUBNET}" -o "${iface}" -j MASQUERADE
    fi
    if ! iptables -t nat -C POSTROUTING -s "${OVPN_SUBNET}" -o "${iface}" -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${OVPN_SUBNET}" -o "${iface}" -j MASQUERADE
    fi

    # IPv6 if enabled
    if [ "$SETUP_IPV6" = "yes" ]; then
        ip6tables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        ip6tables -A INPUT  -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        ip6tables -A INPUT  -i lo -j ACCEPT 2>/dev/null || true
        ip6tables -t nat -A POSTROUTING -o "${iface}" -j MASQUERADE 2>/dev/null || true
    fi

    save_iptables
    print_success "Base firewall rules configured."
}

#==============================================================================
# §13  LET'S ENCRYPT CERTIFICATE SUPPORT
#==============================================================================

is_letsencrypt() {
    [ "$(get_state "CERT_TYPE")" = "letsencrypt" ]
}

install_certbot() {
    if command -v certbot >/dev/null 2>&1; then return 0; fi
    print_step "Installing certbot..."
    if is_debian_based; then
        apt-get install -y certbot 2>/dev/null
    elif is_rhel_based; then
        dnf install -y certbot 2>/dev/null || yum install -y certbot 2>/dev/null
    fi
    command -v certbot >/dev/null 2>&1
}

obtain_letsencrypt_cert() {
    local domain="$1"
    local email="$2"

    print_step "Obtaining Let's Encrypt certificate for ${domain}..."

    # Validate DNS resolution before attempting
    local dns_status
    validate_dns_resolves "$domain"; dns_status=$?
    if [ $dns_status -eq 1 ]; then
        print_error "DNS for '${domain}' does not resolve. Cannot obtain Let's Encrypt certificate."
        return 1
    elif [ $dns_status -eq 2 ]; then
        print_warning "DNS for '${domain}' resolves but not to this server's IP. Proceeding anyway."
    fi

    install_certbot || { print_error "Failed to install certbot."; return 1; }

    # If a cert already exists for a DIFFERENT domain under the vpn-server cert name,
    # certbot --non-interactive will refuse to replace it without --force-renewal.
    # Detect this and add the flag so the cert is replaced rather than erroring out.
    local force_renewal=""
    local existing_le_domain
    existing_le_domain=$(get_state "LE_DOMAIN")
    if [ -n "$existing_le_domain" ] && [ "$existing_le_domain" != "$domain" ]; then
        print_warning "Replacing existing LE cert (was for '${existing_le_domain}', now '${domain}')."
        force_renewal="--force-renewal"
    fi

    # Temporarily open port 80 for HTTP-01 challenge
    iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    ip6tables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

    # shellcheck disable=SC2086
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" \
        --cert-name "vpn-server" \
        $force_renewal \
        2>&1 | tee /tmp/certbot_output.log

    local certbot_status=${PIPESTATUS[0]}

    # Close port 80
    iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    ip6tables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true

    if [ $certbot_status -ne 0 ]; then
        print_error "certbot failed. Check /tmp/certbot_output.log for details."
        return 1
    fi

    # Copy LE certs into our cert store
    local le_dir="${LE_CERTS_BASE}/vpn-server"
    cp "${le_dir}/fullchain.pem" "${CERTS_DIR}/server.crt"
    cp "${le_dir}/privkey.pem"   "${CERTS_DIR}/server.key"
    cp "${le_dir}/chain.pem"     "${CERTS_DIR}/le_chain.crt"
    chmod 600 "${CERTS_DIR}/server.key"

    save_state "CERT_TYPE"  "letsencrypt"
    save_state "LE_DOMAIN"  "$domain"
    save_state "LE_EMAIL"   "$email"

    # Create deploy hook for automatic renewal
    _write_le_deploy_hooks

    print_success "Let's Encrypt certificate obtained for ${domain}."
}

_write_le_deploy_hooks() {
    # Deploy hook: copy renewed certs and restart VPN services
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    mkdir -p /etc/letsencrypt/renewal-hooks/pre
    mkdir -p /etc/letsencrypt/renewal-hooks/post

    cat > /etc/letsencrypt/renewal-hooks/deploy/vpn-cert-deploy.sh << 'DEPLOY_HOOK'
#!/bin/bash
# Runs after each successful certbot renewal
LE_DIR="/etc/letsencrypt/live/vpn-server"
CERTS_DIR="/etc/vpn-setup/certs"

cp "${LE_DIR}/fullchain.pem" "${CERTS_DIR}/server.crt"
cp "${LE_DIR}/privkey.pem"   "${CERTS_DIR}/server.key"
cp "${LE_DIR}/chain.pem"     "${CERTS_DIR}/le_chain.crt"
chmod 600 "${CERTS_DIR}/server.key"

# IKEv2 (strongSwan)
if [ -d /etc/ipsec.d ]; then
    cp "${CERTS_DIR}/server.crt" /etc/ipsec.d/certs/server.crt
    cp "${CERTS_DIR}/server.key" /etc/ipsec.d/private/server.key
    chmod 600 /etc/ipsec.d/private/server.key
    ipsec restart >/dev/null 2>&1 || true
fi

# OpenVPN
if [ -d /etc/openvpn/server ]; then
    cp "${CERTS_DIR}/server.crt" /etc/openvpn/server/server.crt
    cp "${CERTS_DIR}/server.key" /etc/openvpn/server/server.key
    chmod 600 /etc/openvpn/server/server.key
    systemctl restart openvpn@server >/dev/null 2>&1 || \
    systemctl restart openvpn-server@server >/dev/null 2>&1 || true
fi
DEPLOY_HOOK
    chmod 700 /etc/letsencrypt/renewal-hooks/deploy/vpn-cert-deploy.sh

    # Pre-hook: open port 80 before renewal attempt
    cat > /etc/letsencrypt/renewal-hooks/pre/vpn-open-port80.sh << 'PRE_HOOK'
#!/bin/bash
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
ip6tables -I INPUT 1 -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
PRE_HOOK
    chmod 700 /etc/letsencrypt/renewal-hooks/pre/vpn-open-port80.sh

    # Post-hook: close port 80 after renewal attempt
    cat > /etc/letsencrypt/renewal-hooks/post/vpn-close-port80.sh << 'POST_HOOK'
#!/bin/bash
iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
ip6tables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
POST_HOOK
    chmod 700 /etc/letsencrypt/renewal-hooks/post/vpn-close-port80.sh

    print_success "Let's Encrypt renewal hooks installed."
}

_cleanup_letsencrypt() {
    # Removes the certbot certificate and renewal hooks when switching away from LE.
    # Without this, certbot's auto-renewal would keep renewing the old cert and the
    # deploy hook would overwrite whatever new cert is in place (self-signed or new LE).
    print_step "Removing Let's Encrypt certificate and renewal hooks..."
    if command -v certbot >/dev/null 2>&1; then
        certbot delete --cert-name vpn-server --non-interactive 2>/dev/null || true
    fi
    rm -f /etc/letsencrypt/renewal-hooks/deploy/vpn-cert-deploy.sh
    rm -f /etc/letsencrypt/renewal-hooks/pre/vpn-open-port80.sh
    rm -f /etc/letsencrypt/renewal-hooks/post/vpn-close-port80.sh
}

#==============================================================================
# §14  CERTIFICATE GENERATION (OpenSSL, self-signed, 10 years)
#==============================================================================

generate_ca_cert() {
    print_section "Certificate Authority"
    print_step "Generating CA key and certificate (RSA 4096, 10 years)..."

    mkdir -p "${CERTS_DIR}/users"
    chmod 700 "${CERTS_DIR}"

    local ca_key="${CERTS_DIR}/ca.key"
    local ca_crt="${CERTS_DIR}/ca.crt"
    local ca_subj="/C=US/ST=VPN/L=VPN/O=VPN CA/CN=VPN Root CA"

    if [ -f "$ca_crt" ]; then
        print_warning "CA certificate already exists at ${ca_crt}. Skipping regeneration."
        return 0
    fi

    # Generate CA private key
    openssl genrsa -out "$ca_key" 4096 2>/dev/null || {
        print_error "Failed to generate CA key."
        exit 1
    }
    chmod 600 "$ca_key"

    # Generate self-signed CA certificate
    openssl req -new -x509 \
        -key "$ca_key" \
        -out "$ca_crt" \
        -days "${CERT_DAYS}" \
        -subj "$ca_subj" \
        -extensions v3_ca \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        2>/dev/null || {
        print_error "Failed to generate CA certificate."
        exit 1
    }

    print_success "CA certificate generated: ${ca_crt}"
}

generate_server_cert() {
    local server_addr="$1"  # DNS name or IP
    local addr_type="$2"    # "dns" or "ip"
    print_step "Generating server certificate for: ${server_addr}..."

    local server_key="${CERTS_DIR}/server.key"
    local server_csr="${CERTS_DIR}/server.csr"
    local server_crt="${CERTS_DIR}/server.crt"
    local ca_key="${CERTS_DIR}/ca.key"
    local ca_crt="${CERTS_DIR}/ca.crt"
    local san_ext="${CERTS_DIR}/server_san.ext"

    # Build SAN extension — include keyUsage and EKU (required by OpenVPN remote-cert-tls server)
    if [ "$addr_type" = "dns" ]; then
        cat > "$san_ext" << EXT_EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${server_addr}
EXT_EOF
        local san_value="DNS:${server_addr}"
    else
        cat > "$san_ext" << EXT_EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
IP.1 = ${server_addr}
EXT_EOF
        local san_value="IP:${server_addr}"
    fi

    # Generate server private key
    openssl genrsa -out "$server_key" 2048 2>/dev/null || {
        print_error "Failed to generate server key."
        exit 1
    }
    chmod 600 "$server_key"

    # Generate CSR
    openssl req -new \
        -key "$server_key" \
        -out "$server_csr" \
        -subj "/C=US/ST=VPN/L=VPN/O=VPN Server/CN=${server_addr}" \
        2>/dev/null || { print_error "Failed to generate server CSR."; exit 1; }

    # Sign with CA
    openssl x509 -req \
        -in "$server_csr" \
        -CA "$ca_crt" \
        -CAkey "$ca_key" \
        -CAcreateserial \
        -out "$server_crt" \
        -days "${CERT_DAYS}" \
        -sha256 \
        -extfile "$san_ext" \
        -extensions v3_req \
        2>/dev/null || { print_error "Failed to sign server certificate."; exit 1; }

    rm -f "$san_ext"
    print_success "Server certificate generated: ${server_crt}"
}

generate_client_cert() {
    local username="$1"
    local password="$2"   # used as P12 export password
    print_step "Generating client certificate for user: ${username}..."

    local user_dir="${CERTS_DIR}/users/${username}"
    mkdir -p "$user_dir"
    chmod 700 "$user_dir"

    local client_key="${user_dir}/client.key"
    local client_csr="${user_dir}/client.csr"
    local client_crt="${user_dir}/client.crt"
    local client_p12="${user_dir}/client.p12"
    local ca_key="${CERTS_DIR}/ca.key"
    local ca_crt="${CERTS_DIR}/ca.crt"
    local client_ext="${user_dir}/client.ext"

    # Generate client private key
    openssl genrsa -out "$client_key" 2048 2>/dev/null || {
        print_error "Failed to generate client key for ${username}."
        return 1
    }
    chmod 600 "$client_key"

    # Generate CSR
    openssl req -new \
        -key "$client_key" \
        -out "$client_csr" \
        -subj "/C=US/ST=VPN/L=VPN/O=VPN Client/CN=${username}" \
        2>/dev/null || { print_error "Failed to generate client CSR."; return 1; }

    # Write extensions file (extfile approach for OpenSSL 3.x compatibility)
    # SAN email identity must match LocalIdentifier used in the IKEv2 cert mobileconfig
    # so strongSwan can verify the client cert identity against the presented IDi.
    cat > "$client_ext" << EXT_EOF
[v3_client]
keyUsage = critical,digitalSignature
extendedKeyUsage = clientAuth
subjectAltName = email:${username}@cert.vpn
EXT_EOF

    # Sign with CA
    openssl x509 -req \
        -in "$client_csr" \
        -CA "$ca_crt" \
        -CAkey "$ca_key" \
        -CAcreateserial \
        -out "$client_crt" \
        -days "${CERT_DAYS}" \
        -sha256 \
        -extfile "$client_ext" \
        -extensions v3_client \
        2>/dev/null || { print_error "Failed to sign client certificate."; return 1; }

    rm -f "$client_ext"

    # Export as PKCS#12 (password = user's VPN password)
    openssl pkcs12 -export \
        -in "$client_crt" \
        -inkey "$client_key" \
        -certfile "${CERTS_DIR}/ca.crt" \
        -out "$client_p12" \
        -passout "pass:${password}" \
        -name "${username} VPN Certificate" \
        2>/dev/null || { print_error "Failed to export P12 for ${username}."; return 1; }

    chmod 600 "$client_p12"
    print_success "Client certificate and P12 generated for: ${username}"
}
#==============================================================================
# §15  IKEv2 INSTALLATION & CONFIGURATION (strongSwan)
#==============================================================================

install_ikev2_packages() {
    print_step "Installing strongSwan packages..."
    if is_debian_based; then
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL \
            strongswan \
            strongswan-pki \
            libstrongswan-standard-plugins \
            libstrongswan-extra-plugins \
            libcharon-extra-plugins \
            libcharon-extauth-plugins" || true
        # Try newer package names
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL \
            strongswan-swanctl \
            charon-systemd" 2>/dev/null || true
    elif is_rhel_based; then
        eval "$PKG_INSTALL \
            strongswan \
            strongswan-plugin-eap-mschapv2 \
            strongswan-plugin-xauth-generic" || true
    fi
}

install_ikev2() {
    print_section "Installing IKEv2/IPsec (strongSwan)"

    install_ikev2_packages

    # Copy certificates to ipsec.d
    print_step "Installing certificates into strongSwan..."
    mkdir -p /etc/ipsec.d/{cacerts,certs,private}
    cp "${CERTS_DIR}/ca.crt"     /etc/ipsec.d/cacerts/
    cp "${CERTS_DIR}/server.crt" /etc/ipsec.d/certs/
    cp "${CERTS_DIR}/server.key" /etc/ipsec.d/private/
    chmod 600 /etc/ipsec.d/private/server.key

    configure_ikev2
    configure_ikev2_firewall

    # Enable and start
    service_enable "strongswan"
    service_restart "strongswan"
    # Some distros use strongswan-starter
    service_enable "strongswan-starter" 2>/dev/null || true
    service_restart "strongswan-starter" 2>/dev/null || true

    mark_vpn_installed "$VPN_IKEV2"
    print_success "IKEv2 installed and running."
}

configure_ikev2() {
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local addr_type
    addr_type=$(get_state "ADDRESS_TYPE")
    local dns1
    dns1=$(get_state "DNS1")
    local dns2
    dns2=$(get_state "DNS2")
    local ipv6_enabled
    ipv6_enabled=$(get_state "IPV6_ENABLED")

    print_step "Writing ipsec.conf..."

    # Backup existing config
    [ -f /etc/ipsec.conf ] && cp /etc/ipsec.conf /etc/ipsec.conf.bak.$(date +%Y%m%d%H%M%S)

    local dns_line=""
    if [ -n "$dns1" ]; then
        if [ -n "$dns2" ] && [ "$dns2" != "$dns1" ]; then
            dns_line="rightdns=${dns1},${dns2}"
        else
            dns_line="rightdns=${dns1}"
        fi
    fi

    local rightsourceip_eap="${IKEV2_POOL}"
    local rightsourceip_cert="10.10.11.10-10.10.11.250"
    local leftsubnet_val="0.0.0.0/0"
    if [ "$ipv6_enabled" = "yes" ]; then
        leftsubnet_val="0.0.0.0/0,::/0"
    fi

    cat > /etc/ipsec.conf << IPSEC_CONF
# /etc/ipsec.conf - VPN Server IKEv2 Configuration
# Managed by vpn-setup.sh — DO NOT EDIT MANUALLY

config setup
    charondebug="ike 1, knl 1, cfg 0, net 0, esp 0, dmn 0, mgr 0"
    strictcrlpolicy=no
    uniqueids=no

conn %default
    keyexchange=ikev2
    left=%defaultroute
    leftid=$([ "$addr_type" = "dns" ] && echo "@${server_addr}" || echo "${server_addr}")
    leftcert=server.crt
    leftsendcert=always
    leftsubnet=${leftsubnet_val}
    dpdaction=clear
    dpddelay=300s
    rekey=no
    ike=aes256gcm16-sha2_512-prfsha512-ecp384,aes256gcm16-sha2_256-prfsha256-modp2048,aes256-sha2_512-prfsha512-modp4096,aes256-sha2_256-prfsha256-modp2048,aes128-sha2_256-prfsha256-modp2048
    esp=aes256gcm16-sha2_512,aes256gcm16-sha2_256,aes256-sha2_512,aes256-sha2_256,aes128-sha2_256

# EAP-MSCHAPv2: Username/Password authentication
conn ikev2-eap
    also=%default
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=${rightsourceip_eap}
    ${dns_line}
    rightsendcert=never
    eap_identity=%identity
    auto=add

# Certificate-based authentication
conn ikev2-cert
    also=%default
    right=%any
    rightauth=pubkey
    rightsourceip=${rightsourceip_cert}
    ${dns_line}
    auto=add
IPSEC_CONF

    print_step "Writing ipsec.secrets..."
    [ -f /etc/ipsec.secrets ] && cp /etc/ipsec.secrets /etc/ipsec.secrets.bak.$(date +%Y%m%d%H%M%S)

    cat > /etc/ipsec.secrets << IPSEC_SECRETS
# /etc/ipsec.secrets - VPN Credentials
# Managed by vpn-setup.sh — DO NOT EDIT MANUALLY
# Format: %any username : EAP "password"
# Format: %any %any : PSK "psk"

: RSA server.key

IPSEC_SECRETS
    chmod 600 /etc/ipsec.secrets

    # Add L2TP PSK if L2TP is being installed
    if in_list "$VPN_L2TP" "$SETUP_VPNS" || vpn_is_installed "$VPN_L2TP"; then
        local psk
        psk=$(get_state "L2TP_PSK")
        if [ -n "$psk" ]; then
            local escaped_psk
            escaped_psk=$(escape_ipsec "$psk")
            echo "%any %any : PSK \"${escaped_psk}\"" >> /etc/ipsec.secrets
        fi
    fi

    print_success "IKEv2 configuration written."
}

configure_ikev2_firewall() {
    print_step "Configuring IKEv2 firewall rules..."
    # IKEv2 ports
    fw_add INPUT -p udp --dport "${IKEV2_PORT}" -j ACCEPT
    fw_add INPUT -p udp --dport "${IKEV2_NAT_PORT}" -j ACCEPT
    fw_add FORWARD -s "${IKEV2_SUBNET}" -j ACCEPT
    fw_add FORWARD -d "${IKEV2_SUBNET}" -j ACCEPT
    # Cert pool subnet
    fw_add FORWARD -s "10.10.11.0/24" -j ACCEPT
    fw_add FORWARD -d "10.10.11.0/24" -j ACCEPT
    save_iptables
    print_success "IKEv2 firewall rules set."
}

# Add a user to IKEv2 (EAP credentials + client cert)
add_ikev2_user() {
    local username="$1"
    local password="$2"
    local skip_restart="${3:-false}"  # pass "true" in batch ops; caller restarts once at the end

    print_step "Adding IKEv2 user: ${username}..."

    # Add EAP credentials to ipsec.secrets
    local escaped_user escaped_pass sed_user
    escaped_user=$(escape_ipsec "$username")
    escaped_pass=$(escape_ipsec "$password")
    sed_user=$(sed_escape_pattern "$escaped_user")

    # Remove existing entry if present (delete-before-add is idempotent and re-run safe)
    # Format: "%any username : EAP ..." — %any is the server wildcard, username is the EAP client identity
    sed -i "/^%any ${sed_user} : EAP /d" /etc/ipsec.secrets

    echo "%any ${escaped_user} : EAP \"${escaped_pass}\"" >> /etc/ipsec.secrets

    # Copy client cert to ipsec.d/certs if it exists
    local user_crt="${CERTS_DIR}/users/${username}/client.crt"
    local user_key="${CERTS_DIR}/users/${username}/client.key"
    if [ -f "$user_crt" ]; then
        cp "$user_crt" "/etc/ipsec.d/certs/${username}_client.crt"
        cp "$user_key" "/etc/ipsec.d/private/${username}_client.key"
        chmod 600 "/etc/ipsec.d/private/${username}_client.key"
    fi

    # Add per-user cert connection so certificate auth gets an exact rightid match,
    # giving it higher priority than the wildcard ikev2-eap connection.
    # Remove stale entry first, then append fresh block.
    local sed_uname
    sed_uname=$(sed_escape_pattern "$username")
    sed -i "/^# BEGIN ikev2-cert-${sed_uname}$/,/^# END ikev2-cert-${sed_uname}$/d" /etc/ipsec.conf
    cat >> /etc/ipsec.conf << CERT_CONN

# BEGIN ikev2-cert-${username}
conn ikev2-cert-${username}
    also=ikev2-cert
    rightid=${username}@cert.vpn
# END ikev2-cert-${username}
CERT_CONN

    # Restart strongSwan — ipsec reload does not reload secrets from disk
    if [ "$skip_restart" != "true" ]; then
        ipsec restart &>/dev/null || true
    fi

    print_success "IKEv2 user added: ${username}"
}

# Remove a user from IKEv2
remove_ikev2_user() {
    local username="$1"
    local skip_restart="${2:-false}"

    print_step "Removing IKEv2 user: ${username}..."

    # Remove EAP entry — cover both old (no %any prefix) and current (%any prefix) formats
    local escaped_user sed_user
    escaped_user=$(escape_ipsec "$username")
    sed_user=$(sed_escape_pattern "$escaped_user")
    sed -i "/^${sed_user} : EAP /d" /etc/ipsec.secrets
    sed -i "/^%any ${sed_user} : EAP /d" /etc/ipsec.secrets

    # Remove certs
    rm -f "/etc/ipsec.d/certs/${username}_client.crt"
    rm -f "/etc/ipsec.d/private/${username}_client.key"

    # Remove per-user cert connection block from ipsec.conf
    local sed_uname
    sed_uname=$(sed_escape_pattern "$username")
    sed -i "/^# BEGIN ikev2-cert-${sed_uname}$/,/^# END ikev2-cert-${sed_uname}$/d" /etc/ipsec.conf

    if [ "$skip_restart" != "true" ]; then
        ipsec restart &>/dev/null || true
    fi
    print_success "IKEv2 user removed: ${username}"
}

#==============================================================================
# §16  L2TP/IPsec INSTALLATION & CONFIGURATION
#==============================================================================

install_l2tp_packages() {
    print_step "Installing xl2tpd and PPP packages..."

    # Load PPP kernel modules before installing — xl2tpd requires them at startup
    modprobe ppp_generic 2>/dev/null || true
    modprobe ppp_async   2>/dev/null || true
    modprobe ppp_mppe    2>/dev/null || true

    if is_debian_based; then
        # Mask xl2tpd before install: the package post-install script tries to start
        # the service, which fails because the config file doesn't exist yet.
        # We unmask after install and start it ourselves after writing the config.
        systemctl mask xl2tpd 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL xl2tpd ppp" || true
        systemctl unmask xl2tpd 2>/dev/null || true

        # Verify the binary was actually installed
        if ! cmd_exists xl2tpd; then
            print_error "xl2tpd binary not found after install. Check apt logs."
            exit 1
        fi
    elif is_rhel_based; then
        # xl2tpd needs EPEL on RHEL-based
        install_epel
        eval "$PKG_INSTALL xl2tpd ppp" || {
            print_error "Failed to install xl2tpd."
            exit 1
        }
    fi
    print_success "xl2tpd and ppp installed."
}

install_l2tp() {
    print_section "Installing L2TP/IPsec (xl2tpd + strongSwan)"

    # strongSwan should already be installed for IKEv2. If not, install it.
    if ! cmd_exists ipsec; then
        install_ikev2_packages
    fi

    install_l2tp_packages

    # Save PSK to state (if not already saved)
    if [ -n "${SETUP_PSK:-}" ]; then
        save_state "L2TP_PSK" "$SETUP_PSK"
    fi

    configure_l2tp
    configure_l2tp_ipsec
    configure_l2tp_firewall

    service_enable "xl2tpd"
    service_restart "xl2tpd"
    service_enable "strongswan"
    service_restart "strongswan"

    mark_vpn_installed "$VPN_L2TP"
    print_success "L2TP/IPsec installed and running."
}

configure_l2tp() {
    local dns1
    dns1=$(get_state "DNS1")
    local dns2
    dns2=$(get_state "DNS2")

    print_step "Writing xl2tpd configuration..."
    mkdir -p /etc/xl2tpd

    cat > /etc/xl2tpd/xl2tpd.conf << L2TP_CONF
; /etc/xl2tpd/xl2tpd.conf - Managed by vpn-setup.sh
[global]
ipsec saref = no
saref refinfo = 30
port = ${L2TP_PORT}

[lns default]
ip range = ${L2TP_POOL}
local ip = ${L2TP_SERVER_IP}
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
L2TP_CONF

    print_step "Writing PPP options..."
    cat > /etc/ppp/options.xl2tpd << PPP_OPTS
# /etc/ppp/options.xl2tpd - Managed by vpn-setup.sh
ipcp-accept-local
ipcp-accept-remote
ms-dns ${dns1}
ms-dns ${dns2}
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
nodefaultroute
proxyarp
connect-delay 5000
lcp-echo-failure 10
lcp-echo-interval 60
PPP_OPTS

    # Initialize chap-secrets if not present
    if [ ! -f /etc/ppp/chap-secrets ]; then
        cat > /etc/ppp/chap-secrets << CHAP_HDR
# /etc/ppp/chap-secrets - L2TP VPN Credentials
# Managed by vpn-setup.sh — DO NOT EDIT MANUALLY
# Format: "username" l2tpd "password" *
CHAP_HDR
        chmod 600 /etc/ppp/chap-secrets
    fi

    print_success "L2TP/PPP configuration written."
}

configure_l2tp_ipsec() {
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local psk
    psk=$(get_state "L2TP_PSK")

    print_step "Writing L2TP/IPsec connection (ipsec.conf)..."

    # Check if L2TP-PSK conn already exists
    if grep -q "conn L2TP-PSK" /etc/ipsec.conf 2>/dev/null; then
        return 0
    fi

    cat >> /etc/ipsec.conf << L2TP_CONN

# L2TP/IPsec IKEv1 connection
conn L2TP-PSK
    keyexchange=ikev1
    left=%defaultroute
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    authby=secret
    type=transport
    auto=add
    ike=aes256-sha1-modp2048,aes128-sha1-modp1024,3des-sha1-modp1024
    esp=aes256-sha1,aes128-sha1,3des-sha1
L2TP_CONN

    # Write PSK to ipsec.secrets (delete-before-add so the entry is always current)
    local escaped_psk
    escaped_psk=$(escape_ipsec "$psk")
    sed -i "/^%any %any : PSK /d" /etc/ipsec.secrets
    echo "%any %any : PSK \"${escaped_psk}\"" >> /etc/ipsec.secrets

    ipsec restart &>/dev/null || true
    print_success "L2TP/IPsec connection configured."
}

configure_l2tp_firewall() {
    print_step "Configuring L2TP firewall rules..."
    local iface
    iface=$(get_primary_iface)

    fw_add INPUT -p udp --dport "${L2TP_PORT}" -j ACCEPT
    fw_add INPUT -p esp -j ACCEPT
    fw_add INPUT -p ah -j ACCEPT
    fw_add FORWARD -s "${L2TP_SUBNET}" -j ACCEPT
    fw_add FORWARD -d "${L2TP_SUBNET}" -j ACCEPT

    # L2TP needs NAT
    if ! iptables -t nat -C POSTROUTING -s "${L2TP_SUBNET}" -o "${iface}" -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${L2TP_SUBNET}" -o "${iface}" -j MASQUERADE
    fi

    save_iptables
    print_success "L2TP firewall rules set."
}

add_l2tp_user() {
    local username="$1"
    local password="$2"
    local skip_restart="${3:-false}"

    print_step "Adding L2TP user: ${username}..."

    local escaped_user escaped_pass sed_user
    escaped_user=$(escape_ppp "$username")
    escaped_pass=$(escape_ppp "$password")
    sed_user=$(sed_escape_pattern "$escaped_user")

    # Remove existing entry (delete-before-add)
    sed -i "/^\"${sed_user}\" l2tpd /d" /etc/ppp/chap-secrets

    echo "\"${escaped_user}\" l2tpd \"${escaped_pass}\" *" >> /etc/ppp/chap-secrets
    chmod 600 /etc/ppp/chap-secrets

    if [ "$skip_restart" != "true" ]; then
        service_restart "xl2tpd"
    fi
    print_success "L2TP user added: ${username}"
}

remove_l2tp_user() {
    local username="$1"
    local escaped_user
    escaped_user=$(escape_ppp "$username")

    print_step "Removing L2TP user: ${username}..."
    local sed_user
    sed_user=$(sed_escape_pattern "$escaped_user")
    sed -i "/^\"${sed_user}\" l2tpd /d" /etc/ppp/chap-secrets

    service_restart "xl2tpd"
    print_success "L2TP user removed: ${username}"
}
#==============================================================================
# §17  WIREGUARD INSTALLATION & CONFIGURATION
#==============================================================================

install_wg_packages() {
    print_step "Installing WireGuard packages..."
    if is_debian_based; then
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL wireguard wireguard-tools" || {
            # Try kernel module approach for older kernels
            DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL wireguard-dkms wireguard-tools" || {
                print_error "Failed to install WireGuard."
                exit 1
            }
        }
    elif is_rhel_based; then
        install_epel
        eval "$PKG_INSTALL wireguard-tools" || {
            # Try ELrepo for kernel module
            if ! cmd_exists wg; then
                rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org &>/dev/null || true
                eval "$PKG_INSTALL https://www.elrepo.org/elrepo-release-$(rpm -E %rhel).el$(rpm -E %rhel).elrepo.noarch.rpm" 2>/dev/null || true
                eval "$PKG_INSTALL kmod-wireguard wireguard-tools" || {
                    print_error "Failed to install WireGuard."
                    exit 1
                }
            fi
        }
    fi
}

install_wireguard() {
    print_section "Installing WireGuard"

    install_wg_packages

    print_step "Generating WireGuard server keys..."
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard

    # Generate server key pair
    local wg_server_privkey wg_server_pubkey
    wg_server_privkey=$(wg genkey)
    wg_server_pubkey=$(echo "$wg_server_privkey" | wg pubkey)

    # Save public key to state
    save_state "WG_SERVER_PUBKEY" "$wg_server_pubkey"
    save_state "WG_NEXT_IP" "$WG_FIRST_CLIENT"

    configure_wireguard "$wg_server_privkey"
    configure_wireguard_firewall

    # Enable and start WireGuard
    service_enable "wg-quick@wg0"
    service_start "wg-quick@wg0"

    mark_vpn_installed "$VPN_WG"
    print_success "WireGuard installed and running (Server PubKey: ${wg_server_pubkey})"
}

configure_wireguard() {
    local server_privkey="$1"
    local dns1
    dns1=$(get_state "DNS1")
    local dns2
    dns2=$(get_state "DNS2")
    local iface
    iface=$(get_primary_iface)
    local ipv6_enabled
    ipv6_enabled=$(get_state "IPV6_ENABLED")

    print_step "Writing WireGuard server configuration..."

    local wg_address="${WG_SERVER_IP}/24"
    local dns_push="${dns1}"
    [ -n "$dns2" ] && [ "$dns2" != "$dns1" ] && dns_push="${dns1}, ${dns2}"

    local postup_rules="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${iface} -j MASQUERADE"
    local postdown_rules="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${iface} -j MASQUERADE"

    if [ "$ipv6_enabled" = "yes" ]; then
        wg_address="${WG_SERVER_IP}/24, fddd:2c4:2c4:2c4::1/64"
        postup_rules="${postup_rules}; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ${iface} -j MASQUERADE"
        postdown_rules="${postdown_rules}; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ${iface} -j MASQUERADE"
    fi

    cat > /etc/wireguard/wg0.conf << WG_CONF
# /etc/wireguard/wg0.conf - WireGuard Server Config
# Managed by vpn-setup.sh — DO NOT EDIT MANUALLY

[Interface]
Address = ${wg_address}
ListenPort = ${WG_PORT}
PrivateKey = ${server_privkey}
SaveConfig = false

PostUp = ${postup_rules}
PostDown = ${postdown_rules}

# DNS pushed to clients: ${dns_push}
# Clients are added below — do not edit the [Peer] sections manually
# vpn-setup managed peers:
WG_CONF
    chmod 600 /etc/wireguard/wg0.conf

    print_success "WireGuard server config written."
}

configure_wireguard_firewall() {
    print_step "Configuring WireGuard firewall rules..."
    fw_add INPUT -p udp --dport "${WG_PORT}" -j ACCEPT
    save_iptables
    print_success "WireGuard firewall rules set."
}

add_wireguard_user() {
    local username="$1"
    # Password not used for WireGuard — it's key-based

    print_step "Adding WireGuard user: ${username}..."

    local user_dir="${CERTS_DIR}/users/${username}"
    mkdir -p "$user_dir"

    # Capture old public key BEFORE generating new ones so we can hot-remove the old peer
    local old_pubkey=""
    [ -f "${user_dir}/wg_client.pub" ] && old_pubkey=$(cat "${user_dir}/wg_client.pub" 2>/dev/null || true)

    # Generate client key pair
    local client_privkey client_pubkey
    client_privkey=$(wg genkey)
    client_pubkey=$(echo "$client_privkey" | wg pubkey)
    local client_psk
    client_psk=$(wg genpsk)

    # Save client keys
    echo "$client_privkey" > "${user_dir}/wg_client.key"
    echo "$client_pubkey"  > "${user_dir}/wg_client.pub"
    echo "$client_psk"     > "${user_dir}/wg_client.psk"
    chmod 600 "${user_dir}/wg_client.key" "${user_dir}/wg_client.psk"

    # Assign IP
    local client_ip
    client_ip=$(next_wg_ip) || {
        print_error "Cannot assign WireGuard IP for ${username}."
        return 1
    }
    save_state "WG_NEXT_IP" "$(increment_ip "$client_ip")"

    # Save client IP for profile generation
    save_state "WG_IP_${username}" "$client_ip"

    # Remove any existing peer block for this user before appending fresh one
    # (guards against duplicate entries if the user is re-added)
    if [ -f /etc/wireguard/wg0.conf ]; then
        # Hot-remove old peer from running wg0 (old_pubkey was captured before key regen)
        if [ -n "$old_pubkey" ] && wg show wg0 &>/dev/null; then
            wg set wg0 peer "$old_pubkey" remove &>/dev/null || true
        fi
        python3 - "${username}" /etc/wireguard/wg0.conf << 'PYEOF_CLEAN' 2>/dev/null || true
import sys, re
uname = sys.argv[1]
with open(sys.argv[2], 'r') as f:
    content = f.read()
content = re.sub(r'\n# User: ' + re.escape(uname) + r'\n\[Peer\][^\[]*', '', content)
with open(sys.argv[2], 'w') as f:
    f.write(content)
PYEOF_CLEAN
    fi

    # Add peer to server config
    cat >> /etc/wireguard/wg0.conf << WG_PEER

# User: ${username}
[Peer]
PublicKey = ${client_pubkey}
PresharedKey = ${client_psk}
AllowedIPs = ${client_ip}/32
WG_PEER

    # Reload WireGuard if running
    if wg show wg0 &>/dev/null; then
        if wg addconf wg0 <(wg-quick strip wg0) &>/dev/null; then
            # Hot-add the specific peer so it's reachable immediately
            wg set wg0 peer "$client_pubkey" preshared-key <(echo "$client_psk") allowed-ips "${client_ip}/32" &>/dev/null || true
        else
            # Hot-reload failed; restart the service to pick up the new config
            service_restart "wg-quick@wg0"
        fi
    fi

    print_success "WireGuard user added: ${username} (IP: ${client_ip})"
}

remove_wireguard_user() {
    local username="$1"

    print_step "Removing WireGuard user: ${username}..."

    local user_dir="${CERTS_DIR}/users/${username}"
    local client_pubkey=""

    if [ -f "${user_dir}/wg_client.pub" ]; then
        client_pubkey=$(cat "${user_dir}/wg_client.pub")
    fi

    # Remove from server config — remove the [Peer] block for this user
    if [ -n "$client_pubkey" ]; then
        # Create temp file without the peer block
        python3 - "$client_pubkey" /etc/wireguard/wg0.conf << 'PYEOF' 2>/dev/null || \
        awk -v uname="${username}" '$0 == "# User: " uname{p=1;next} p && /^[[:space:]]*$/{p=0;next} !p{print}' /etc/wireguard/wg0.conf > /tmp/wg0_tmp.conf && mv /tmp/wg0_tmp.conf /etc/wireguard/wg0.conf || true
import sys, re

pubkey = sys.argv[1]
config_file = sys.argv[2]

with open(config_file, 'r') as f:
    content = f.read()

# Remove peer block containing this pubkey
pattern = r'\n# User: [^\n]+\n\[Peer\]\nPublicKey = ' + re.escape(pubkey) + r'[^\[]*'
content = re.sub(pattern, '', content)

with open(config_file, 'w') as f:
    f.write(content)
PYEOF
    fi

    # Remove from running WireGuard
    if [ -n "$client_pubkey" ] && wg show wg0 &>/dev/null; then
        wg set wg0 peer "$client_pubkey" remove &>/dev/null || true
    fi

    # Clean up keys
    rm -f "${user_dir}/wg_client.key" "${user_dir}/wg_client.pub" "${user_dir}/wg_client.psk"

    print_success "WireGuard user removed: ${username}"
}

#==============================================================================
# §18  OPENVPN INSTALLATION & CONFIGURATION
#==============================================================================

install_openvpn_packages() {
    print_step "Installing OpenVPN packages..."
    if is_debian_based; then
        DEBIAN_FRONTEND=noninteractive eval "$PKG_INSTALL openvpn" || {
            print_error "Failed to install OpenVPN."
            exit 1
        }
    elif is_rhel_based; then
        eval "$PKG_INSTALL openvpn" || {
            print_error "Failed to install OpenVPN."
            exit 1
        }
    fi
}

install_openvpn() {
    print_section "Installing OpenVPN"

    install_openvpn_packages

    print_step "Setting up OpenVPN PKI (OpenSSL)..."
    setup_openvpn_pki

    configure_openvpn
    setup_openvpn_auth_script
    configure_openvpn_firewall

    # Detect the correct service name (RHEL 8+ uses openvpn-server@server)
    local ovpn_svc
    ovpn_svc=$(get_openvpn_svc)
    save_state "OPENVPN_SERVICE" "$ovpn_svc"
    service_enable "$ovpn_svc"
    service_restart "$ovpn_svc"

    save_state "OVPN_NEXT_IP" "$OVPN_FIRST_CLIENT"
    mark_vpn_installed "$VPN_OVPN"
    print_success "OpenVPN installed and running."
}

setup_openvpn_pki() {
    mkdir -p "${OPENVPN_DIR}/server" "${OPENVPN_DIR}/auth" "${OPENVPN_DIR}/clients"
    chmod 700 "${OPENVPN_DIR}/auth"

    # Link or copy CA and server certs
    cp "${CERTS_DIR}/ca.crt"     "${OPENVPN_DIR}/server/ca.crt"
    cp "${CERTS_DIR}/server.crt" "${OPENVPN_DIR}/server/server.crt"
    cp "${CERTS_DIR}/server.key" "${OPENVPN_DIR}/server/server.key"
    chmod 600 "${OPENVPN_DIR}/server/server.key"

    # Generate TLS-crypt key
    if [ ! -f "${OPENVPN_DIR}/server/ta.key" ]; then
        openvpn --genkey secret "${OPENVPN_DIR}/server/ta.key" 2>/dev/null || \
        openvpn --genkey --secret "${OPENVPN_DIR}/server/ta.key" 2>/dev/null || {
            print_warning "Could not generate ta.key. Using openssl rand instead."
            openssl rand -out "${OPENVPN_DIR}/server/ta.key" 256
        }
    fi
    chmod 600 "${OPENVPN_DIR}/server/ta.key"

    # Generate Diffie-Hellman parameters
    if [ ! -f "${OPENVPN_DIR}/server/dh.pem" ]; then
        print_step "Generating DH parameters (this may take a moment)..."
        openssl dhparam -out "${OPENVPN_DIR}/server/dh.pem" 2048 2>/dev/null || {
            print_error "Failed to generate DH parameters."
            exit 1
        }
    fi

    print_success "OpenVPN PKI ready."
}

configure_openvpn() {
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local dns1
    dns1=$(get_state "DNS1")
    local dns2
    dns2=$(get_state "DNS2")
    local ipv6_enabled
    ipv6_enabled=$(get_state "IPV6_ENABLED")

    print_step "Writing OpenVPN server configuration..."

    local ovpn_dir="${OPENVPN_DIR}/server"
    local push_dns="push \"dhcp-option DNS ${dns1}\""
    if [ -n "$dns2" ] && [ "$dns2" != "$dns1" ]; then
        push_dns="${push_dns}
push \"dhcp-option DNS ${dns2}\""
    fi

    # OpenVPN 'server' directive needs plain network address without CIDR prefix
    local ovpn_network="${OVPN_SUBNET%%/*}"
    local server_directive="server ${ovpn_network} 255.255.255.0"
    local ipv6_directives=""
    if [ "$ipv6_enabled" = "yes" ]; then
        ipv6_directives="
server-ipv6 fddd:2c4:2c4:2c4::/64
push \"route-ipv6 2000::/3\""
    fi

    cat > "${OPENVPN_DIR}/server.conf" << OVPN_CONF
# /etc/openvpn/server.conf
# Managed by vpn-setup.sh — DO NOT EDIT MANUALLY

# Network
${server_directive}
${ipv6_directives}
port ${OVPN_PORT}
proto udp
dev tun

# Certificates
ca   ${ovpn_dir}/ca.crt
cert ${ovpn_dir}/server.crt
key  ${ovpn_dir}/server.key
dh   ${ovpn_dir}/dh.pem
tls-crypt ${ovpn_dir}/ta.key

# Security
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-GCM-SHA384
remote-cert-tls client

# Authentication: both certificate AND username/password required
verify-client-cert require
auth-user-pass-verify /etc/openvpn/auth/verify.sh via-file
script-security 2
username-as-common-name

# Client settings
${push_dns}
push "redirect-gateway def1 bypass-dhcp"

# Connection
keepalive 10 120
allow-compression no
max-clients 100
user nobody
group nogroup
persist-key
persist-tun

# Logging
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
mute 20
OVPN_CONF

    # nogroup may be nobody on RHEL
    if is_rhel_based; then
        sed -i 's/^group nogroup$/group nobody/' "${OPENVPN_DIR}/server.conf"
    fi

    print_success "OpenVPN server config written."
}

setup_openvpn_auth_script() {
    print_step "Setting up OpenVPN authentication script..."
    mkdir -p "${OPENVPN_DIR}/auth"
    # OpenVPN drops privs to nobody:nogroup (Debian) or nobody:nobody (RHEL)
    local ovpn_group="nogroup"
    is_rhel_based && ovpn_group="nobody"
    chown "root:${ovpn_group}" "${OPENVPN_DIR}/auth"
    chmod 750 "${OPENVPN_DIR}/auth"

    # Create empty credentials file — must be readable by nobody/nogroup (OpenVPN drops privs)
    touch "${OPENVPN_DIR}/auth/users.passwd"
    chown "root:${ovpn_group}" "${OPENVPN_DIR}/auth/users.passwd"
    chmod 640 "${OPENVPN_DIR}/auth/users.passwd"

    # Create verify script
    cat > "${OPENVPN_DIR}/auth/verify.sh" << 'VERIFY_SCRIPT'
#!/usr/bin/env bash
# OpenVPN username/password verification script
# Credentials stored as: username:sha256_hash

CREDS_FILE="/etc/openvpn/auth/users.passwd"

if [ ! -f "$1" ]; then
    exit 1
fi

USERNAME=$(head -1 "$1" 2>/dev/null)
PASSWORD=$(tail -1 "$1" 2>/dev/null)

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    exit 1
fi

# Compute SHA-256 hash of provided password
INPUT_HASH=$(printf '%s' "$PASSWORD" | sha256sum | awk '{print $1}')

# Look up stored hash — use awk for exact field match (grep -F can't anchor)
STORED_HASH=$(awk -F: -v user="$USERNAME" '$1 == user {print $2; exit}' "$CREDS_FILE" 2>/dev/null)

if [ -z "$STORED_HASH" ]; then
    exit 1
fi

if [ "$INPUT_HASH" = "$STORED_HASH" ]; then
    exit 0
fi

exit 1
VERIFY_SCRIPT
    chmod 755 "${OPENVPN_DIR}/auth/verify.sh"

    print_success "OpenVPN auth script installed."
}

configure_openvpn_firewall() {
    print_step "Configuring OpenVPN firewall rules..."
    local iface
    iface=$(get_primary_iface)

    fw_add INPUT -p udp --dport "${OVPN_PORT}" -j ACCEPT
    fw_add FORWARD -i tun0 -j ACCEPT
    fw_add FORWARD -o tun0 -j ACCEPT

    if ! iptables -t nat -C POSTROUTING -s "${OVPN_SUBNET}" -o "${iface}" -j MASQUERADE &>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${OVPN_SUBNET}" -o "${iface}" -j MASQUERADE
    fi

    save_iptables
    print_success "OpenVPN firewall rules set."
}

add_openvpn_user() {
    local username="$1"
    local password="$2"
    local skip_restart="${3:-false}"

    print_step "Adding OpenVPN user: ${username}..."

    # Add hashed password to credentials file
    local pass_hash
    pass_hash=$(hash_password "$password")

    # Remove existing entry (delete-before-add)
    local sed_uname
    sed_uname=$(sed_escape_pattern "$username")
    sed -i "/^${sed_uname}:/d" "${OPENVPN_DIR}/auth/users.passwd"

    echo "${username}:${pass_hash}" >> "${OPENVPN_DIR}/auth/users.passwd"
    local ovpn_group="nogroup"
    is_rhel_based && ovpn_group="nobody"
    chown "root:${ovpn_group}" "${OPENVPN_DIR}/auth/users.passwd"
    chmod 640 "${OPENVPN_DIR}/auth/users.passwd"

    # Assign IP (tracked in state)
    local client_ip
    client_ip=$(next_ovpn_ip) || {
        print_error "Cannot assign OpenVPN IP for ${username}."
        return 1
    }
    save_state "OVPN_IP_${username}" "$client_ip"
    save_state "OVPN_NEXT_IP" "$(increment_ip "$client_ip")"

    # Create client-specific config to assign fixed IP
    mkdir -p "${OPENVPN_DIR}/ccd"
    echo "ifconfig-push ${client_ip} ${OVPN_SERVER_IP}" > "${OPENVPN_DIR}/ccd/${username}"

    # Add ccd directive to server config if not already there
    if ! grep -q "^client-config-dir" "${OPENVPN_DIR}/server.conf" 2>/dev/null; then
        echo "client-config-dir ${OPENVPN_DIR}/ccd" >> "${OPENVPN_DIR}/server.conf"
    fi

    if [ "$skip_restart" != "true" ]; then
        service_restart "$(get_openvpn_svc)"
    fi
    print_success "OpenVPN user added: ${username} (IP: ${client_ip})"
}

remove_openvpn_user() {
    local username="$1"

    print_step "Removing OpenVPN user: ${username}..."

    # Remove from credentials file
    local sed_uname
    sed_uname=$(sed_escape_pattern "$username")
    sed -i "/^${sed_uname}:/d" "${OPENVPN_DIR}/auth/users.passwd"

    # Remove CCD file
    rm -f "${OPENVPN_DIR}/ccd/${username}"

    # Revoke certificate (add to CRL if needed — simplified version)
    local client_crt="${CERTS_DIR}/users/${username}/client.crt"
    if [ -f "$client_crt" ]; then
        print_info "Certificate for ${username} is no longer in credentials but key is not CRL'd."
        print_info "For full revocation, consider regenerating the CA or implementing a CRL."
    fi

    service_restart "$(get_openvpn_svc)"
    print_success "OpenVPN user removed: ${username}"
}
#==============================================================================
# §19  USER MANAGEMENT: CREATE & REMOVE USERS ACROSS ALL VPN TYPES
#==============================================================================

create_vpn_user() {
    local username="$1"
    local password="$2"
    local psk="$3"
    local skip_restart="${4:-false}"

    print_section "Creating VPN User: ${username}"

    # Generate client certificate (used by IKEv2 cert-auth and OpenVPN)
    generate_client_cert "$username" "$password" || {
        print_error "Failed to generate client certificate for ${username}. Aborting user creation."
        return 1
    }

    # Add to each installed VPN
    if vpn_is_installed "$VPN_IKEV2"; then
        add_ikev2_user "$username" "$password" "$skip_restart"
    fi

    if vpn_is_installed "$VPN_L2TP"; then
        add_l2tp_user "$username" "$password" "$skip_restart"
    fi

    if vpn_is_installed "$VPN_WG"; then
        add_wireguard_user "$username"
    fi

    if vpn_is_installed "$VPN_OVPN"; then
        add_openvpn_user "$username" "$password" "$skip_restart"
    fi

    # Register user in state
    register_user "$username"

    # Generate profile files
    create_profile_dir "$username"
    generate_all_profiles "$username" "$password" "$psk"

    print_success "VPN user '${username}' created successfully."
    echo ""
    echo -e "  ${CYAN}Profile files located at:${NC}"
    echo -e "  ${BOLD}${PROFILES_BASE}/${username}/${NC}"
}

remove_vpn_user() {
    local username="$1"

    print_section "Removing VPN User: ${username}"

    if vpn_is_installed "$VPN_IKEV2"; then
        remove_ikev2_user "$username"
    fi

    if vpn_is_installed "$VPN_L2TP"; then
        remove_l2tp_user "$username"
    fi

    if vpn_is_installed "$VPN_WG"; then
        remove_wireguard_user "$username"
    fi

    if vpn_is_installed "$VPN_OVPN"; then
        remove_openvpn_user "$username"
    fi

    # Remove profile directory
    local user_profile_dir="${PROFILES_BASE}/${username}"
    if [ -d "$user_profile_dir" ]; then
        rm -rf "$user_profile_dir"
        print_done "Profile files removed."
    fi

    # Remove cert directory
    local user_cert_dir="${CERTS_DIR}/users/${username}"
    if [ -d "$user_cert_dir" ]; then
        rm -rf "$user_cert_dir"
        print_done "Certificates removed."
    fi

    # Deregister from state
    deregister_user "$username"

    print_success "VPN user '${username}' removed."
}

#==============================================================================
# §20  PROFILE GENERATION: CREATE VPN CLIENT CONFIG FILES
#==============================================================================

create_profile_dir() {
    local username="$1"
    local user_dir="${PROFILES_BASE}/${username}"
    mkdir -p "$user_dir"
    chmod 700 "$user_dir"
}

generate_all_profiles() {
    local username="$1"
    local password="$2"
    local psk="${3:-}"

    print_section "Generating Profile Files for: ${username}"

    # Copy CA cert and P12 to profile dir
    cp "${CERTS_DIR}/ca.crt" "${PROFILES_BASE}/${username}/${username}_ca.crt"
    if [ -f "${CERTS_DIR}/users/${username}/client.p12" ]; then
        cp "${CERTS_DIR}/users/${username}/client.p12" "${PROFILES_BASE}/${username}/${username}_client_cert.p12"
    fi

    if vpn_is_installed "$VPN_IKEV2"; then
        generate_ikev2_eap_mobileconfig "$username"
        generate_ikev2_cert_mobileconfig "$username" "$password"
        generate_ikev2_sswan "$username" "$password"
        generate_ikev2_windows_ps1 "$username" "$password" "$psk"
    fi

    if vpn_is_installed "$VPN_WG"; then
        generate_wireguard_conf "$username"
    fi

    if vpn_is_installed "$VPN_OVPN"; then
        generate_openvpn_ovpn "$username"
    fi

    generate_connection_info "$username" "$password" "$psk"

    print_success "All profile files generated in: ${PROFILES_BASE}/${username}/"
}

generate_ikev2_eap_mobileconfig() {
    local username="$1"
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local profile_uuid display_uuid ca_uuid
    profile_uuid=$(generate_uuid)
    display_uuid=$(generate_uuid)
    ca_uuid=$(generate_uuid)

    local out_file="${PROFILES_BASE}/${username}/${username}_ikev2_eap.mobileconfig"

    print_step "Generating IKEv2 EAP (user/pass) mobileconfig..."

    # ServerCertificateIssuerCommonName: only valid for self-signed.
    # In LE mode the issuer is Let's Encrypt's intermediate CA (R11/E1/etc.) — hardcoding
    # "VPN Root CA" here would cause iOS to reject the server cert.
    local issuer_key=""
    if ! is_letsencrypt; then
        issuer_key="                <key>ServerCertificateIssuerCommonName</key>
                <string>VPN Root CA</string>"
    fi

    # Build the CA cert payload (only needed for self-signed; LE is natively trusted)
    local ca_payload=""
    if ! is_letsencrypt; then
        local ca_b64
        ca_b64=$(b64_cert "${CERTS_DIR}/ca.crt")
        ca_payload="        <dict>
            <key>PayloadContent</key>
            <data>
${ca_b64}
            </data>
            <key>PayloadDescription</key>
            <string>VPN Root CA Certificate</string>
            <key>PayloadDisplayName</key>
            <string>VPN Root CA</string>
            <key>PayloadIdentifier</key>
            <string>com.vpn.ca.${username}</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>${ca_uuid}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>"
    fi

    cat > "$out_file" << MCONFIG_EAP
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>IKEv2</key>
            <dict>
                <key>AuthenticationMethod</key>
                <string>None</string>
                <key>ExtendedAuthEnabled</key>
                <integer>1</integer>
                <key>LocalIdentifier</key>
                <string>${username}</string>
                <key>RemoteAddress</key>
                <string>${server_addr}</string>
                <key>RemoteIdentifier</key>
                <string>${server_addr}</string>
                <key>AuthName</key>
                <string>${username}</string>
                <key>AuthPassword</key>
                <string></string>
${issuer_key}
                <key>IKESecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256-GCM</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>20</integer>
                </dict>
                <key>ChildSecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256-GCM</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>20</integer>
                </dict>
            </dict>
            <key>PayloadDescription</key>
            <string>IKEv2 VPN (Username/Password) for ${username}</string>
            <key>PayloadDisplayName</key>
            <string>IKEv2 VPN - ${username}</string>
            <key>PayloadIdentifier</key>
            <string>com.vpn.ikev2.eap.${username}</string>
            <key>PayloadType</key>
            <string>com.apple.vpn.managed</string>
            <key>PayloadUUID</key>
            <string>${display_uuid}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>UserDefinedName</key>
            <string>IKEv2 VPN (${username})</string>
            <key>VPNType</key>
            <string>IKEv2</string>
        </dict>
${ca_payload}
    </array>
    <key>PayloadDescription</key>
    <string>IKEv2 VPN configuration for ${username} (Username/Password)</string>
    <key>PayloadDisplayName</key>
    <string>IKEv2 VPN - ${server_addr} (EAP)</string>
    <key>PayloadIdentifier</key>
    <string>com.vpn.profile.eap.${username}</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${profile_uuid}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
MCONFIG_EAP

    chmod 600 "$out_file"
    print_done "IKEv2 EAP mobileconfig: ${out_file}"
}

generate_ikev2_cert_mobileconfig() {
    local username="$1"
    local password="$2"   # P12 password
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")

    local profile_uuid vpn_uuid cert_uuid ca_uuid
    profile_uuid=$(generate_uuid)
    vpn_uuid=$(generate_uuid)
    cert_uuid=$(generate_uuid)
    ca_uuid=$(generate_uuid)

    local p12_b64
    p12_b64=$(b64_file "${CERTS_DIR}/users/${username}/client.p12")

    # Build CA cert payload (only for self-signed; LE is natively trusted)
    local ca_payload=""
    if ! is_letsencrypt; then
        local ca_b64
        ca_b64=$(b64_cert "${CERTS_DIR}/ca.crt")
        ca_payload="        <dict>
            <key>PayloadContent</key>
            <data>
${ca_b64}
            </data>
            <key>PayloadDescription</key>
            <string>VPN Root CA Certificate</string>
            <key>PayloadDisplayName</key>
            <string>VPN Root CA</string>
            <key>PayloadIdentifier</key>
            <string>com.vpn.ca.cert.${username}</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadUUID</key>
            <string>${ca_uuid}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>"
    fi

    local out_file="${PROFILES_BASE}/${username}/${username}_ikev2_cert.mobileconfig"

    print_step "Generating IKEv2 Certificate mobileconfig..."

    cat > "$out_file" << MCONFIG_CERT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>IKEv2</key>
            <dict>
                <key>AuthenticationMethod</key>
                <string>Certificate</string>
                <key>ExtendedAuthEnabled</key>
                <integer>0</integer>
                <key>LocalIdentifier</key>
                <string>${username}@cert.vpn</string>
                <key>PayloadCertificateUUID</key>
                <string>${cert_uuid}</string>
                <key>RemoteAddress</key>
                <string>${server_addr}</string>
                <key>RemoteIdentifier</key>
                <string>${server_addr}</string>
                <key>CertificateType</key>
                <string>RSA</string>
                <key>IKESecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256-GCM</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>20</integer>
                </dict>
                <key>ChildSecurityAssociationParameters</key>
                <dict>
                    <key>EncryptionAlgorithm</key>
                    <string>AES-256-GCM</string>
                    <key>IntegrityAlgorithm</key>
                    <string>SHA2-256</string>
                    <key>DiffieHellmanGroup</key>
                    <integer>20</integer>
                </dict>
            </dict>
            <key>PayloadDescription</key>
            <string>IKEv2 VPN (Certificate) for ${username}</string>
            <key>PayloadDisplayName</key>
            <string>IKEv2 VPN Cert - ${username}</string>
            <key>PayloadIdentifier</key>
            <string>com.vpn.ikev2.cert.${username}</string>
            <key>PayloadType</key>
            <string>com.apple.vpn.managed</string>
            <key>PayloadUUID</key>
            <string>${vpn_uuid}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>UserDefinedName</key>
            <string>IKEv2 VPN Cert (${username})</string>
            <key>VPNType</key>
            <string>IKEv2</string>
        </dict>
        <dict>
            <key>Password</key>
            <string>${password}</string>
            <key>PayloadContent</key>
            <data>
${p12_b64}
            </data>
            <key>PayloadDescription</key>
            <string>VPN Client Certificate for ${username}</string>
            <key>PayloadDisplayName</key>
            <string>${username} VPN Certificate</string>
            <key>PayloadIdentifier</key>
            <string>com.vpn.client.cert.${username}</string>
            <key>PayloadType</key>
            <string>com.apple.security.pkcs12</string>
            <key>PayloadUUID</key>
            <string>${cert_uuid}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
${ca_payload}
    </array>
    <key>PayloadDescription</key>
    <string>IKEv2 VPN (Certificate) for ${username}</string>
    <key>PayloadDisplayName</key>
    <string>IKEv2 VPN Cert - ${server_addr}</string>
    <key>PayloadIdentifier</key>
    <string>com.vpn.profile.cert.${username}</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${profile_uuid}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
MCONFIG_CERT

    chmod 600 "$out_file"
    print_done "IKEv2 Certificate mobileconfig: ${out_file}"
}

generate_ikev2_sswan() {
    local username="$1"
    local password="$2"
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")

    local uuid1 uuid2
    uuid1=$(generate_uuid | tr '[:upper:]' '[:lower:]')
    uuid2=$(generate_uuid | tr '[:upper:]' '[:lower:]')

    local p12_b64
    p12_b64=$(b64_file "${CERTS_DIR}/users/${username}/client.p12")

    local out_file="${PROFILES_BASE}/${username}/${username}_ikev2.sswan"
    local out_file_cert="${PROFILES_BASE}/${username}/${username}_ikev2_cert.sswan"

    print_step "Generating IKEv2 Android strongSwan profile..."

    # In LE mode, omit remote.cert entirely — Android strongSwan falls back to the
    # system trust store (which includes LE's root CA). Embedding our own CA cert
    # would cause validation failure because LE certs are not signed by our CA.
    if is_letsencrypt; then
        cat > "$out_file" << SSWAN_JSON_LE
{
  "uuid": "${uuid1}",
  "name": "IKEv2 VPN (${username}) - EAP",
  "type": "ikev2-eap",
  "remote": {
    "addr": "${server_addr}",
    "id": "${server_addr}"
  },
  "local": {
    "eap_id": "${username}"
  },
  "password": "${password}"
}
SSWAN_JSON_LE
        cat > "$out_file_cert" << SSWAN_CERT_JSON_LE
{
  "uuid": "${uuid2}",
  "name": "IKEv2 VPN (${username}) - Certificate",
  "type": "ikev2-cert",
  "remote": {
    "addr": "${server_addr}",
    "id": "${server_addr}"
  },
  "local": {
    "p12": "${p12_b64}",
    "password": "${password}"
  }
}
SSWAN_CERT_JSON_LE
    else
        local ca_b64
        ca_b64=$(b64_cert "${CERTS_DIR}/ca.crt")
        cat > "$out_file" << SSWAN_JSON
{
  "uuid": "${uuid1}",
  "name": "IKEv2 VPN (${username}) - EAP",
  "type": "ikev2-eap",
  "remote": {
    "addr": "${server_addr}",
    "id": "${server_addr}",
    "cert": "${ca_b64}"
  },
  "local": {
    "eap_id": "${username}"
  },
  "password": "${password}"
}
SSWAN_JSON
        cat > "$out_file_cert" << SSWAN_CERT_JSON
{
  "uuid": "${uuid2}",
  "name": "IKEv2 VPN (${username}) - Certificate",
  "type": "ikev2-cert",
  "remote": {
    "addr": "${server_addr}",
    "id": "${server_addr}",
    "cert": "${ca_b64}"
  },
  "local": {
    "p12": "${p12_b64}",
    "password": "${password}"
  }
}
SSWAN_CERT_JSON
    fi

    chmod 600 "$out_file" "$out_file_cert"
    print_done "IKEv2 Android profiles: ${out_file}, ${out_file_cert}"
}

generate_ikev2_windows_ps1() {
    local username="$1"
    local password="$2"
    local psk="${3:-}"
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")

    local out_file="${PROFILES_BASE}/${username}/${username}_ikev2_windows.ps1"

    print_step "Generating IKEv2 Windows PowerShell setup script..."

    cat > "$out_file" << WIN_PS1
# IKEv2 VPN Setup for Windows — User: ${username}
# Run this script as Administrator in PowerShell
# Generated by vpn-setup.sh

param(
    [string]\$VpnName = "IKEv2 VPN (${username})",
    [string]\$ServerAddress = "${server_addr}"
)

Write-Host "Setting up IKEv2 VPN: \$VpnName" -ForegroundColor Cyan

# Remove existing VPN connection if present
if (Get-VpnConnection -Name \$VpnName -ErrorAction SilentlyContinue) {
    Remove-VpnConnection -Name \$VpnName -Force
    Write-Host "Removed existing VPN connection."
}

# Install CA Certificate (only needed for self-signed server certs)
# In Let's Encrypt mode the server cert is publicly trusted — no CA import required.
\$caCertPath = Join-Path \$PSScriptRoot "${username}_ca.crt"
\$isLetsEncrypt = $(is_letsencrypt && echo '$true' || echo '$false')
if (-not \$isLetsEncrypt) {
    if (Test-Path \$caCertPath) {
        Import-Certificate -FilePath \$caCertPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
        Write-Host "CA certificate installed." -ForegroundColor Green
    } else {
        Write-Warning "CA certificate not found at \$caCertPath. Import it manually."
    }
} else {
    Write-Host "Let's Encrypt certificate in use — no CA import needed." -ForegroundColor Cyan
}

# Install Client Certificate (P12)
\$p12Path = Join-Path \$PSScriptRoot "${username}_client_cert.p12"
if (Test-Path \$p12Path) {
    \$p12Password = ConvertTo-SecureString "${password}" -AsPlainText -Force
    Import-PfxCertificate -FilePath \$p12Path -CertStoreLocation Cert:\CurrentUser\My -Password \$p12Password | Out-Null
    Write-Host "Client certificate installed." -ForegroundColor Green
}

# Add IKEv2 VPN connection (EAP/username-password mode)
Add-VpnConnection \`
    -Name \$VpnName \`
    -ServerAddress \$ServerAddress \`
    -TunnelType IKEv2 \`
    -AuthenticationMethod Eap \`
    -EncryptionLevel Required \`
    -RememberCredential \$true \`
    -SplitTunneling \$false \`
    -PassThru

# Configure IKEv2 security settings
Set-VpnConnectionIPsecConfiguration \`
    -ConnectionName \$VpnName \`
    -AuthenticationTransformConstants GCMAES256 \`
    -CipherTransformConstants GCMAES256 \`
    -EncryptionMethod AES256 \`
    -IntegrityCheckMethod SHA256 \`
    -DHGroup ECP384 \`
    -PfsGroup ECP384 \`
    -Force

Write-Host ""
Write-Host "VPN connection '\$VpnName' created successfully!" -ForegroundColor Green
Write-Host "Username: ${username}" -ForegroundColor Yellow
Write-Host "Server:   ${server_addr}" -ForegroundColor Yellow
Write-Host ""
Write-Host "Connect via: Settings > Network & Internet > VPN" -ForegroundColor Cyan

# Optional: Create certificate-based VPN connection
\$certVpnName = "IKEv2 VPN Cert (${username})"
Add-VpnConnection \`
    -Name \$certVpnName \`
    -ServerAddress \$ServerAddress \`
    -TunnelType IKEv2 \`
    -AuthenticationMethod MachineCertificate \`
    -EncryptionLevel Required \`
    -SplitTunneling \$false \`
    -PassThru 2>\$null

Write-Host "Certificate-based VPN '\$certVpnName' also created." -ForegroundColor Green
WIN_PS1

    chmod 644 "$out_file"
    print_done "Windows PowerShell script: ${out_file}"
}

generate_wireguard_conf() {
    local username="$1"
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local dns1
    dns1=$(get_state "DNS1")
    local dns2
    dns2=$(get_state "DNS2")
    local ipv6_enabled
    ipv6_enabled=$(get_state "IPV6_ENABLED")

    local user_dir="${CERTS_DIR}/users/${username}"
    if [ ! -f "${user_dir}/wg_client.key" ]; then
        print_warning "WireGuard keys not found for ${username}. Skipping WG profile."
        return
    fi

    local client_privkey server_pubkey client_ip client_psk
    client_privkey=$(cat "${user_dir}/wg_client.key")
    server_pubkey=$(get_state "WG_SERVER_PUBKEY")
    client_ip=$(get_state "WG_IP_${username}")
    client_psk=$(cat "${user_dir}/wg_client.psk" 2>/dev/null || echo "")

    local client_address="${client_ip}/32"
    local dns_entry="${dns1}"
    [ -n "$dns2" ] && [ "$dns2" != "$dns1" ] && dns_entry="${dns1}, ${dns2}"

    local allowed_ips="0.0.0.0/0"
    if [ "$ipv6_enabled" = "yes" ]; then
        client_address="${client_ip}/32, fddd:2c4:2c4:2c4::$(echo "$client_ip" | awk -F. '{print $4}')/128"
        allowed_ips="0.0.0.0/0, ::/0"
    fi

    local psk_line=""
    [ -n "$client_psk" ] && psk_line="PresharedKey = ${client_psk}"

    local out_file="${PROFILES_BASE}/${username}/${username}_wireguard.conf"

    print_step "Generating WireGuard client config..."

    cat > "$out_file" << WG_CLIENT
[Interface]
# WireGuard Config for: ${username}
# Generated by vpn-setup.sh
Address = ${client_address}
PrivateKey = ${client_privkey}
DNS = ${dns_entry}

[Peer]
PublicKey = ${server_pubkey}
${psk_line}
Endpoint = ${server_addr}:${WG_PORT}
AllowedIPs = ${allowed_ips}
PersistentKeepalive = 25
WG_CLIENT

    chmod 600 "$out_file"
    print_done "WireGuard config: ${out_file}"
}

generate_openvpn_ovpn() {
    local username="$1"
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local dns1
    dns1=$(get_state "DNS1")

    local ca_crt_content client_crt_content client_key_content ta_key_content

    # In LE mode, use the LE intermediate chain so the client can verify the LE server cert.
    # In self-signed mode, use our own CA cert.
    if is_letsencrypt; then
        ca_crt_content=$(cat "${CERTS_DIR}/le_chain.crt")
    else
        ca_crt_content=$(cat "${CERTS_DIR}/ca.crt")
    fi
    client_crt_content=$(cat "${CERTS_DIR}/users/${username}/client.crt")
    client_key_content=$(cat "${CERTS_DIR}/users/${username}/client.key")
    ta_key_content=$(cat "${OPENVPN_DIR}/server/ta.key")

    local out_file="${PROFILES_BASE}/${username}/${username}_openvpn.ovpn"

    print_step "Generating OpenVPN .ovpn profile..."

    cat > "$out_file" << OVPN_PROFILE
# OpenVPN Client Profile for: ${username}
# Generated by vpn-setup.sh
# Both certificate AND username/password authentication are required.

client
dev tun
proto udp
remote ${server_addr} ${OVPN_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun

# Authentication
auth-user-pass
remote-cert-tls server

# Security
cipher AES-256-GCM
auth SHA256
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-GCM-SHA384

verb 3
mute 20

# Your username: ${username}
# Enter your VPN password when prompted

<ca>
${ca_crt_content}
</ca>

<cert>
${client_crt_content}
</cert>

<key>
${client_key_content}
</key>

<tls-crypt>
${ta_key_content}
</tls-crypt>
OVPN_PROFILE

    chmod 600 "$out_file"
    print_done "OpenVPN profile: ${out_file}"
}

generate_connection_info() {
    local username="$1"
    local password="$2"
    local psk="${3:-}"
    local server_addr
    server_addr=$(get_state "SERVER_ADDRESS")
    local addr_type
    addr_type=$(get_state "ADDRESS_TYPE")
    local psk_stored
    psk_stored=$(get_state "L2TP_PSK")
    local dns1 dns2
    dns1=$(get_state "DNS1")
    dns2=$(get_state "DNS2")
    local wg_ip ovpn_ip
    # When called from a PSK-only update we don't have the plaintext password.
    # Show a placeholder rather than a blank field.
    local display_password="${password:-[unchanged — re-run Update User to regenerate with new password]}"
    wg_ip=$(get_state "WG_IP_${username}")
    ovpn_ip=$(get_state "OVPN_IP_${username}")

    local out_file="${PROFILES_BASE}/${username}/${username}_connection_info.txt"

    print_step "Generating connection info summary..."

    cat > "$out_file" << INFO
================================================================================
  VPN Connection Information for: ${username}
  Generated: $(date)
================================================================================

SERVER DETAILS
--------------
  Server Address : ${server_addr}
  Address Type   : ${addr_type}
  DNS Server 1   : ${dns1}
  DNS Server 2   : ${dns2}

CREDENTIALS
-----------
  Username       : ${username}
  Password       : ${display_password}
  Pre-Shared Key : ${psk_stored:-${psk}}

================================================================================
 IKEv2/IPsec (strongSwan)
================================================================================
  Server          : ${server_addr}
  Type            : IKEv2
  Authentication  : EAP-MSCHAPv2 (username/password) OR Certificate
  Username        : ${username}
  Password        : ${display_password}

  Profile Files:
    iOS/macOS (user/pass)  : ${username}_ikev2_eap.mobileconfig
    iOS/macOS (certificate): ${username}_ikev2_cert.mobileconfig
    Android (strongSwan)   : ${username}_ikev2.sswan
    Windows (PowerShell)   : ${username}_ikev2_windows.ps1
    Client Certificate P12 : ${username}_client_cert.p12
    P12 Password           : ${display_password}

  Manual Setup (Windows/Linux):
    VPN Type     : IKEv2
    Server       : ${server_addr}
    Auth         : EAP-MSCHAPv2
    Username     : ${username}
    Password     : ${display_password}

================================================================================
 L2TP/IPsec
================================================================================
  Server          : ${server_addr}
  Type            : L2TP/IPsec with Pre-Shared Key
  Pre-Shared Key  : ${psk_stored:-${psk}}
  Username        : ${username}
  Password        : ${display_password}

  Manual Setup (Windows/macOS/iOS/Android):
    VPN Type         : L2TP/IPsec
    Server           : ${server_addr}
    Pre-Shared Key   : ${psk_stored:-${psk}}
    Username         : ${username}
    Password         : ${display_password}

================================================================================
 WireGuard
================================================================================
  Config File     : ${username}_wireguard.conf
  Client IP       : ${wg_ip:-N/A}
  Server Endpoint : ${server_addr}:${WG_PORT}

  Import the .conf file into the WireGuard app.
  No username/password needed — key-based authentication.

================================================================================
 OpenVPN
================================================================================
  Config File     : ${username}_openvpn.ovpn
  Client IP       : ${ovpn_ip:-N/A}
  Authentication  : Certificate + Username/Password
  Username        : ${username}
  Password        : ${display_password}

  Import the .ovpn file into any OpenVPN client.
  Enter username/password when prompted.

================================================================================
 CA CERTIFICATE
================================================================================
  File: ${username}_ca.crt
$(is_letsencrypt && echo "  This certificate is NOT needed for device trust — the server uses a
  Let's Encrypt certificate which is publicly trusted on all devices.
  It is included for reference only (signs client certificates for IKEv2 cert auth)." \
|| echo "  Import this certificate as a trusted CA on your device/system.
  Required for IKEv2 (EAP and Certificate) and OpenVPN on devices
  that do not automatically trust self-signed certificates.")

================================================================================
INFO

    chmod 600 "$out_file"
    print_done "Connection info: ${out_file}"
}
#==============================================================================
# §21  RE-RUN MANAGEMENT MENU
#==============================================================================

show_status_summary() {
    load_all_state
    local installed_vpns user_count
    installed_vpns=$(get_state "INSTALLED_VPNS")
    user_count=$(count_users)

    echo ""
    echo -e "${CYAN}${BOLD}  VPN Server Status${NC}"
    echo -e "  ${DIM}────────────────────────────────────────${NC}"
    echo -e "  Server    : ${BOLD}$(get_state "SERVER_ADDRESS")${NC} ($(get_state "ADDRESS_TYPE"))"
    echo -e "  VPNs      : ${BOLD}${installed_vpns:-none}${NC}"
    echo -e "  IPv6      : ${BOLD}$(get_state "IPV6_ENABLED")${NC}"
    echo -e "  DNS       : ${BOLD}$(get_state "DNS1")${NC} / ${BOLD}$(get_state "DNS2")${NC}"
    echo -e "  Users     : ${BOLD}${user_count}${NC}"
    echo -e "  Profiles  : ${BOLD}${PROFILES_BASE}${NC}"
    echo ""
}

show_management_menu() {
    while true; do
        print_header
        show_status_summary

        echo -e "  ${BOLD}Management Options:${NC}"
        echo ""
        echo -e "  ${BOLD}1)${NC} Add / Remove VPN user(s)"
        echo -e "  ${BOLD}2)${NC} Change Server DNS name / IP"
        echo -e "  ${BOLD}3)${NC} Change VPN DNS resolver(s)"
        echo -e "  ${BOLD}4)${NC} Update VPN servers"
        echo -e "  ${BOLD}5)${NC} Uninstall VPN server(s)"
        echo -e "  ${BOLD}6)${NC} Advanced"
        echo -e "  ${BOLD}0)${NC} Exit"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r menu_choice

        case "$menu_choice" in
            1) manage_users_menu ;;
            2) change_server_address_menu ;;
            3) change_dns_menu ;;
            4) update_vpn_menu ;;
            5) uninstall_vpn_menu ;;
            6) show_advanced_menu ;;
            0) echo ""; print_info "Exiting."; exit 0 ;;
            *) print_warning "Invalid choice. Please enter 0-6." ;;
        esac
    done
}

#==============================================================================
# §22  USER MANAGEMENT MENU
#==============================================================================

manage_users_menu() {
    while true; do
        print_section "User Management"
        echo -e "  Current users:"
        local users
        users=$(get_users_list)
        if [ -z "$users" ]; then
            echo -e "  ${DIM}  (no users)${NC}"
        else
            echo "$users" | while read -r u; do
                echo -e "    ${CYAN}•${NC} $u"
            done
        fi
        echo ""
        echo -e "  ${BOLD}1)${NC} Add a user"
        echo -e "  ${BOLD}2)${NC} Add multiple users"
        echo -e "  ${BOLD}3)${NC} Remove a user"
        echo -e "  ${BOLD}4)${NC} Update user(s)"
        echo -e "  ${BOLD}5)${NC} Export user list"
        echo -e "  ${BOLD}6)${NC} List users and profile paths"
        echo -e "  ${BOLD}0)${NC} Back"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r u_choice

        case "$u_choice" in
            1) add_user_menu ;;
            2) batch_add_users_menu ;;
            3) remove_user_menu ;;
            4) update_users_menu ;;
            5) export_user_list ;;
            6) list_users_detail ;;
            0) return ;;
            *) print_warning "Invalid choice." ;;
        esac
    done
}

add_user_menu() {
    print_section "Add VPN User"
    local new_username new_password new_psk confirm_pass confirm_psk

    # Username
    while true; do
        echo -en "${YELLOW}  ?${NC}  New username (or 0 to cancel): "
        read -r new_username
        [ "$new_username" = "0" ] && return
        if [ -z "$new_username" ]; then
            print_warning "Username cannot be empty."
        elif ! echo "$new_username" | grep -qE '^[a-zA-Z0-9._@-]+$'; then
            print_warning "Username may only contain letters, digits, '.', '_', '@', '-'."
        elif in_list "$new_username" "$(get_state "USERS_LIST")"; then
            print_warning "User '${new_username}' already exists."
        else
            break
        fi
    done

    # Password
    while true; do
        echo -en "${YELLOW}  ?${NC}  Password (hidden): "
        read -rs new_password
        echo ""
        echo -en "${YELLOW}  ?${NC}  Confirm password: "
        read -rs confirm_pass
        echo ""
        if [ -z "$new_password" ]; then
            print_warning "Password cannot be empty."
        elif [ "$new_password" != "$confirm_pass" ]; then
            print_warning "Passwords do not match."
        else
            break
        fi
    done

    # PSK
    while true; do
        echo -en "${YELLOW}  ?${NC}  Pre-Shared Key (hidden, used for IKEv2/L2TP): "
        read -rs new_psk
        echo ""
        echo -en "${YELLOW}  ?${NC}  Confirm PSK: "
        read -rs confirm_psk
        echo ""
        if [ -z "$new_psk" ]; then
            print_warning "PSK cannot be empty."
        elif [ "$new_psk" != "$confirm_psk" ]; then
            print_warning "PSKs do not match."
        else
            break
        fi
    done

    create_vpn_user "$new_username" "$new_password" "$new_psk"
    press_enter
}

#------------------------------------------------------------------------------
# BATCH ADD USERS
#------------------------------------------------------------------------------

batch_add_users_menu() {
    while true; do
        print_section "Add Multiple Users"
        echo -e "  ${BOLD}1)${NC} Interactive  — add users one by one"
        echo -e "  ${BOLD}2)${NC} Import from CSV file"
        echo -e "  ${BOLD}0)${NC} Back"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r choice
        case "$choice" in
            1) batch_add_interactive ;;
            2) batch_add_from_csv ;;
            0) return ;;
            *) print_warning "Invalid choice." ;;
        esac
    done
}

batch_add_interactive() {
    print_section "Batch Add Users — Interactive"
    local total_created=0

    while true; do
        local new_username new_password new_psk confirm_pass confirm_psk

        # Username
        while true; do
            echo -en "${YELLOW}  ?${NC}  New username (or 0 to stop): "
            read -r new_username
            [ "$new_username" = "0" ] && break 2
            if [ -z "$new_username" ]; then
                print_warning "Username cannot be empty."
            elif ! echo "$new_username" | grep -qE '^[a-zA-Z0-9_-]+$'; then
                print_warning "Username may only contain letters, digits, underscores, hyphens."
            elif in_list "$new_username" "$(get_state "USERS_LIST")"; then
                print_warning "User '${new_username}' already exists."
            else
                break
            fi
        done

        # Password
        while true; do
            echo -en "${YELLOW}  ?${NC}  Password (hidden): "
            read -rs new_password
            echo ""
            echo -en "${YELLOW}  ?${NC}  Confirm password: "
            read -rs confirm_pass
            echo ""
            if [ -z "$new_password" ]; then
                print_warning "Password cannot be empty."
            elif [ "$new_password" != "$confirm_pass" ]; then
                print_warning "Passwords do not match."
            else
                break
            fi
        done

        # PSK
        while true; do
            echo -en "${YELLOW}  ?${NC}  Pre-Shared Key (hidden): "
            read -rs new_psk
            echo ""
            echo -en "${YELLOW}  ?${NC}  Confirm PSK: "
            read -rs confirm_psk
            echo ""
            if [ -z "$new_psk" ]; then
                print_warning "PSK cannot be empty."
            elif [ "$new_psk" != "$confirm_psk" ]; then
                print_warning "PSKs do not match."
            else
                break
            fi
        done

        create_vpn_user "$new_username" "$new_password" "$new_psk" "true"
        ((total_created++))

        echo ""
        if ! ask_yn "  Add another user?" "n"; then
            break
        fi
        echo ""
    done

    # Single restart after all users are written
    if [ "$total_created" -gt 0 ]; then
        if vpn_is_installed "$VPN_IKEV2"; then
            print_step "Restarting strongSwan..."
            ipsec restart &>/dev/null || true
        fi
        if vpn_is_installed "$VPN_L2TP"; then
            print_step "Restarting xl2tpd..."
            service_restart "xl2tpd"
        fi
        if vpn_is_installed "$VPN_OVPN"; then
            print_step "Restarting OpenVPN..."
            service_restart "$(get_openvpn_svc)"
        fi
    fi

    echo ""
    print_info "Batch add complete: ${total_created} user(s) created."
    press_enter
}

batch_add_from_csv() {
    print_section "Batch Add Users — CSV Import"
    echo -e "  CSV format: ${BOLD}username,password,psk${NC}  (# lines and blank lines are skipped)"
    echo ""
    echo -en "${YELLOW}  ?${NC}  Path to CSV file (or 0 to cancel): "
    read -r csv_path
    [ "$csv_path" = "0" ] && return

    if [ ! -f "$csv_path" ]; then
        print_error "File not found: ${csv_path}"
        press_enter
        return
    fi

    # Phase 1 — validate all lines
    local line_num=0
    local error_count=0
    local valid_users=()
    local valid_passes=()
    local valid_psks=()
    local seen_in_file=""

    while IFS= read -r line || [ -n "$line" ]; do
        ((line_num++))
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        local csv_user csv_pass csv_psk
        csv_user=$(echo "$line" | cut -d',' -f1)
        csv_pass=$(echo "$line" | cut -d',' -f2)
        csv_psk=$(echo "$line"  | cut -d',' -f3)

        local row_ok=true

        if [ -z "$csv_user" ] || ! echo "$csv_user" | grep -qE '^[a-zA-Z0-9_-]+$'; then
            print_warning "Line ${line_num}: invalid username '${csv_user}'"
            row_ok=false
        elif in_list "$csv_user" "$(get_state "USERS_LIST")"; then
            print_warning "Line ${line_num}: user '${csv_user}' already exists"
            row_ok=false
        elif in_list "$csv_user" "$seen_in_file"; then
            print_warning "Line ${line_num}: duplicate username '${csv_user}' in file"
            row_ok=false
        fi

        if [ -z "$csv_pass" ]; then
            print_warning "Line ${line_num}: password is empty"
            row_ok=false
        fi

        if [ -z "$csv_psk" ]; then
            print_warning "Line ${line_num}: PSK is empty"
            row_ok=false
        fi

        if $row_ok; then
            valid_users+=("$csv_user")
            valid_passes+=("$csv_pass")
            valid_psks+=("$csv_psk")
            seen_in_file=$(add_to_list "$csv_user" "$seen_in_file")
        else
            ((error_count++))
        fi
    done < "$csv_path"

    local valid_count="${#valid_users[@]}"
    echo ""
    echo -e "  Valid entries  : ${GREEN}${valid_count}${NC}"
    echo -e "  Invalid entries: ${RED}${error_count}${NC}"

    if [ "$valid_count" -eq 0 ]; then
        print_warning "No valid entries to import."
        press_enter
        return
    fi

    # Phase 2 — confirm
    if [ "$error_count" -gt 0 ]; then
        echo ""
        if ! ask_yn "  Proceed with ${valid_count} valid entries (skip invalid)?" "n"; then
            print_info "Cancelled."
            press_enter
            return
        fi
    else
        if ! ask_yn "  Create ${valid_count} user(s)?" "y"; then
            print_info "Cancelled."
            press_enter
            return
        fi
    fi

    # Phase 3 — create (skip per-user restart; restart once at the end)
    local created=0 failed=0
    local i
    for i in "${!valid_users[@]}"; do
        if create_vpn_user "${valid_users[$i]}" "${valid_passes[$i]}" "${valid_psks[$i]}" "true"; then
            ((created++))
        else
            print_error "Failed to create user '${valid_users[$i]}'"
            ((failed++))
        fi
    done

    # Single restart after all users are written
    if [ "$created" -gt 0 ]; then
        if vpn_is_installed "$VPN_IKEV2"; then
            print_step "Restarting strongSwan..."
            ipsec restart &>/dev/null || true
        fi
        if vpn_is_installed "$VPN_L2TP"; then
            print_step "Restarting xl2tpd..."
            service_restart "xl2tpd"
        fi
        if vpn_is_installed "$VPN_OVPN"; then
            print_step "Restarting OpenVPN..."
            service_restart "$(get_openvpn_svc)"
        fi
    fi

    echo ""
    print_info "Import complete: ${created} created, ${failed} failed."
    press_enter
}

#------------------------------------------------------------------------------
# UPDATE USERS
#------------------------------------------------------------------------------

update_users_menu() {
    while true; do
        print_section "Update User(s)"
        echo -e "  ${BOLD}1)${NC} Update a single user"
        echo -e "  ${BOLD}2)${NC} Bulk update from CSV"
        echo -e "  ${BOLD}0)${NC} Back"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r choice
        case "$choice" in
            1) update_single_user ;;
            2) batch_update_from_csv ;;
            0) return ;;
            *) print_warning "Invalid choice." ;;
        esac
    done
}

update_single_user() {
    print_section "Update Single User"
    local users
    users=$(get_users_list)

    if [ -z "$users" ]; then
        print_warning "No users configured."
        press_enter
        return
    fi

    echo -e "  Select user to update:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r u; do
        echo -e "  ${BOLD}${i})${NC} $u"
        user_array+=("$u")
        ((i++))
    done <<< "$users"
    echo -e "  ${BOLD}0)${NC} Cancel"
    echo ""

    local sel
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter number: "
        read -r sel
        [ "$sel" = "0" ] && return
        if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ] 2>/dev/null; then
            break
        fi
        print_warning "Invalid selection."
    done

    local target_user="${user_array[$((sel-1))]}"
    echo ""
    print_info "Updating user: ${target_user}"
    echo -e "  ${DIM}(press Enter to keep current value)${NC}"
    echo ""

    # New password
    local new_password="" confirm_pass
    while true; do
        echo -en "${YELLOW}  ?${NC}  New password (hidden, Enter to skip): "
        read -rs new_password
        echo ""
        if [ -z "$new_password" ]; then
            break
        fi
        echo -en "${YELLOW}  ?${NC}  Confirm new password: "
        read -rs confirm_pass
        echo ""
        if [ "$new_password" = "$confirm_pass" ]; then
            break
        fi
        print_warning "Passwords do not match."
        new_password=""
    done

    # New PSK
    local new_psk="" confirm_psk
    while true; do
        echo -en "${YELLOW}  ?${NC}  New PSK (hidden, Enter to skip): "
        read -rs new_psk
        echo ""
        if [ -z "$new_psk" ]; then
            break
        fi
        echo -en "${YELLOW}  ?${NC}  Confirm new PSK: "
        read -rs confirm_psk
        echo ""
        if [ "$new_psk" = "$confirm_psk" ]; then
            break
        fi
        print_warning "PSKs do not match."
        new_psk=""
    done

    if [ -z "$new_password" ] && [ -z "$new_psk" ]; then
        print_warning "No changes specified. Nothing to update."
        press_enter
        return
    fi

    update_user_credentials "$target_user" "$new_password" "$new_psk"
    press_enter
}

update_user_credentials() {
    local username="$1"
    local new_password="$2"
    local new_psk="$3"
    local skip_restart="${4:-false}"  # pass "true" in batch ops; caller restarts once at the end

    print_section "Updating credentials for: ${username}"

    local current_psk
    current_psk=$(get_state "L2TP_PSK")
    local effective_psk="${new_psk:-$current_psk}"

    # ---- Password update ----
    if [ -n "$new_password" ]; then
        print_step "Updating password..."

        # IKEv2 EAP in ipsec.secrets — delete-before-add avoids sed delimiter conflicts
        if vpn_is_installed "$VPN_IKEV2" && [ -f /etc/ipsec.secrets ]; then
            local escaped_user escaped_pass sed_user
            escaped_user=$(escape_ipsec "$username")
            escaped_pass=$(escape_ipsec "$new_password")
            sed_user=$(sed_escape_pattern "$escaped_user")
            sed -i "/^%any ${sed_user} : EAP /d" /etc/ipsec.secrets
            echo "%any ${escaped_user} : EAP \"${escaped_pass}\"" >> /etc/ipsec.secrets
        fi

        # L2TP PPP in chap-secrets — delete-before-add
        if vpn_is_installed "$VPN_L2TP" && [ -f /etc/ppp/chap-secrets ]; then
            local ppp_user ppp_pass sed_ppp_user
            ppp_user=$(escape_ppp "$username")
            ppp_pass=$(escape_ppp "$new_password")
            sed_ppp_user=$(sed_escape_pattern "$ppp_user")
            sed -i "/^\"${sed_ppp_user}\" l2tpd /d" /etc/ppp/chap-secrets
            echo "\"${ppp_user}\" l2tpd \"${ppp_pass}\" *" >> /etc/ppp/chap-secrets
        fi

        # OpenVPN SHA-256 hash in users.passwd — delete-before-add
        if vpn_is_installed "$VPN_OVPN" && [ -f "${OPENVPN_DIR}/auth/users.passwd" ]; then
            local new_hash sed_uname
            new_hash=$(hash_password "$new_password")
            sed_uname=$(sed_escape_pattern "$username")
            sed -i "/^${sed_uname}:/d" "${OPENVPN_DIR}/auth/users.passwd"
            echo "${username}:${new_hash}" >> "${OPENVPN_DIR}/auth/users.passwd"
        fi

        # Regenerate client cert (P12 export password = VPN password)
        generate_client_cert "$username" "$new_password" || {
            print_error "Failed to regenerate client certificate for ${username}. Aborting credential update."
            return 1
        }

        # Regenerate all profile files
        generate_all_profiles "$username" "$new_password" "$effective_psk"

        if [ "$skip_restart" != "true" ]; then
            if vpn_is_installed "$VPN_IKEV2"; then
                ipsec restart 2>/dev/null || true
            fi
            if vpn_is_installed "$VPN_L2TP"; then
                service_restart xl2tpd
            fi
            if vpn_is_installed "$VPN_OVPN"; then
                service_restart "$(get_openvpn_svc)"
            fi
        fi

        print_success "Password updated."
    fi

    # ---- PSK update ----
    if [ -n "$new_psk" ]; then
        print_step "Updating PSK..."

        save_state "L2TP_PSK" "$new_psk"

        # Update ipsec.secrets PSK line (used by both IKEv2 and L2TP)
        if { vpn_is_installed "$VPN_IKEV2" || vpn_is_installed "$VPN_L2TP"; } && [ -f /etc/ipsec.secrets ]; then
            local escaped_psk
            escaped_psk=$(escape_ipsec "$new_psk")
            # Delete-before-add: avoids sed delimiter conflicts with special chars in PSK
            sed -i "/^%any %any : PSK /d" /etc/ipsec.secrets
            echo "%any %any : PSK \"${escaped_psk}\"" >> /etc/ipsec.secrets
        fi

        print_warning "L2TP PSK is server-wide — all existing L2TP clients need updated profiles."

        # Regenerate connection_info.txt for all users to pick up the new PSK.
        # We intentionally do NOT call generate_all_profiles here — the full profile
        # regeneration needs the user's plaintext password (for the P12 mobileconfig and
        # Windows PS1). Calling it with an empty password would overwrite those working
        # files with broken ones. Only the connection info text file needs updating for
        # a PSK change.
        local all_users
        all_users=$(get_users_list)
        if [ -n "$all_users" ]; then
            while IFS= read -r u; do
                generate_connection_info "$u" "" "$new_psk"
            done <<< "$all_users"
        fi

        if [ "$skip_restart" != "true" ] && vpn_is_installed "$VPN_IKEV2"; then
            ipsec restart 2>/dev/null || true
        fi

        print_success "PSK updated."
    fi

    print_success "Done updating '${username}'."
}

batch_update_from_csv() {
    print_section "Bulk Update from CSV"
    echo -e "  CSV format: ${BOLD}username,new_password,new_psk${NC}"
    echo -e "  ${DIM}password or psk column may be blank (but not both)${NC}"
    echo ""
    echo -en "${YELLOW}  ?${NC}  Path to update CSV (or 0 to cancel): "
    read -r csv_path
    [ "$csv_path" = "0" ] && return

    if [ ! -f "$csv_path" ]; then
        print_error "File not found: ${csv_path}"
        press_enter
        return
    fi

    # Phase 1 — validate all lines
    local line_num=0
    local error_count=0
    local valid_users=()
    local valid_passes=()
    local valid_psks=()

    while IFS= read -r line || [ -n "$line" ]; do
        ((line_num++))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        local csv_user csv_pass csv_psk
        csv_user=$(echo "$line" | cut -d',' -f1)
        csv_pass=$(echo "$line" | cut -d',' -f2)
        csv_psk=$(echo "$line"  | cut -d',' -f3)

        local row_ok=true

        if [ -z "$csv_user" ]; then
            print_warning "Line ${line_num}: username is empty"
            row_ok=false
        elif ! in_list "$csv_user" "$(get_state "USERS_LIST")"; then
            print_warning "Line ${line_num}: user '${csv_user}' does not exist"
            row_ok=false
        fi

        if [ -z "$csv_pass" ] && [ -z "$csv_psk" ]; then
            print_warning "Line ${line_num}: both password and PSK are empty — nothing to update"
            row_ok=false
        fi

        if $row_ok; then
            valid_users+=("$csv_user")
            valid_passes+=("$csv_pass")
            valid_psks+=("$csv_psk")
        else
            ((error_count++))
        fi
    done < "$csv_path"

    local valid_count="${#valid_users[@]}"
    echo ""
    echo -e "  Valid entries  : ${GREEN}${valid_count}${NC}"
    echo -e "  Invalid entries: ${RED}${error_count}${NC}"

    if [ "$valid_count" -eq 0 ]; then
        print_warning "No valid entries to process."
        press_enter
        return
    fi

    # Phase 2 — confirm
    if [ "$error_count" -gt 0 ]; then
        echo ""
        if ! ask_yn "  Proceed with ${valid_count} valid entries (skip invalid)?" "n"; then
            print_info "Cancelled."
            press_enter
            return
        fi
    else
        if ! ask_yn "  Update ${valid_count} user(s)?" "y"; then
            print_info "Cancelled."
            press_enter
            return
        fi
    fi

    # Phase 3 — apply (skip per-user restart; restart once at the end)
    local updated=0 failed=0
    local i
    for i in "${!valid_users[@]}"; do
        if update_user_credentials "${valid_users[$i]}" "${valid_passes[$i]}" "${valid_psks[$i]}" "true"; then
            ((updated++))
        else
            print_error "Failed to update user '${valid_users[$i]}'"
            ((failed++))
        fi
    done

    # Single restart after all credentials are written
    if [ "$updated" -gt 0 ]; then
        if vpn_is_installed "$VPN_IKEV2"; then
            print_step "Restarting strongSwan..."
            ipsec restart 2>/dev/null || true
        fi
        if vpn_is_installed "$VPN_L2TP"; then
            service_restart xl2tpd
        fi
        if vpn_is_installed "$VPN_OVPN"; then
            service_restart "$(get_openvpn_svc)"
        fi
    fi

    echo ""
    print_info "Bulk update complete: ${updated} updated, ${failed} failed."
    press_enter
}

#------------------------------------------------------------------------------
# EXPORT USER LIST
#------------------------------------------------------------------------------

export_user_list() {
    print_section "Export User List"
    local export_file="${PROFILES_BASE}/users_export.csv"

    {
        echo "# VPN Users Export — generated by vpn-setup.sh"
        echo "# Format: username,password,psk"
        echo "# Passwords are not stored — fill them in before re-importing"
        local users
        users=$(get_users_list)
        if [ -n "$users" ]; then
            while IFS= read -r u; do
                echo "${u},,"
            done <<< "$users"
        fi
    } > "$export_file"

    print_success "Exported to: ${export_file}"
    echo ""
    echo -e "  ${DIM}Fill in passwords and PSKs, then use 'Add multiple users > Import from CSV'.${NC}"
    press_enter
}

remove_user_menu() {
    print_section "Remove VPN User"
    local users
    users=$(get_users_list)

    if [ -z "$users" ]; then
        print_warning "No users found."
        press_enter
        return
    fi

    echo -e "  Select user to remove:"
    echo ""
    local i=1
    local user_array=()
    while IFS= read -r u; do
        echo -e "  ${BOLD}${i})${NC} $u"
        user_array+=("$u")
        ((i++))
    done <<< "$users"
    echo -e "  ${BOLD}0)${NC} Cancel"
    echo ""

    local sel
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter number: "
        read -r sel
        if [ "$sel" = "0" ]; then return; fi
        if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ] 2>/dev/null; then
            break
        fi
        print_warning "Invalid selection."
    done

    local target_user="${user_array[$((sel-1))]}"
    echo ""
    if ask_yn "  Remove user '${target_user}'? This cannot be undone." "n"; then
        remove_vpn_user "$target_user"
    else
        print_info "Cancelled."
    fi
    press_enter
}

list_users_detail() {
    print_section "VPN Users"
    local users
    users=$(get_users_list)
    if [ -z "$users" ]; then
        print_warning "No users configured."
        press_enter
        return
    fi

    while IFS= read -r u; do
        echo -e "  ${CYAN}${BOLD}${u}${NC}"
        echo -e "    Profile dir : ${PROFILES_BASE}/${u}/"
        local wg_ip ovpn_ip
        wg_ip=$(get_state "WG_IP_${u}")
        ovpn_ip=$(get_state "OVPN_IP_${u}")
        [ -n "$wg_ip" ]   && echo -e "    WireGuard IP: ${wg_ip}"
        [ -n "$ovpn_ip" ] && echo -e "    OpenVPN IP  : ${ovpn_ip}"
        if [ -d "${PROFILES_BASE}/${u}" ]; then
            local file_count
            file_count=$(ls "${PROFILES_BASE}/${u}" 2>/dev/null | wc -l)
            echo -e "    Profile files: ${file_count} file(s)"
        fi
        echo ""
    done <<< "$users"
    press_enter
}

#==============================================================================
# §23  CHANGE SERVER ADDRESS
#==============================================================================

change_server_address_menu() {
    print_section "Change Server Address"
    local current_addr
    current_addr=$(get_state "SERVER_ADDRESS")
    echo -e "  Current server address: ${BOLD}${current_addr}${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Use a DNS hostname"
    echo -e "  ${BOLD}2)${NC} Use server IP (auto-detect)"
    echo -e "  ${BOLD}0)${NC} Cancel"
    echo ""

    local choice new_addr new_type
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r choice
        case "$choice" in
            0) return ;;
            1)
                new_type="dns"
                while true; do
                    echo -en "${YELLOW}  ?${NC}  Enter new DNS hostname: "
                    read -r new_addr
                    if [ -z "$new_addr" ]; then
                        print_warning "Hostname cannot be empty."
                    elif ! echo "$new_addr" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$'; then
                        print_warning "Invalid hostname. Use only letters, digits, dots, and hyphens."
                    else
                        break
                    fi
                done
                break
                ;;
            2)
                new_type="ip"
                echo -en "  ${DIM}Detecting public IP...${NC}"
                new_addr=$(get_public_ip)
                if [ -z "$new_addr" ]; then
                    print_warning "Could not auto-detect. Enter manually:"
                    while true; do
                        echo -en "${YELLOW}  ?${NC}  Enter IP: "
                        read -r new_addr
                        echo "$new_addr" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' && break
                        print_warning "Invalid IP address."
                    done
                else
                    echo -e " ${GREEN}${new_addr}${NC}"
                fi
                break
                ;;
            *) print_warning "Invalid choice." ;;
        esac
    done

    echo ""
    print_info "New address: ${new_addr} (${new_type})"
    if ! ask_yn "Apply this change? (Server certificates will be regenerated)" "y"; then
        print_info "Cancelled."
        press_enter
        return
    fi

    # Ask for LE email if switching to DNS mode
    local le_email=""
    if [ "$new_type" = "dns" ]; then
        local existing_email
        existing_email=$(get_state "LE_EMAIL")
        echo ""
        echo -e "  ${DIM}A Let's Encrypt certificate can be obtained for this hostname.${NC}"
        if [ -n "$existing_email" ]; then
            echo -en "${YELLOW}  ?${NC}  Email for Let's Encrypt [${existing_email}]: "
            read -r le_email
            [ -z "$le_email" ] && le_email="$existing_email"
        else
            while true; do
                echo -en "${YELLOW}  ?${NC}  Email for Let's Encrypt (required): "
                read -r le_email
                [ -n "$le_email" ] && break
                print_warning "  Email cannot be empty."
            done
        fi
    fi

    # Capture current cert mode BEFORE updating state — used for LE cleanup decisions below.
    local was_letsencrypt=false
    is_letsencrypt && was_letsencrypt=true

    save_state "SERVER_ADDRESS" "$new_addr"
    save_state "ADDRESS_TYPE" "$new_type"

    # Switching to IP mode: purge LE cert + hooks so auto-renewal can't overwrite the
    # new self-signed cert after we switch away.
    if [ "$was_letsencrypt" = "true" ] && [ "$new_type" = "ip" ]; then
        _cleanup_letsencrypt
    fi

    # Regenerate server cert for new address
    print_step "Regenerating server certificate..."
    if [ "$new_type" = "dns" ]; then
        if obtain_letsencrypt_cert "$new_addr" "$le_email"; then
            true  # LE cert obtained; obtain_letsencrypt_cert already saved CERT_TYPE=letsencrypt
        else
            echo ""
            print_warning "Let's Encrypt certificate could not be obtained."
            print_warning "Common causes: port 80 blocked, DNS not pointing here, another service on port 80."
            echo ""
            if ask_yn "Continue with a self-signed certificate instead?" "y"; then
                # Purge old LE cert + hooks so auto-renewal can't silently revert the server
                # back to the previous domain's cert after we fall back to self-signed.
                if [ "$was_letsencrypt" = "true" ]; then
                    _cleanup_letsencrypt
                fi
                generate_server_cert "$new_addr" "$new_type"
                save_state "CERT_TYPE" "self-signed"
            else
                print_warning "Server address change aborted. Reverting to previous address."
                save_state "SERVER_ADDRESS" "$current_addr"
                save_state "ADDRESS_TYPE" "$(get_state "ADDRESS_TYPE")"
                press_enter
                return
            fi
        fi
    else
        generate_server_cert "$new_addr" "$new_type"
        save_state "CERT_TYPE" "self-signed"
    fi

    cp "${CERTS_DIR}/server.crt" /etc/ipsec.d/certs/ 2>/dev/null || true
    cp "${CERTS_DIR}/server.key" /etc/ipsec.d/private/ 2>/dev/null || true
    chmod 600 /etc/ipsec.d/private/server.key 2>/dev/null || true
    cp "${CERTS_DIR}/server.crt" "${OPENVPN_DIR}/server/" 2>/dev/null || true
    cp "${CERTS_DIR}/server.key" "${OPENVPN_DIR}/server/" 2>/dev/null || true
    chmod 600 "${OPENVPN_DIR}/server/server.key" 2>/dev/null || true

    # Update ipsec.conf server ID
    if vpn_is_installed "$VPN_IKEV2" || vpn_is_installed "$VPN_L2TP"; then
        local new_leftid escaped_leftid
        new_leftid=$([ "$new_type" = "dns" ] && echo "@${new_addr}" || echo "${new_addr}")
        escaped_leftid=$(sed_escape_replacement "$new_leftid")
        sed -i "s|leftid=.*|leftid=${escaped_leftid}|" /etc/ipsec.conf 2>/dev/null || true
        service_restart "strongswan"
    fi

    # Restart OpenVPN
    if vpn_is_installed "$VPN_OVPN"; then
        service_restart "$(get_openvpn_svc)"
    fi

    # Regenerate user profiles that don't require the plaintext password.
    # WireGuard configs, OpenVPN .ovpn profiles, IKEv2 EAP mobileconfigs, and
    # connection info can all be regenerated without the password. Only the IKEv2
    # cert mobileconfig, .sswan, and Windows PS1 embed the P12 password — those
    # can't be regenerated here.
    print_step "Regenerating user profiles with new server address..."
    local users
    users=$(get_users_list)
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        create_profile_dir "$u"
        if vpn_is_installed "$VPN_IKEV2"; then
            generate_ikev2_eap_mobileconfig "$u"
        fi
        if vpn_is_installed "$VPN_WG"; then
            generate_wireguard_conf "$u"
        fi
        if vpn_is_installed "$VPN_OVPN"; then
            generate_openvpn_ovpn "$u"
        fi
        generate_connection_info "$u" "" ""
        print_warning "IKEv2 cert mobileconfig, .sswan, and Windows PS1 for '${u}' need the P12 password to regenerate."
        print_warning "Use 'Update User' to set a new password, which will regenerate those profiles."
    done <<< "$users"

    print_success "Server address updated to: ${new_addr}"
    press_enter
}

#==============================================================================
# §24  CHANGE DNS RESOLVERS
#==============================================================================

change_dns_menu() {
    print_section "Change VPN DNS Resolver(s)"
    echo -e "  Current: ${BOLD}$(get_state "DNS1")${NC} / ${BOLD}$(get_state "DNS2")${NC}"
    echo ""
    echo -e "  Select up to two DNS servers for VPN clients."
    echo -e "  ${DIM}(Enter two numbers separated by space, or one number for both primary/secondary)${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Server's Internal DNS  ${DIM}(auto-detected)${NC}"
    echo -e "  ${BOLD}2)${NC} Cloudflare             ${DIM}(1.1.1.1, 1.0.0.1)${NC}"
    echo -e "  ${BOLD}3)${NC} AdGuard                ${DIM}(94.140.14.14, 94.140.15.15)${NC}"
    echo -e "  ${BOLD}4)${NC} Google                 ${DIM}(8.8.8.8, 8.8.4.4)${NC}"
    echo -e "  ${BOLD}5)${NC} Quad9                  ${DIM}(9.9.9.9, 149.112.112.112)${NC}"
    echo -e "  ${BOLD}6)${NC} OpenDNS                ${DIM}(208.67.222.222, 208.67.220.220)${NC}"
    echo -e "  ${BOLD}0)${NC} Back"
    echo ""

    local d1 d2 dns_input
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter choice(s) [e.g. '4' or '4 2']: "
        read -r dns_input
        [ "$dns_input" = "0" ] && return
        d1=$(echo "$dns_input" | awk '{print $1}')
        d2=$(echo "$dns_input" | awk '{print $2}')
        [ -z "$d2" ] && d2="$d1"
        if echo "$d1" | grep -qE '^[1-6]$' && echo "$d2" | grep -qE '^[1-6]$'; then
            break
        fi
        print_warning "Please enter valid choices (1-6) or 0 to go back."
    done

    local dns1_pair dns2_pair
    dns1_pair=$(get_dns_ipv4 "$d1")
    dns2_pair=$(get_dns_ipv4 "$d2")
    SETUP_DNS1=$(echo "$dns1_pair" | awk '{print $1}')
    if [ "$d1" = "$d2" ]; then
        SETUP_DNS2=$(echo "$dns2_pair" | awk '{print $2}')
    else
        SETUP_DNS2=$(echo "$dns2_pair" | awk '{print $1}')
    fi

    # If internal DNS selected but detection failed, fall back to Cloudflare
    if { [ "$d1" = "1" ] || [ "$d2" = "1" ]; } && [ -z "$SETUP_DNS1" ]; then
        print_warning "Could not detect system DNS. Falling back to Cloudflare (1.1.1.1)."
        SETUP_DNS1="1.1.1.1"
        SETUP_DNS2="1.0.0.1"
    fi

    echo ""
    echo -e "  ${GREEN}Primary DNS:${NC}   $(get_dns_name "$d1") — ${SETUP_DNS1}"
    echo -e "  ${GREEN}Secondary DNS:${NC} $(get_dns_name "$d2") — ${SETUP_DNS2}"
    echo ""

    save_state "DNS1" "$SETUP_DNS1"
    save_state "DNS2" "$SETUP_DNS2"
    [ -n "$SETUP_DNS1_V6" ] && save_state "DNS1_IPV6" "$SETUP_DNS1_V6"
    [ -n "$SETUP_DNS2_V6" ] && save_state "DNS2_IPV6" "$SETUP_DNS2_V6"

    # Update xl2tpd PPP options — remove all ms-dns lines and rewrite both
    if vpn_is_installed "$VPN_L2TP" && [ -f /etc/ppp/options.xl2tpd ]; then
        sed -i '/^ms-dns /d' /etc/ppp/options.xl2tpd
        echo "ms-dns ${SETUP_DNS1}" >> /etc/ppp/options.xl2tpd
        echo "ms-dns ${SETUP_DNS2}" >> /etc/ppp/options.xl2tpd
        service_restart "xl2tpd"
    fi

    # Update OpenVPN — delete all existing DNS push lines and rewrite
    if vpn_is_installed "$VPN_OVPN" && [ -f "${OPENVPN_DIR}/server.conf" ]; then
        sed -i '/^push "dhcp-option DNS /d' "${OPENVPN_DIR}/server.conf"
        if [ -n "$SETUP_DNS1" ]; then
            echo "push \"dhcp-option DNS ${SETUP_DNS1}\"" >> "${OPENVPN_DIR}/server.conf"
        fi
        if [ -n "$SETUP_DNS2" ] && [ "$SETUP_DNS2" != "$SETUP_DNS1" ]; then
            echo "push \"dhcp-option DNS ${SETUP_DNS2}\"" >> "${OPENVPN_DIR}/server.conf"
        fi
        service_restart "$(get_openvpn_svc)"
    fi

    # Update IKEv2 (rightdns in ipsec.conf)
    if vpn_is_installed "$VPN_IKEV2" && [ -f /etc/ipsec.conf ]; then
        if [ -n "$SETUP_DNS1" ]; then
            local new_dns_val="${SETUP_DNS1}"
            [ -n "$SETUP_DNS2" ] && [ "$SETUP_DNS2" != "$SETUP_DNS1" ] && new_dns_val="${SETUP_DNS1},${SETUP_DNS2}"
            sed -i "s|rightdns=.*|rightdns=${new_dns_val}|" /etc/ipsec.conf
        fi
        service_restart "strongswan"
    fi

    print_success "DNS resolvers updated. Services restarted."
    press_enter
}

#==============================================================================
# §25  UPDATE VPN SERVERS
#==============================================================================

update_vpn_menu() {
    print_section "Update VPN Servers"
    print_info "Updating packages for installed VPN servers..."
    echo ""

    eval "$PKG_UPDATE" || print_warning "Package list update had warnings."

    local pkgs_to_update=""

    if vpn_is_installed "$VPN_IKEV2" || vpn_is_installed "$VPN_L2TP"; then
        pkgs_to_update="$pkgs_to_update strongswan"
    fi
    if vpn_is_installed "$VPN_L2TP"; then
        pkgs_to_update="$pkgs_to_update xl2tpd"
    fi
    if vpn_is_installed "$VPN_WG"; then
        pkgs_to_update="$pkgs_to_update wireguard-tools"
    fi
    if vpn_is_installed "$VPN_OVPN"; then
        pkgs_to_update="$pkgs_to_update openvpn"
    fi

    pkgs_to_update=$(echo "$pkgs_to_update" | xargs)  # trim whitespace

    if [ -z "$pkgs_to_update" ]; then
        print_warning "No VPN servers currently installed."
        press_enter
        return
    fi

    print_step "Updating: ${pkgs_to_update}"
    eval "$PKG_INSTALL $pkgs_to_update" || print_warning "Some packages could not be updated."

    # Restart services
    if vpn_is_installed "$VPN_IKEV2" || vpn_is_installed "$VPN_L2TP"; then
        service_restart "strongswan"
    fi
    if vpn_is_installed "$VPN_L2TP"; then
        service_restart "xl2tpd"
    fi
    if vpn_is_installed "$VPN_WG"; then
        service_restart "wg-quick@wg0"
    fi
    if vpn_is_installed "$VPN_OVPN"; then
        service_restart "$(get_openvpn_svc)"
    fi

    print_success "VPN servers updated and restarted."
    press_enter
}

#==============================================================================
# §26  UNINSTALL VPN SERVERS
#==============================================================================

uninstall_vpn_menu() {
    print_section "Uninstall VPN Server(s)"
    local installed
    installed=$(get_state "INSTALLED_VPNS")

    if [ -z "$installed" ]; then
        print_warning "No VPN servers are installed."
        press_enter
        return
    fi

    echo -e "  Currently installed: ${BOLD}${installed}${NC}"
    echo ""
    echo -e "  Select VPN to uninstall:"
    echo ""

    local i=1
    while IFS= read -r v; do
        [ -z "$v" ] && continue
        echo -e "  ${BOLD}${i})${NC} ${v}"
        ((i++))
    done <<< "$(echo "$installed" | tr ',' '\n')"

    local num_installed=$((i - 1))
    local all_num=$((num_installed + 1))
    echo -e "  ${BOLD}${all_num})${NC} All VPN servers"
    echo -e "  ${BOLD}0)${NC}  Cancel"
    echo ""

    local sel
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r sel
        [ "$sel" = "0" ] && return
        if [ "$sel" -ge 1 ] && [ "$sel" -le "$all_num" ] 2>/dev/null; then
            break
        fi
        print_warning "Invalid selection."
    done

    local to_uninstall=""
    if [ "$sel" = "$all_num" ]; then
        to_uninstall="$installed"
    else
        to_uninstall=$(echo "$installed" | tr ',' '\n' | sed -n "${sel}p")
    fi

    echo ""
    if ! ask_yn "Uninstall: ${to_uninstall}? This will stop services and remove configs." "n"; then
        print_info "Cancelled."
        press_enter
        return
    fi

    echo "$to_uninstall" | tr ',' '\n' | while read -r vpn; do
        case "$vpn" in
            "$VPN_IKEV2")  uninstall_ikev2 ;;
            "$VPN_L2TP")   uninstall_l2tp  ;;
            "$VPN_WG")     uninstall_wireguard ;;
            "$VPN_OVPN")   uninstall_openvpn ;;
        esac
    done

    print_success "Uninstallation complete."
    press_enter
}

uninstall_ikev2() {
    print_step "Uninstalling IKEv2 (strongSwan)..."

    # Remove IKEv2-specific conn blocks from ipsec.conf
    if [ -f /etc/ipsec.conf ]; then
        sed -i '/^conn ikev2-eap$/,/^$/d' /etc/ipsec.conf
        sed -i '/^conn ikev2-cert$/,/^$/d' /etc/ipsec.conf
        sed -i '/^# BEGIN ikev2-cert-/,/^# END ikev2-cert-/d' /etc/ipsec.conf
    fi

    # Only remove strongSwan entirely if L2TP isn't also installed (they share it)
    if ! vpn_is_installed "$VPN_L2TP"; then
        service_stop "strongswan"
        service_stop "strongswan-starter" 2>/dev/null || true
        eval "$PKG_REMOVE strongswan libstrongswan-standard-plugins libcharon-extra-plugins" 2>/dev/null || true
        rm -f /etc/ipsec.conf /etc/ipsec.secrets
        rm -rf /etc/ipsec.d
    else
        # L2TP still needs strongSwan — just remove EAP entries from ipsec.secrets
        sed -i '/: EAP /d' /etc/ipsec.secrets
        ipsec restart &>/dev/null || true
    fi

    # Remove IKEv2 firewall rules
    fw_delete INPUT -p udp --dport "${IKEV2_PORT}" -j ACCEPT 2>/dev/null || true
    fw_delete INPUT -p udp --dport "${IKEV2_NAT_PORT}" -j ACCEPT 2>/dev/null || true
    save_iptables
    mark_vpn_uninstalled "$VPN_IKEV2"
    print_success "IKEv2 uninstalled."
}

uninstall_l2tp() {
    print_step "Uninstalling L2TP (xl2tpd)..."
    service_stop "xl2tpd"
    eval "$PKG_REMOVE xl2tpd" 2>/dev/null || true
    rm -f /etc/xl2tpd/xl2tpd.conf /etc/ppp/options.xl2tpd

    # Remove L2TP-specific IPsec conn and PSK from shared config
    if [ -f /etc/ipsec.conf ]; then
        sed -i '/^# L2TP\/IPsec/,/^$/d' /etc/ipsec.conf 2>/dev/null || true
        sed -i '/^conn L2TP-PSK/,/^$/d' /etc/ipsec.conf 2>/dev/null || true
    fi
    if [ -f /etc/ipsec.secrets ]; then
        sed -i '/^%any %any : PSK /d' /etc/ipsec.secrets
    fi

    # Remove chap-secrets entries
    if [ -f /etc/ppp/chap-secrets ]; then
        sed -i '/ l2tpd /d' /etc/ppp/chap-secrets
    fi

    # Only remove strongSwan if IKEv2 isn't also installed
    if ! vpn_is_installed "$VPN_IKEV2"; then
        service_stop "strongswan"
        service_stop "strongswan-starter" 2>/dev/null || true
        eval "$PKG_REMOVE strongswan" 2>/dev/null || true
        rm -f /etc/ipsec.conf /etc/ipsec.secrets
        rm -rf /etc/ipsec.d
    else
        ipsec restart &>/dev/null || true
    fi

    fw_delete INPUT -p udp --dport "${L2TP_PORT}" -j ACCEPT 2>/dev/null || true
    save_iptables
    mark_vpn_uninstalled "$VPN_L2TP"
    print_success "L2TP uninstalled."
}

uninstall_wireguard() {
    print_step "Uninstalling WireGuard..."
    wg-quick down wg0 2>/dev/null || true
    service_stop "wg-quick@wg0" 2>/dev/null || true
    eval "$PKG_REMOVE wireguard-tools wireguard" 2>/dev/null || true
    rm -f /etc/wireguard/wg0.conf
    fw_delete INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || true
    save_iptables
    mark_vpn_uninstalled "$VPN_WG"
    print_success "WireGuard uninstalled."
}

uninstall_openvpn() {
    print_step "Uninstalling OpenVPN..."
    service_stop "$(get_openvpn_svc)"
    service_stop "openvpn-server@server" 2>/dev/null || true
    eval "$PKG_REMOVE openvpn" 2>/dev/null || true
    rm -rf "${OPENVPN_DIR}/server" "${OPENVPN_DIR}/auth" "${OPENVPN_DIR}/ccd"
    fw_delete INPUT -p udp --dport "${OVPN_PORT}" -j ACCEPT 2>/dev/null || true
    save_iptables
    mark_vpn_uninstalled "$VPN_OVPN"
    print_success "OpenVPN uninstalled."
}
#==============================================================================
# §27  ADVANCED MENU
#==============================================================================

show_advanced_menu() {
    while true; do
        print_section "Advanced Options"
        echo -e "  ${BOLD}1)${NC} Split Tunneling"
        echo -e "  ${BOLD}2)${NC} Access VPN server's subnet from VPN clients"
        echo -e "  ${BOLD}3)${NC} Access VPN clients from server's subnet"
        echo -e "  ${BOLD}4)${NC} Port Forwarding to VPN clients"
        echo -e "  ${BOLD}5)${NC} Disable IPv6"
        if is_letsencrypt; then
            echo -e "  ${BOLD}6)${NC} Renew Let's Encrypt certificate"
        fi
        echo -e "  ${BOLD}0)${NC} Back"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r adv_choice

        case "$adv_choice" in
            1) split_tunneling_menu ;;
            2) server_subnet_access_menu ;;
            3) client_subnet_access_menu ;;
            4) port_forwarding_menu ;;
            5) disable_ipv6_menu ;;
            6)
                if is_letsencrypt; then
                    renew_letsencrypt_menu
                else
                    print_warning "Invalid choice."
                fi
                ;;
            0) return ;;
            *) print_warning "Invalid choice." ;;
        esac
    done
}

renew_letsencrypt_menu() {
    print_section "Renew Let's Encrypt Certificate"
    local domain
    domain=$(get_state "LE_DOMAIN")
    echo -e "  Current domain: ${BOLD}${domain}${NC}"
    echo -e "  ${DIM}Port 80 will be opened temporarily (managed by renewal hooks).${NC}"
    echo ""
    if ! ask_yn "Force renewal of Let's Encrypt certificate?" "y"; then
        return
    fi

    print_step "Forcing certificate renewal..."
    # Pre/post hooks manage port 80; deploy hook copies certs and restarts services.
    certbot renew --cert-name vpn-server --force-renewal 2>&1

    print_success "Renewal complete. Deploy hook has restarted VPN services."
    press_enter
}

#==============================================================================
# §28  ADVANCED: SPLIT TUNNELING
#==============================================================================

split_tunneling_menu() {
    print_section "Split Tunneling"
    local current_mode
    current_mode=$(get_state "SPLIT_TUNNELING")
    current_mode="${current_mode:-disabled}"

    echo -e "  Current mode: ${BOLD}${current_mode}${NC}"
    echo ""
    echo -e "  ${DIM}Split tunneling routes only specific traffic through VPN.${NC}"
    echo -e "  ${DIM}Full tunnel (default) routes ALL traffic through VPN.${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Full tunnel (all traffic through VPN) [default]"
    echo -e "  ${BOLD}2)${NC} Split tunnel (only VPN subnet traffic)"
    echo -e "  ${BOLD}3)${NC} Custom split (enter specific subnets)"
    echo -e "  ${BOLD}0)${NC} Back"
    echo ""
    echo -en "${YELLOW}  ?${NC}  Enter choice: "
    read -r st_choice

    case "$st_choice" in
        0) return ;;
        1)
            apply_split_tunneling "full" ""
            save_state "SPLIT_TUNNELING" "full"
            ;;
        2)
            local subnets="${IKEV2_SUBNET},${L2TP_SUBNET},${WG_SUBNET},${OVPN_SUBNET}"
            apply_split_tunneling "split" "$subnets"
            save_state "SPLIT_TUNNELING" "split"
            ;;
        3)
            echo ""
            echo -en "${YELLOW}  ?${NC}  Enter subnets (comma-separated, e.g. 10.0.0.0/8,192.168.1.0/24): "
            read -r custom_subnets
            if [ -n "$custom_subnets" ]; then
                apply_split_tunneling "custom" "$custom_subnets"
                save_state "SPLIT_TUNNELING" "custom:${custom_subnets}"
            fi
            ;;
        *) print_warning "Invalid choice." ;;
    esac
    press_enter
}

apply_split_tunneling() {
    local mode="$1"
    local subnets="$2"

    print_step "Applying split tunneling mode: ${mode}..."

    # WireGuard: update AllowedIPs in server config — affects new client configs
    if vpn_is_installed "$VPN_WG"; then
        if [ "$mode" = "full" ]; then
            save_state "WG_ALLOWED_IPS" "0.0.0.0/0"
        else
            # Convert comma-separated to space-separated
            local wg_subnets
            wg_subnets=$(echo "$subnets" | tr ',' ', ')
            save_state "WG_ALLOWED_IPS" "$wg_subnets"
        fi
        print_info "WireGuard: AllowedIPs updated for new clients. Existing clients need new profile files."
    fi

    # OpenVPN: update push directives
    if vpn_is_installed "$VPN_OVPN" && [ -f "${OPENVPN_DIR}/server.conf" ]; then
        # Remove existing redirect-gateway and route push lines
        sed -i '/^push "redirect-gateway/d' "${OPENVPN_DIR}/server.conf"
        sed -i '/^push "route /d' "${OPENVPN_DIR}/server.conf"

        if [ "$mode" = "full" ]; then
            echo 'push "redirect-gateway def1 bypass-dhcp"' >> "${OPENVPN_DIR}/server.conf"
        else
            # Add individual subnet routes
            echo "$subnets" | tr ',' '\n' | while read -r subnet; do
                subnet=$(echo "$subnet" | xargs)
                local net mask
                net=$(echo "$subnet" | cut -d/ -f1)
                mask=$(cidr_to_mask "$(echo "$subnet" | cut -d/ -f2)")
                echo "push \"route ${net} ${mask}\"" >> "${OPENVPN_DIR}/server.conf"
            done
        fi
        service_restart "$(get_openvpn_svc)"
        print_success "OpenVPN split tunneling configured."
    fi

    # IKEv2: update leftsubnet in ipsec.conf
    if vpn_is_installed "$VPN_IKEV2" && [ -f /etc/ipsec.conf ]; then
        if [ "$mode" = "full" ]; then
            sed -i 's|leftsubnet=.*|leftsubnet=0.0.0.0/0|' /etc/ipsec.conf
        else
            local ike_subnets escaped_subnets
            ike_subnets=$(echo "$subnets" | tr ',' ' ')
            escaped_subnets=$(sed_escape_replacement "$ike_subnets")
            sed -i "s|leftsubnet=.*|leftsubnet=${escaped_subnets}|" /etc/ipsec.conf
        fi
        service_restart "strongswan"
        print_success "IKEv2 split tunneling configured."
    fi

    print_success "Split tunneling mode '${mode}' applied."
}

# Convert CIDR prefix length to subnet mask
cidr_to_mask() {
    local bits="$1"
    local mask=""
    local full_octets=$((bits / 8))
    local partial_bits=$((bits % 8))
    local i

    for ((i=0; i<4; i++)); do
        if [ "$i" -lt "$full_octets" ]; then
            mask="${mask}${mask:+.}255"
        elif [ "$i" -eq "$full_octets" ]; then
            local val=0
            local j
            for ((j=7; j>=8-partial_bits && partial_bits>0; j--)); do
                val=$((val + (1 << j)))
            done
            mask="${mask}${mask:+.}${val}"
        else
            mask="${mask}${mask:+.}0"
        fi
    done
    echo "$mask"
}

#==============================================================================
# §29  ADVANCED: ACCESS VPN SERVER'S SUBNET
#==============================================================================

server_subnet_access_menu() {
    print_section "Access VPN Server's Subnet"
    echo -e "  ${DIM}Allow VPN clients to reach the server's local network (LAN).${NC}"
    echo ""

    # Detect server's local subnet
    local iface server_subnet
    iface=$(get_primary_iface)
    server_subnet=$(ip -o -f inet addr show "$iface" 2>/dev/null | awk '{print $4}' | head -1)

    echo -e "  Detected server subnet: ${BOLD}${server_subnet:-unknown}${NC}"
    echo ""

    local current
    current=$(get_state "SERVER_SUBNET_ACCESS")
    echo -e "  Current state: ${BOLD}${current:-disabled}${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Enable subnet access"
    echo -e "  ${BOLD}2)${NC} Disable subnet access"
    echo -e "  ${BOLD}0)${NC} Back"
    echo ""
    echo -en "${YELLOW}  ?${NC}  Enter choice: "
    read -r sub_choice

    case "$sub_choice" in
        1)
            local target_subnet
            if [ -n "$server_subnet" ]; then
                echo -en "${YELLOW}  ?${NC}  Server subnet [${server_subnet}]: "
                read -r target_subnet
                target_subnet="${target_subnet:-$server_subnet}"
            else
                while true; do
                    echo -en "${YELLOW}  ?${NC}  Enter server subnet (e.g. 192.168.1.0/24): "
                    read -r target_subnet
                    [ -n "$target_subnet" ] && break
                done
            fi

            # Add forward rules for each VPN subnet → server subnet
            for vpn_subnet in "${IKEV2_SUBNET}" "${L2TP_SUBNET}" "${WG_SUBNET}" "${OVPN_SUBNET}"; do
                fw_add FORWARD -s "$vpn_subnet" -d "$target_subnet" -j ACCEPT
                fw_add FORWARD -s "$target_subnet" -d "$vpn_subnet" -j ACCEPT
            done

            # Add route if needed
            if ! ip route show "$target_subnet" &>/dev/null; then
                print_info "Note: Make sure ${target_subnet} is reachable from this server."
            fi

            save_iptables
            save_state "SERVER_SUBNET_ACCESS" "enabled:${target_subnet}"
            print_success "VPN clients can now access: ${target_subnet}"
            ;;
        2)
            local saved
            saved=$(get_state "SERVER_SUBNET_ACCESS")
            local saved_subnet
            saved_subnet=$(echo "$saved" | cut -d: -f2)
            if [ -n "$saved_subnet" ]; then
                for vpn_subnet in "${IKEV2_SUBNET}" "${L2TP_SUBNET}" "${WG_SUBNET}" "${OVPN_SUBNET}"; do
                    fw_delete FORWARD -s "$vpn_subnet" -d "$saved_subnet" -j ACCEPT 2>/dev/null || true
                    fw_delete FORWARD -s "$saved_subnet" -d "$vpn_subnet" -j ACCEPT 2>/dev/null || true
                done
                save_iptables
            fi
            save_state "SERVER_SUBNET_ACCESS" "disabled"
            print_success "Server subnet access disabled."
            ;;
        0) return ;;
    esac
    press_enter
}

#==============================================================================
# §30  ADVANCED: ACCESS VPN CLIENTS FROM SERVER'S SUBNET
#==============================================================================

client_subnet_access_menu() {
    print_section "Access VPN Clients from Server's Subnet"
    echo -e "  ${DIM}Allow devices on the server's LAN to reach VPN clients.${NC}"
    echo ""

    local current
    current=$(get_state "CLIENT_SUBNET_ACCESS")
    echo -e "  Current state: ${BOLD}${current:-disabled}${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} Enable (adds FORWARD rules and proxy_arp)"
    echo -e "  ${BOLD}2)${NC} Disable"
    echo -e "  ${BOLD}0)${NC} Back"
    echo ""
    echo -en "${YELLOW}  ?${NC}  Enter choice: "
    read -r csa_choice

    case "$csa_choice" in
        1)
            local iface
            iface=$(get_primary_iface)

            # Enable proxy_arp
            echo 1 > "/proc/sys/net/ipv4/conf/${iface}/proxy_arp" 2>/dev/null || true

            # Add FORWARD rules from server interface to VPN subnets
            fw_add FORWARD -i "$iface" -d "${IKEV2_SUBNET}" -j ACCEPT
            fw_add FORWARD -i "$iface" -d "${L2TP_SUBNET}"  -j ACCEPT
            fw_add FORWARD -i "$iface" -d "${WG_SUBNET}"    -j ACCEPT
            fw_add FORWARD -i "$iface" -d "${OVPN_SUBNET}"  -j ACCEPT

            # Persist proxy_arp via sysctl
            local sysctl_file="/etc/sysctl.d/99-vpn-forwarding.conf"
            if ! grep -q "proxy_arp" "$sysctl_file" 2>/dev/null; then
                echo "net.ipv4.conf.${iface}.proxy_arp = 1" >> "$sysctl_file"
            fi

            save_iptables
            save_state "CLIENT_SUBNET_ACCESS" "enabled"
            print_success "LAN devices can now reach VPN clients."
            ;;
        2)
            local iface
            iface=$(get_primary_iface)
            echo 0 > "/proc/sys/net/ipv4/conf/${iface}/proxy_arp" 2>/dev/null || true
            fw_delete FORWARD -i "$iface" -d "${IKEV2_SUBNET}" -j ACCEPT 2>/dev/null || true
            fw_delete FORWARD -i "$iface" -d "${L2TP_SUBNET}"  -j ACCEPT 2>/dev/null || true
            fw_delete FORWARD -i "$iface" -d "${WG_SUBNET}"    -j ACCEPT 2>/dev/null || true
            fw_delete FORWARD -i "$iface" -d "${OVPN_SUBNET}"  -j ACCEPT 2>/dev/null || true
            save_iptables
            save_state "CLIENT_SUBNET_ACCESS" "disabled"
            print_success "LAN-to-VPN-client access disabled."
            ;;
        0) return ;;
    esac
    press_enter
}

#==============================================================================
# §31  ADVANCED: PORT FORWARDING TO VPN CLIENTS
#==============================================================================

port_forwarding_menu() {
    while true; do
        print_section "Port Forwarding to VPN Clients"

        # List current rules
        local pf_rules
        pf_rules=$(get_state "PORT_FORWARDING_RULES")
        if [ -n "$pf_rules" ]; then
            echo -e "  ${BOLD}Current rules:${NC}"
            echo "$pf_rules" | tr ';' '\n' | grep -v '^$' | while read -r rule; do
                echo -e "  ${CYAN}  •${NC} ${rule}"
            done
        else
            echo -e "  ${DIM}  No port forwarding rules configured.${NC}"
        fi

        echo ""
        echo -e "  ${BOLD}1)${NC} Add port forwarding rule"
        echo -e "  ${BOLD}2)${NC} Remove a rule"
        echo -e "  ${BOLD}0)${NC} Back"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r pf_choice

        case "$pf_choice" in
            1) add_port_forward_rule ;;
            2) remove_port_forward_rule ;;
            0) return ;;
            *) print_warning "Invalid choice." ;;
        esac
    done
}

add_port_forward_rule() {
    print_step "Add port forwarding rule"
    echo ""

    # Protocol
    local proto
    while true; do
        echo -en "${YELLOW}  ?${NC}  Protocol [tcp/udp]: "
        read -r proto
        case "${proto,,}" in
            tcp|udp) break ;;
            *) print_warning "Enter 'tcp' or 'udp'." ;;
        esac
    done

    # External port
    local ext_port
    while true; do
        echo -en "${YELLOW}  ?${NC}  External port (1-65535): "
        read -r ext_port
        if echo "$ext_port" | grep -qE '^[0-9]+$' && [ "$ext_port" -ge 1 ] && [ "$ext_port" -le 65535 ]; then
            break
        fi
        print_warning "Invalid port number."
    done

    # VPN client IP
    local client_ip
    while true; do
        echo -en "${YELLOW}  ?${NC}  VPN client IP (e.g. 10.20.20.2): "
        read -r client_ip
        echo "$client_ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' && break
        print_warning "Invalid IP address."
    done

    # Internal port
    local int_port
    while true; do
        echo -en "${YELLOW}  ?${NC}  Internal port on client (default: ${ext_port}): "
        read -r int_port
        int_port="${int_port:-$ext_port}"
        if echo "$int_port" | grep -qE '^[0-9]+$' && [ "$int_port" -ge 1 ] && [ "$int_port" -le 65535 ]; then
            break
        fi
        print_warning "Invalid port number."
    done

    # Apply the rule
    local iface
    iface=$(get_primary_iface)

    # DNAT: incoming on external port → client IP:internal port
    iptables -t nat -A PREROUTING -i "$iface" -p "$proto" --dport "$ext_port" \
        -j DNAT --to-destination "${client_ip}:${int_port}"

    # FORWARD: allow forwarded traffic to client
    iptables -A FORWARD -p "$proto" -d "$client_ip" --dport "$int_port" -j ACCEPT

    save_iptables

    # Save rule to state
    local rule_str="${proto}:${ext_port}->${client_ip}:${int_port}"
    local existing_rules
    existing_rules=$(get_state "PORT_FORWARDING_RULES")
    if [ -n "$existing_rules" ]; then
        save_state "PORT_FORWARDING_RULES" "${existing_rules};${rule_str}"
    else
        save_state "PORT_FORWARDING_RULES" "$rule_str"
    fi

    print_success "Port forwarding rule added: ${rule_str}"
    press_enter
}

remove_port_forward_rule() {
    local pf_rules
    pf_rules=$(get_state "PORT_FORWARDING_RULES")

    if [ -z "$pf_rules" ]; then
        print_warning "No rules to remove."
        press_enter
        return
    fi

    echo ""
    echo -e "  Select rule to remove:"
    echo ""
    local i=1
    local rule_array=()
    while IFS= read -r rule; do
        [ -z "$rule" ] && continue
        echo -e "  ${BOLD}${i})${NC} ${rule}"
        rule_array+=("$rule")
        ((i++))
    done <<< "$(echo "$pf_rules" | tr ';' '\n')"
    echo -e "  ${BOLD}0)${NC} Cancel"
    echo ""

    local sel
    while true; do
        echo -en "${YELLOW}  ?${NC}  Enter number: "
        read -r sel
        [ "$sel" = "0" ] && return
        if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ] 2>/dev/null; then
            break
        fi
        print_warning "Invalid selection."
    done

    local target_rule="${rule_array[$((sel-1))]}"
    local iface
    iface=$(get_primary_iface)

    # Parse rule: proto:ext_port->client_ip:int_port
    local proto ext_port client_ip int_port
    proto=$(echo "$target_rule" | cut -d: -f1)
    ext_port=$(echo "$target_rule" | cut -d: -f2 | cut -d'>' -f1 | tr -d '-')
    client_ip=$(echo "$target_rule" | cut -d'>' -f2 | cut -d: -f1)
    int_port=$(echo "$target_rule" | cut -d'>' -f2 | cut -d: -f2)

    # Remove iptables rules
    iptables -t nat -D PREROUTING -i "$iface" -p "$proto" --dport "$ext_port" \
        -j DNAT --to-destination "${client_ip}:${int_port}" 2>/dev/null || true
    iptables -D FORWARD -p "$proto" -d "$client_ip" --dport "$int_port" -j ACCEPT 2>/dev/null || true

    save_iptables

    # Remove from state
    local new_rules
    new_rules=$(echo "$pf_rules" | tr ';' '\n' | grep -Fxv "$target_rule" | tr '\n' ';' | sed 's/;$//')
    save_state "PORT_FORWARDING_RULES" "$new_rules"

    print_success "Rule removed: ${target_rule}"
    press_enter
}

#==============================================================================
# §32  ADVANCED: DISABLE IPv6
#==============================================================================

disable_ipv6_menu() {
    print_section "IPv6 Configuration"
    local current
    current=$(get_state "IPV6_ENABLED")
    echo -e "  Current IPv6 state: ${BOLD}${current:-disabled}${NC}"
    echo ""

    if [ "$current" = "yes" ]; then
        echo -e "  ${BOLD}1)${NC} Disable IPv6 (system-wide)"
        echo -e "  ${BOLD}0)${NC} Back"
        echo ""
        echo -en "${YELLOW}  ?${NC}  Enter choice: "
        read -r ipv6_choice

        if [ "$ipv6_choice" = "1" ]; then
            disable_ipv6_system
        fi
    else
        print_info "IPv6 is already disabled."
    fi
    press_enter
}

disable_ipv6_system() {
    print_step "Disabling IPv6 system-wide..."

    # Sysctl
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 &>/dev/null || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 &>/dev/null || true
    sysctl -w net.ipv6.conf.lo.disable_ipv6=1 &>/dev/null || true

    # Persist
    local sysctl_file="/etc/sysctl.d/99-vpn-forwarding.conf"
    cat >> "$sysctl_file" << 'IPV6_SYSCTL'

# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
IPV6_SYSCTL
    sysctl -p "$sysctl_file" &>/dev/null || true

    # Remove IPv6 from WireGuard config
    if vpn_is_installed "$VPN_WG" && [ -f /etc/wireguard/wg0.conf ]; then
        sed -i 's|Address = .*,.*|Address = '"${WG_SERVER_IP}/24"'|' /etc/wireguard/wg0.conf
        sed -i '/ip6tables/d' /etc/wireguard/wg0.conf
        wg-quick down wg0 2>/dev/null || true
        wg-quick up wg0 2>/dev/null || true
    fi

    # Remove IPv6 from OpenVPN
    if vpn_is_installed "$VPN_OVPN" && [ -f "${OPENVPN_DIR}/server.conf" ]; then
        sed -i '/server-ipv6/d' "${OPENVPN_DIR}/server.conf"
        sed -i '/route-ipv6/d' "${OPENVPN_DIR}/server.conf"
        service_restart "$(get_openvpn_svc)"
    fi

    # Flush ip6tables
    ip6tables -F 2>/dev/null || true
    ip6tables -t nat -F 2>/dev/null || true

    save_state "IPV6_ENABLED" "no"
    print_success "IPv6 disabled system-wide and removed from VPN configurations."
}
#==============================================================================
# §33  POST-INSTALL VALIDATION (with auto-fix)
#==============================================================================

# Check if a UDP port is listening
check_port_listening() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -ulnp 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v netstat &>/dev/null; then
        netstat -ulnp 2>/dev/null | grep -q ":${port} " && return 0
    fi
    return 1
}

# Wait for a systemd service to leave "activating" state (up to N seconds)
wait_for_service() {
    local svc="$1"
    local max_wait="${2:-5}"
    local i=0
    while [ "$i" -lt "$max_wait" ]; do
        local state
        state=$(systemctl is-active "$svc" 2>/dev/null)
        [ "$state" != "activating" ] && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# Attempt to start/restart a service and wait for it to become active
try_fix_service() {
    local svc="$1"
    local label="$2"
    print_info "Attempting to restart ${label}..."
    systemctl restart "$svc" &>/dev/null
    sleep 2
    wait_for_service "$svc" 5
    if service_is_active "$svc"; then
        print_done "${label} restarted successfully"
        return 0
    fi
    return 1
}

# Check if strongSwan is active (tries both service names)
strongswan_is_active() {
    service_is_active "strongswan" || service_is_active "strongswan-starter"
}

# Restart strongSwan (tries both service names)
restart_strongswan() {
    systemctl restart strongswan &>/dev/null || systemctl restart strongswan-starter &>/dev/null
    sleep 2
}

validate_ikev2() {
    local errors=0

    # Service running
    if strongswan_is_active; then
        print_done "strongSwan service is running"
    else
        print_warning "strongSwan service is NOT running — attempting restart..."
        restart_strongswan
        if strongswan_is_active; then
            print_done "strongSwan service restarted successfully"
        else
            print_error "strongSwan service could NOT be started"
            errors=$((errors + 1))
        fi
    fi

    # Ports — if not listening, service restart above may not have settled yet
    if check_port_listening "$IKEV2_PORT"; then
        print_done "UDP port ${IKEV2_PORT} (IKE) is listening"
    else
        # Port comes from the service — if service was just restarted, wait a moment
        sleep 1
        if check_port_listening "$IKEV2_PORT"; then
            print_done "UDP port ${IKEV2_PORT} (IKE) is listening"
        else
            print_error "UDP port ${IKEV2_PORT} (IKE) is NOT listening"
            errors=$((errors + 1))
        fi
    fi
    if check_port_listening "$IKEV2_NAT_PORT"; then
        print_done "UDP port ${IKEV2_NAT_PORT} (NAT-T) is listening"
    else
        sleep 1
        if check_port_listening "$IKEV2_NAT_PORT"; then
            print_done "UDP port ${IKEV2_NAT_PORT} (NAT-T) is listening"
        else
            print_error "UDP port ${IKEV2_NAT_PORT} (NAT-T) is NOT listening"
            errors=$((errors + 1))
        fi
    fi

    # ipsec statusall — connections loaded
    local ipsec_status
    ipsec_status=$(ipsec statusall 2>/dev/null)
    if echo "$ipsec_status" | grep -q "ikev2-eap"; then
        print_done "IKEv2 EAP connection loaded"
    else
        # Try reloading connections
        print_warning "IKEv2 EAP connection not loaded — attempting ipsec reload..."
        ipsec reload &>/dev/null
        sleep 1
        ipsec_status=$(ipsec statusall 2>/dev/null)
        if echo "$ipsec_status" | grep -q "ikev2-eap"; then
            print_done "IKEv2 EAP connection loaded after reload"
        else
            print_error "IKEv2 EAP connection NOT loaded in strongSwan"
            errors=$((errors + 1))
        fi
    fi
    if echo "$ipsec_status" | grep -q "ikev2-cert"; then
        print_done "IKEv2 cert connection loaded"
    else
        if ! echo "$ipsec_status" | grep -q "ikev2-cert"; then
            # Reload was already attempted above — just re-check
            ipsec_status=$(ipsec statusall 2>/dev/null)
        fi
        if echo "$ipsec_status" | grep -q "ikev2-cert"; then
            print_done "IKEv2 cert connection loaded"
        else
            print_error "IKEv2 cert connection NOT loaded in strongSwan"
            errors=$((errors + 1))
        fi
    fi

    # Server certificate validity
    local cert_type
    cert_type=$(get_state "CERT_TYPE" 2>/dev/null)
    if [ "$cert_type" = "letsencrypt" ]; then
        local le_domain
        le_domain=$(get_state "LE_DOMAIN" 2>/dev/null)
        if [ -n "$le_domain" ] && [ -f "${LE_CERTS_BASE}/${le_domain}/fullchain.pem" ]; then
            if openssl x509 -in "${LE_CERTS_BASE}/${le_domain}/cert.pem" -noout -checkend 0 &>/dev/null; then
                print_done "Let's Encrypt server certificate is valid (not expired)"
            else
                print_error "Let's Encrypt server certificate is expired — run: certbot renew"
                errors=$((errors + 1))
            fi
        else
            print_warning "Let's Encrypt certificate files not found — verify certbot setup"
        fi
    elif [ -f "${CERTS_DIR}/server.crt" ]; then
        if openssl verify -CAfile "${CERTS_DIR}/ca.crt" "${CERTS_DIR}/server.crt" &>/dev/null; then
            print_done "Server certificate is valid (verified against CA)"
        else
            print_error "Server certificate FAILED verification against CA"
            errors=$((errors + 1))
        fi
    else
        print_error "Server certificate not found at ${CERTS_DIR}/server.crt"
        errors=$((errors + 1))
    fi

    # NAT/MASQUERADE rule
    if iptables -t nat -S 2>/dev/null | grep -q "MASQUERADE"; then
        print_done "iptables NAT MASQUERADE rule present"
    else
        print_warning "No iptables NAT MASQUERADE rule — attempting to add..."
        local iface
        iface=$(get_primary_iface)
        if [ -n "$iface" ]; then
            iptables -t nat -A POSTROUTING -s "${IKEV2_SUBNET}" -o "${iface}" -j MASQUERADE 2>/dev/null
            save_iptables
            if iptables -t nat -S 2>/dev/null | grep -q "MASQUERADE"; then
                print_done "iptables NAT MASQUERADE rule added"
            else
                print_error "Failed to add iptables NAT MASQUERADE rule"
                errors=$((errors + 1))
            fi
        else
            print_error "Cannot determine primary network interface for NAT rule"
            errors=$((errors + 1))
        fi
    fi

    return $errors
}

validate_l2tp() {
    local errors=0

    # xl2tpd service
    if service_is_active "xl2tpd"; then
        print_done "xl2tpd service is running"
    else
        print_warning "xl2tpd service is NOT running — attempting restart..."
        if try_fix_service "xl2tpd" "xl2tpd"; then
            true
        else
            print_error "xl2tpd service could NOT be started"
            errors=$((errors + 1))
        fi
    fi

    # Port 1701
    if check_port_listening "$L2TP_PORT"; then
        print_done "UDP port ${L2TP_PORT} (L2TP) is listening"
    else
        sleep 1
        if check_port_listening "$L2TP_PORT"; then
            print_done "UDP port ${L2TP_PORT} (L2TP) is listening"
        else
            print_error "UDP port ${L2TP_PORT} (L2TP) is NOT listening"
            errors=$((errors + 1))
        fi
    fi

    # strongSwan must also be running for L2TP/IPsec
    if strongswan_is_active; then
        print_done "strongSwan service is running (required for L2TP/IPsec)"
    else
        print_warning "strongSwan service is NOT running — attempting restart..."
        restart_strongswan
        if strongswan_is_active; then
            print_done "strongSwan restarted successfully"
        else
            print_error "strongSwan service could NOT be started (L2TP/IPsec will fail)"
            errors=$((errors + 1))
        fi
    fi

    # L2TP-PSK connection loaded
    local ipsec_status
    ipsec_status=$(ipsec statusall 2>/dev/null)
    if echo "$ipsec_status" | grep -q "L2TP-PSK"; then
        print_done "L2TP-PSK connection loaded in strongSwan"
    else
        print_warning "L2TP-PSK connection not loaded — attempting ipsec reload..."
        ipsec reload &>/dev/null
        sleep 1
        ipsec_status=$(ipsec statusall 2>/dev/null)
        if echo "$ipsec_status" | grep -q "L2TP-PSK"; then
            print_done "L2TP-PSK connection loaded after reload"
        else
            print_error "L2TP-PSK connection NOT loaded in strongSwan"
            errors=$((errors + 1))
        fi
    fi

    # PSK in secrets
    if grep -q "^%any %any : PSK " /etc/ipsec.secrets 2>/dev/null; then
        print_done "L2TP PSK is present in ipsec.secrets"
    else
        # Try to recover PSK from state and write it
        local saved_psk
        saved_psk=$(get_state "L2TP_PSK" 2>/dev/null)
        if [ -n "$saved_psk" ]; then
            print_warning "L2TP PSK missing from ipsec.secrets — restoring from state..."
            local escaped_psk
            escaped_psk=$(escape_ipsec "$saved_psk")
            echo "%any %any : PSK \"${escaped_psk}\"" >> /etc/ipsec.secrets
            ipsec restart &>/dev/null
            sleep 1
            if grep -q "^%any %any : PSK " /etc/ipsec.secrets 2>/dev/null; then
                print_done "L2TP PSK restored to ipsec.secrets"
            else
                print_error "Failed to restore L2TP PSK to ipsec.secrets"
                errors=$((errors + 1))
            fi
        else
            print_error "L2TP PSK is MISSING from ipsec.secrets (no saved PSK in state to restore)"
            errors=$((errors + 1))
        fi
    fi

    return $errors
}

validate_wireguard() {
    local errors=0

    # Config file (check first — service can't start without it)
    if [ -f /etc/wireguard/wg0.conf ]; then
        print_done "WireGuard config file exists"
    else
        print_error "WireGuard config file not found at /etc/wireguard/wg0.conf"
        errors=$((errors + 1))
        # Can't fix anything else without the config
        return $errors
    fi

    # Service running
    if service_is_active "wg-quick@wg0"; then
        print_done "WireGuard (wg-quick@wg0) service is running"
    else
        print_warning "WireGuard service is NOT running — attempting restart..."
        if try_fix_service "wg-quick@wg0" "WireGuard"; then
            true
        else
            print_error "WireGuard (wg-quick@wg0) service could NOT be started"
            errors=$((errors + 1))
        fi
    fi

    # Port
    if check_port_listening "$WG_PORT"; then
        print_done "UDP port ${WG_PORT} (WireGuard) is listening"
    else
        sleep 1
        if check_port_listening "$WG_PORT"; then
            print_done "UDP port ${WG_PORT} (WireGuard) is listening"
        else
            print_error "UDP port ${WG_PORT} (WireGuard) is NOT listening"
            errors=$((errors + 1))
        fi
    fi

    # wg0 interface
    if ip link show wg0 &>/dev/null; then
        print_done "wg0 interface exists"
    else
        print_error "wg0 interface does NOT exist"
        errors=$((errors + 1))
    fi

    return $errors
}

validate_openvpn() {
    local errors=0
    local ovpn_svc
    ovpn_svc=$(get_openvpn_svc)

    # Config file (check first — service can't start without it)
    if [ -f "${OPENVPN_DIR}/server.conf" ]; then
        print_done "OpenVPN server config exists"
    else
        print_error "OpenVPN server config not found at ${OPENVPN_DIR}/server.conf"
        errors=$((errors + 1))
        # Can't fix service issues without the config
        return $errors
    fi

    # Wait if service is still activating from initial install
    local svc_state
    svc_state=$(systemctl is-active "$ovpn_svc" 2>/dev/null)
    if [ "$svc_state" = "activating" ]; then
        print_info "OpenVPN is still starting, waiting up to 5 seconds..."
        wait_for_service "$ovpn_svc" 5
        svc_state=$(systemctl is-active "$ovpn_svc" 2>/dev/null)
    fi

    # Service running
    if service_is_active "$ovpn_svc"; then
        print_done "OpenVPN (${ovpn_svc}) service is running"
    else
        print_warning "OpenVPN (${ovpn_svc}) is NOT running (status: ${svc_state}) — attempting restart..."
        if try_fix_service "$ovpn_svc" "OpenVPN"; then
            true
        else
            # Try the alternate service name in case detection was wrong
            local alt_svc
            if [ "$ovpn_svc" = "openvpn@server" ]; then
                alt_svc="openvpn-server@server"
            else
                alt_svc="openvpn@server"
            fi
            print_info "Trying alternate service name: ${alt_svc}..."
            if try_fix_service "$alt_svc" "OpenVPN (${alt_svc})"; then
                # Update the cached service name
                _OPENVPN_SVC="$alt_svc"
                save_state "OPENVPN_SERVICE" "$alt_svc"
                ovpn_svc="$alt_svc"
            else
                print_error "OpenVPN service could NOT be started"
                errors=$((errors + 1))
            fi
        fi
    fi

    # Port
    if check_port_listening "$OVPN_PORT"; then
        print_done "UDP port ${OVPN_PORT} (OpenVPN) is listening"
    else
        sleep 1
        if check_port_listening "$OVPN_PORT"; then
            print_done "UDP port ${OVPN_PORT} (OpenVPN) is listening"
        else
            print_error "UDP port ${OVPN_PORT} (OpenVPN) is NOT listening"
            errors=$((errors + 1))
        fi
    fi

    # tun0 interface
    if ip link show tun0 &>/dev/null; then
        print_done "tun0 interface exists"
    else
        # May appear shortly after service starts
        sleep 1
        if ip link show tun0 &>/dev/null; then
            print_done "tun0 interface exists"
        else
            print_error "tun0 interface does NOT exist"
            errors=$((errors + 1))
        fi
    fi

    # Auth script
    if [ -f "${OPENVPN_DIR}/auth/verify.sh" ] && [ -x "${OPENVPN_DIR}/auth/verify.sh" ]; then
        print_done "OpenVPN auth verify script is present and executable"
    elif [ -f "${OPENVPN_DIR}/auth/verify.sh" ]; then
        print_warning "Auth verify script exists but is not executable — fixing permissions..."
        chmod +x "${OPENVPN_DIR}/auth/verify.sh"
        if [ -x "${OPENVPN_DIR}/auth/verify.sh" ]; then
            print_done "Auth verify script permissions fixed"
        else
            print_error "Failed to set execute permission on verify.sh"
            errors=$((errors + 1))
        fi
    else
        print_error "OpenVPN auth verify script missing at ${OPENVPN_DIR}/auth/verify.sh"
        errors=$((errors + 1))
    fi

    # Server cert EKU (extendedKeyUsage=serverAuth)
    if [ -f "${OPENVPN_DIR}/server/server.crt" ]; then
        if openssl x509 -in "${OPENVPN_DIR}/server/server.crt" -noout -purpose 2>/dev/null | grep -q "SSL server : Yes"; then
            print_done "Server certificate has serverAuth EKU"
        else
            print_warning "Server certificate may be missing serverAuth EKU"
        fi
    fi

    return $errors
}

validate_vpn_installation() {
    print_section "Post-Install Validation"
    echo ""

    local total_errors=0
    local vpn_errors
    local fixed_count=0

    # IP forwarding
    local ipv4_fwd
    ipv4_fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
    if [ "$ipv4_fwd" = "1" ]; then
        print_done "IPv4 forwarding is enabled"
    else
        print_warning "IPv4 forwarding is NOT enabled — fixing..."
        sysctl -w net.ipv4.ip_forward=1 &>/dev/null
        sysctl -w net.ipv4.conf.all.forwarding=1 &>/dev/null
        ipv4_fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
        if [ "$ipv4_fwd" = "1" ]; then
            print_done "IPv4 forwarding re-enabled"
            fixed_count=$((fixed_count + 1))
        else
            print_error "IPv4 forwarding could NOT be enabled"
            total_errors=$((total_errors + 1))
        fi
    fi

    echo ""

    if vpn_is_installed "$VPN_IKEV2"; then
        echo -e "  ${BOLD}IKEv2/IPsec:${NC}"
        vpn_errors=0
        validate_ikev2 || vpn_errors=$?
        total_errors=$((total_errors + vpn_errors))
        echo ""
    fi

    if vpn_is_installed "$VPN_L2TP"; then
        echo -e "  ${BOLD}L2TP/IPsec:${NC}"
        vpn_errors=0
        validate_l2tp || vpn_errors=$?
        total_errors=$((total_errors + vpn_errors))
        echo ""
    fi

    if vpn_is_installed "$VPN_WG"; then
        echo -e "  ${BOLD}WireGuard:${NC}"
        vpn_errors=0
        validate_wireguard || vpn_errors=$?
        total_errors=$((total_errors + vpn_errors))
        echo ""
    fi

    if vpn_is_installed "$VPN_OVPN"; then
        echo -e "  ${BOLD}OpenVPN:${NC}"
        vpn_errors=0
        validate_openvpn || vpn_errors=$?
        total_errors=$((total_errors + vpn_errors))
        echo ""
    fi

    # CA certificate
    if [ -f "${CERTS_DIR}/ca.crt" ]; then
        local ca_end
        ca_end=$(openssl x509 -in "${CERTS_DIR}/ca.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -n "$ca_end" ]; then
            print_done "CA certificate valid until: ${ca_end}"
        fi
    else
        print_error "CA certificate not found at ${CERTS_DIR}/ca.crt"
        total_errors=$((total_errors + 1))
    fi

    echo ""
    if [ "$total_errors" -eq 0 ]; then
        print_success "All validation checks passed!"
    else
        print_warning "${total_errors} issue(s) could not be auto-fixed. Review the errors above."
        print_info "Some issues may resolve after a system reboot."
    fi

    return $total_errors
}

#==============================================================================
# §34  FIRST RUN SETUP ORCHESTRATOR
#==============================================================================

first_run_setup() {
    print_header
    echo -e "  ${BOLD}Welcome to the VPN Server Setup Script!${NC}"
    echo -e "  This will install and configure your selected VPN servers."
    echo ""
    press_enter

    # Step 1: Detect OS & Architecture
    print_section "System Detection"
    detect_os
    detect_arch

    # Step 2: Gather all setup information first
    ask_vpn_selection
    ask_server_address
    ask_ipv6_support
    ask_dns_servers
    ask_user_credentials

    # Step 3: Confirm
    confirm_setup

    # Step 4: Initialize state
    init_state
    save_state "SERVER_ADDRESS"   "$SETUP_ADDRESS"
    save_state "ADDRESS_TYPE"     "$SETUP_ADDR_TYPE"
    save_state "IPV6_ENABLED"     "$SETUP_IPV6"
    save_state "DNS1"             "$SETUP_DNS1"
    save_state "DNS2"             "$SETUP_DNS2"
    save_state "L2TP_PSK"        "$SETUP_PSK"
    save_state "SETUP_DATE"      "$(date '+%Y-%m-%d %H:%M:%S')"
    [ -n "$SETUP_DNS1_V6" ] && save_state "DNS1_IPV6" "$SETUP_DNS1_V6"
    [ -n "$SETUP_DNS2_V6" ] && save_state "DNS2_IPV6" "$SETUP_DNS2_V6"
    [ -n "$SETUP_LE_EMAIL" ] && save_state "LE_EMAIL" "$SETUP_LE_EMAIL"

    # Step 5: System preparation
    system_update
    install_base_dependencies
    setup_ip_forwarding
    setup_firewall_base

    # Step 6: Generate CA and server certificate
    generate_ca_cert
    if [ "$SETUP_ADDR_TYPE" = "dns" ]; then
        if obtain_letsencrypt_cert "$SETUP_ADDRESS" "$SETUP_LE_EMAIL"; then
            print_success "Using Let's Encrypt certificate for ${SETUP_ADDRESS}."
        else
            echo ""
            print_warning "Let's Encrypt certificate could not be obtained."
            print_warning "Common causes:"
            echo -e "  ${DIM}  - Port 80 is blocked by a cloud/VPS firewall (security group)${NC}"
            echo -e "  ${DIM}  - DNS does not point to this server's IP yet${NC}"
            echo -e "  ${DIM}  - Another service is using port 80${NC}"
            echo ""
            if ask_yn "Continue with a self-signed certificate instead?" "y"; then
                print_info "Using self-signed certificate."
                generate_server_cert "$SETUP_ADDRESS" "$SETUP_ADDR_TYPE"
                save_state "CERT_TYPE" "self-signed"
            else
                print_error "Installation aborted. Fix the issue above and re-run the script."
                exit 1
            fi
        fi
    else
        generate_server_cert "$SETUP_ADDRESS" "$SETUP_ADDR_TYPE"
        save_state "CERT_TYPE" "self-signed"
    fi

    # Step 7: Install selected VPN servers
    if in_list "$VPN_IKEV2" "$SETUP_VPNS"; then
        install_ikev2
    fi

    if in_list "$VPN_L2TP" "$SETUP_VPNS"; then
        install_l2tp
    fi

    if in_list "$VPN_WG" "$SETUP_VPNS"; then
        install_wireguard
    fi

    if in_list "$VPN_OVPN" "$SETUP_VPNS"; then
        install_openvpn
    fi

    # Step 8: Create the first user
    mkdir -p "${PROFILES_BASE}"
    chmod 755 "${PROFILES_BASE}"

    create_vpn_user "$SETUP_USERNAME" "$SETUP_PASSWORD" "$SETUP_PSK"

    # Step 9: Validate installation
    validate_vpn_installation

    # Step 10: Final summary
    print_final_summary
}

print_final_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║              VPN Server Setup Complete!                      ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Server:${NC}    ${SETUP_ADDRESS}"
    echo -e "  ${BOLD}VPNs:${NC}      ${SETUP_VPNS}"
    echo -e "  ${BOLD}User:${NC}      ${SETUP_USERNAME}"
    echo -e "  ${BOLD}Profiles:${NC}  ${PROFILES_BASE}/${SETUP_USERNAME}/"
    echo ""
    echo -e "  ${CYAN}Profile files generated:${NC}"

    local user_dir="${PROFILES_BASE}/${SETUP_USERNAME}"
    if [ -d "$user_dir" ]; then
        ls "$user_dir" 2>/dev/null | while read -r f; do
            echo -e "    ${DIM}→${NC} ${f}"
        done
    fi

    echo ""
    echo -e "  ${BOLD}Service Status:${NC}"
    if vpn_is_installed "$VPN_IKEV2" || vpn_is_installed "$VPN_L2TP"; then
        local ss_status
        ss_status=$(systemctl is-active strongswan 2>/dev/null) || ss_status=$(systemctl is-active strongswan-starter 2>/dev/null) || ss_status="unknown"
        echo -e "    strongSwan  : ${ss_status}"
    fi
    if vpn_is_installed "$VPN_L2TP"; then
        local l2tp_status
        l2tp_status=$(systemctl is-active xl2tpd 2>/dev/null) || l2tp_status="unknown"
        echo -e "    xl2tpd      : ${l2tp_status}"
    fi
    if vpn_is_installed "$VPN_WG"; then
        local wg_status
        wg_status=$(systemctl is-active wg-quick@wg0 2>/dev/null) || wg_status="unknown"
        echo -e "    WireGuard   : ${wg_status}"
    fi
    if vpn_is_installed "$VPN_OVPN"; then
        local ovpn_status
        ovpn_status=$(systemctl is-active "$(get_openvpn_svc)" 2>/dev/null) || ovpn_status="unknown"
        echo -e "    OpenVPN     : ${ovpn_status}"
    fi

    echo ""
    echo -e "  ${YELLOW}${BOLD}Important ports to open on your firewall/cloud security group:${NC}"
    if vpn_is_installed "$VPN_IKEV2"; then
        echo -e "    UDP 500, UDP 4500  (IKEv2/IPsec)"
    fi
    if vpn_is_installed "$VPN_L2TP"; then
        echo -e "    UDP 1701           (L2TP)"
    fi
    if vpn_is_installed "$VPN_WG"; then
        echo -e "    UDP 51820          (WireGuard)"
    fi
    if vpn_is_installed "$VPN_OVPN"; then
        echo -e "    UDP 1194           (OpenVPN)"
    fi

    echo ""
    echo -e "  ${DIM}Re-run this script to manage users, change settings, or uninstall.${NC}"
    echo -e "  ${DIM}Profile files are in: ${PROFILES_BASE}/${NC}"
    echo ""
}

#==============================================================================
# §35  MAIN ENTRY POINT
#==============================================================================

main() {
    # Always check root first
    check_root

    # If first run, detect OS early for state detection
    if [ ! -f "$STATE_FILE" ]; then
        detect_os
        detect_arch
    fi

    if has_prior_install; then
        # Re-run mode: show management menu
        load_all_state
        detect_os
        detect_arch

        # Sanity-check SERVER_ADDRESS — a corrupted value (e.g. "1") causes every
        # generated profile to have a broken RemoteAddress. Warn loudly so the user
        # can fix it via Management Menu → Change Server Address before doing anything else.
        local saved_addr
        saved_addr=$(get_state "SERVER_ADDRESS")
        if [ -z "$saved_addr" ] || ! echo "$saved_addr" | grep -qE '^[a-zA-Z0-9._-]+$'; then
            print_warning "WARNING: SERVER_ADDRESS in state file looks corrupt: '${saved_addr}'"
            print_warning "All generated profiles will have a broken server address."
            print_warning "Go to Management Menu → 2) Change Server Address to fix this before adding users."
            echo ""
        fi

        show_management_menu
    else
        # First run: show setup wizard
        first_run_setup
    fi
}

# Execute main
main "$@"

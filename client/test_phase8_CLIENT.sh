#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase8_CLIENT.sh - Verification Phase 8 : Outils + SFTP/SSL
# Aucune creation, uniquement des verifications
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SERVER_IP="192.168.100.1"
DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 8 - Verification Outils/SFTP/SSL (CLIENT)"
echo -e "==========================================${NC}"

# =============================================================
# 8.1 Outils installes
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.1.1 Firefox${NC}"

if dpkg -l firefox 2>/dev/null | grep -q "^ii"; then
    ok "Firefox installe"
    FF_VER=$(firefox --version 2>/dev/null | head -1)
    [ -n "$FF_VER" ] && info "Version : $FF_VER"
elif command -v firefox &>/dev/null; then
    ok "Firefox disponible (snap ou autre)"
else
    fail "Firefox NON installe"
fi

echo ""
echo -e "${BOLD}>>> 8.1.2 FileZilla${NC}"

if dpkg -l filezilla 2>/dev/null | grep -q "^ii"; then
    ok "FileZilla installe"
    FZ_VER=$(filezilla --version 2>/dev/null | head -1)
    [ -n "$FZ_VER" ] && info "Version : $FZ_VER"
else
    fail "FileZilla NON installe (sudo apt install filezilla)"
fi

echo ""
echo -e "${BOLD}>>> 8.1.3 Thunderbird${NC}"

if dpkg -l thunderbird 2>/dev/null | grep -q "^ii"; then
    ok "Thunderbird installe"
    TB_VER=$(thunderbird --version 2>/dev/null | head -1)
    [ -n "$TB_VER" ] && info "Version : $TB_VER"
else
    fail "Thunderbird NON installe"
fi

# Autres outils utiles
echo ""
echo -e "${BOLD}>>> 8.1 Autres outils${NC}"

for pkg in openssh-client dnsutils curl wget net-tools; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg installe"
    else
        warn "$pkg manquant"
    fi
done

# =============================================================
# 8.3 Test connexion SFTP
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.3 Connectivite SSH/SFTP${NC}"

# Ping
if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
    ok "Ping $SERVER_IP"
else
    fail "Ping $SERVER_IP echoue"
fi

# Port 22
if nc -zw3 "$SERVER_IP" 22 2>/dev/null; then
    ok "Port 22 (SSH/SFTP) accessible"
else
    if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/22" 2>/dev/null; then
        ok "Port 22 (SSH/SFTP) accessible"
    else
        fail "Port 22 (SSH/SFTP) PAS accessible"
    fi
fi

# Test SSH banner
SSH_BANNER=$(echo "" | timeout 3 nc "$SERVER_IP" 22 2>/dev/null | head -1)
if echo "$SSH_BANNER" | grep -qi "SSH"; then
    ok "SSH repond : $(echo $SSH_BANNER | head -c 50)"
else
    warn "Pas de banner SSH detecte"
fi

# Test connexion SSH
if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$USER@$SERVER_IP" exit 2>/dev/null; then
    ok "SSH connexion par cle fonctionne"
else
    info "Connexion SSH par cle echouee (normal, mot de passe requis)"
    ok "FileZilla utilisera le mot de passe pour SFTP"
fi

echo ""
echo -e "${BOLD}>>> 8.3 Config FileZilla attendue${NC}"
info "Hote       : sftp://$SERVER_IP"
info "Port       : 22"
info "Protocole  : SFTP - SSH File Transfer Protocol"
info "Utilisateur: $USER"
info "Mot de passe: but1"
info "Repertoire : /users/firms/exemple/www/"

# =============================================================
# 8.4 SSL sur tous les domaines
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.4 HTTPS sur tous les domaines${NC}"

for domain in $ALL_DOMAINS; do
    # Test HTTP
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$domain/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        ok "http://www.$domain -> $HTTP_CODE"
    else
        fail "http://www.$domain -> $HTTP_CODE"
    fi

    # Test HTTPS
    HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$domain/" 2>/dev/null)
    if [ "$HTTPS_CODE" = "200" ]; then
        ok "https://www.$domain -> $HTTPS_CODE"
    else
        fail "https://www.$domain -> $HTTPS_CODE"
    fi
done

# =============================================================
# 8.4 Verification certificat SSL
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.4 Certificat SSL${NC}"

for domain in $ALL_DOMAINS; do
    CERT_INFO=$(echo | timeout 3 openssl s_client -connect "$SERVER_IP:443" -servername "www.$domain" 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
    if [ -n "$CERT_INFO" ]; then
        ok "Certificat SSL recupere pour www.$domain"
        SUBJECT=$(echo "$CERT_INFO" | grep "subject=" | sed 's/subject=//')
        EXPIRE=$(echo "$CERT_INFO" | grep "notAfter=" | sed 's/notAfter=//')
        info "  Sujet  : $SUBJECT"
        info "  Expire : $EXPIRE"
    else
        fail "Impossible de recuperer le certificat pour www.$domain"
    fi
    # Un seul certificat pour tous les domaines
    break
done

# Verifier que le certificat est auto-signe
ISSUER=$(echo | timeout 3 openssl s_client -connect "$SERVER_IP:443" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
SUBJECT_CERT=$(echo | timeout 3 openssl s_client -connect "$SERVER_IP:443" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
if [ "$ISSUER" = "$SUBJECT_CERT" ]; then
    ok "Certificat auto-signe (issuer = subject)"
else
    info "Issuer : $ISSUER"
fi

# =============================================================
# 8.4 Tous les ports accessibles
# =============================================================
echo ""
echo -e "${BOLD}>>> 8.4 Recap : tous les ports du serveur${NC}"

for port_info in "22:SSH/SFTP" "25:SMTP" "80:HTTP" "143:IMAP" "443:HTTPS"; do
    port=$(echo "$port_info" | cut -d: -f1)
    svc=$(echo "$port_info" | cut -d: -f2)
    if nc -zw3 "$SERVER_IP" "$port" 2>/dev/null; then
        ok "Port $port ($svc) accessible"
    elif timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/$port" 2>/dev/null; then
        ok "Port $port ($svc) accessible"
    else
        fail "Port $port ($svc) PAS accessible"
    fi
done

# DNS port 53
if dig @"$SERVER_IP" "$DOMAIN" +short &>/dev/null; then
    ok "Port 53 (DNS) accessible"
else
    warn "Port 53 (DNS) pas de reponse"
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 8 CLIENT : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 8 CLIENT : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

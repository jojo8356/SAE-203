#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# configure_client.sh - SAE S203 - Vérification & Config Client
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./configure_client.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SERVER_IP="192.168.1.1"
DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"
DB_PASS="but1"

ERRORS=0
FIXES=0

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
fix()  { echo -e "  ${YELLOW}[FIX]${NC} $1"; ((FIXES++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((ERRORS++)); }

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Vérification du Client"
echo -e "==========================================${NC}"

# =============================================================
# 1. PAQUETS
# =============================================================
echo ""
echo -e "${BOLD}>>> 1. Vérification des paquets${NC}"

PACKAGES="firefox thunderbird filezilla openssh-client dnsutils curl wget net-tools traceroute iputils-ping nano vim"

MISSING=""
for pkg in $PACKAGES; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg"
    else
        MISSING="$MISSING $pkg"
        fail "$pkg manquant"
    fi
done

if [ -n "$MISSING" ]; then
    fix "Installation des paquets manquants..."
    apt-get update -qq
    apt-get install -y $MISSING >/dev/null 2>&1
    for pkg in $MISSING; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            ok "$pkg installé"
        else
            fail "$pkg n'a pas pu être installé"
        fi
    done
fi

# =============================================================
# 2. /etc/hosts
# =============================================================
echo ""
echo -e "${BOLD}>>> 2. Vérification de /etc/hosts${NC}"

HOSTS_LINE="$SERVER_IP  www.$DOMAIN $DOMAIN www.$DOMAIN2 $DOMAIN2 www.$DOMAIN3 $DOMAIN3"

for domain in $ALL_DOMAINS; do
    if grep -q "www\.$domain" /etc/hosts 2>/dev/null; then
        ok "www.$domain dans /etc/hosts"
    else
        fix "Ajout de www.$domain dans /etc/hosts"
        # On ajoute la ligne complète une seule fois
        if ! grep -q "$SERVER_IP.*$DOMAIN" /etc/hosts 2>/dev/null; then
            echo "$HOSTS_LINE" >> /etc/hosts
        fi
        break
    fi
done

# =============================================================
# 3. RÉSOLUTION DNS
# =============================================================
echo ""
echo -e "${BOLD}>>> 3. Test de résolution DNS${NC}"

for domain in $ALL_DOMAINS; do
    RESULT=$(getent hosts "www.$domain" 2>/dev/null | awk '{print $1}')
    if [ -n "$RESULT" ]; then
        ok "www.$domain -> $RESULT"
    else
        fail "www.$domain ne se résout pas"
    fi
done

# =============================================================
# 4. CONNECTIVITÉ SERVEUR
# =============================================================
echo ""
echo -e "${BOLD}>>> 4. Test de connectivité vers le serveur ($SERVER_IP)${NC}"

# Ping
if ping -c 1 -W 3 "$SERVER_IP" &>/dev/null; then
    ok "Ping $SERVER_IP"
else
    fail "Ping $SERVER_IP échoué"
fi

# SSH (port 22)
if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/22" 2>/dev/null; then
    ok "Port 22 (SSH) accessible"
else
    fail "Port 22 (SSH) inaccessible"
fi

# HTTP (port 80)
if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/80" 2>/dev/null; then
    ok "Port 80 (HTTP) accessible"
else
    fail "Port 80 (HTTP) inaccessible"
fi

# HTTPS (port 443)
if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/443" 2>/dev/null; then
    ok "Port 443 (HTTPS) accessible"
else
    fail "Port 443 (HTTPS) inaccessible"
fi

# SMTP (port 25)
if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/25" 2>/dev/null; then
    ok "Port 25 (SMTP) accessible"
else
    fail "Port 25 (SMTP) inaccessible"
fi

# IMAP (port 143)
if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/143" 2>/dev/null; then
    ok "Port 143 (IMAP) accessible"
else
    fail "Port 143 (IMAP) inaccessible"
fi

# DNS (port 53)
if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/53" 2>/dev/null; then
    ok "Port 53 (DNS) accessible"
else
    fail "Port 53 (DNS) inaccessible"
fi

# =============================================================
# 5. TEST HTTP/HTTPS
# =============================================================
echo ""
echo -e "${BOLD}>>> 5. Test des sites web${NC}"

for domain in $ALL_DOMAINS; do
    # HTTP
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$domain/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        ok "http://www.$domain -> $HTTP_CODE"
    else
        fail "http://www.$domain -> $HTTP_CODE"
    fi

    # HTTPS
    HTTPS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$domain/" 2>/dev/null)
    if [ "$HTTPS_CODE" = "200" ]; then
        ok "https://www.$domain -> $HTTPS_CODE"
    else
        fail "https://www.$domain -> $HTTPS_CODE"
    fi
done

# phpPgAdmin
PGA_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/phppgadmin/" 2>/dev/null)
if [ "$PGA_CODE" = "200" ] || [ "$PGA_CODE" = "301" ] || [ "$PGA_CODE" = "302" ]; then
    ok "phpPgAdmin -> $PGA_CODE"
else
    fail "phpPgAdmin -> $PGA_CODE"
fi

# =============================================================
# 6. TEST SSL CERTIFICAT
# =============================================================
echo ""
echo -e "${BOLD}>>> 6. Vérification du certificat SSL${NC}"

CERT_INFO=$(echo | openssl s_client -connect "$SERVER_IP:443" -servername "www.$DOMAIN" 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
if [ -n "$CERT_INFO" ]; then
    ok "Certificat SSL récupéré"
    SUBJECT=$(echo "$CERT_INFO" | grep "subject=" | sed 's/subject=/  /')
    EXPIRE=$(echo "$CERT_INFO" | grep "notAfter=" | sed 's/notAfter=/  Expire : /')
    echo -e "  ${CYAN}$SUBJECT${NC}"
    echo -e "  ${CYAN}$EXPIRE${NC}"
else
    fail "Impossible de récupérer le certificat SSL"
fi

# =============================================================
# 7. TEST SFTP
# =============================================================
echo ""
echo -e "${BOLD}>>> 7. Test SFTP${NC}"

if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$USER@$SERVER_IP" exit 2>/dev/null; then
    ok "SSH avec clé (sans mot de passe)"
else
    if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/22" 2>/dev/null; then
        ok "Port SSH ouvert (connexion par mot de passe requise)"
    else
        fail "SSH inaccessible"
    fi
fi

# =============================================================
# 8. TEST DNS (dig)
# =============================================================
echo ""
echo -e "${BOLD}>>> 8. Test DNS via Bind9 du serveur${NC}"

for domain in $ALL_DOMAINS; do
    DIG_RESULT=$(dig @"$SERVER_IP" "www.$domain" +short 2>/dev/null)
    if [ -n "$DIG_RESULT" ]; then
        ok "dig www.$domain -> $DIG_RESULT"
    else
        fail "dig www.$domain -> pas de réponse"
    fi

    # Test MX
    MX_RESULT=$(dig @"$SERVER_IP" "$domain" MX +short 2>/dev/null)
    if [ -n "$MX_RESULT" ]; then
        ok "dig $domain MX -> $MX_RESULT"
    else
        fail "dig $domain MX -> pas de réponse"
    fi
done

# =============================================================
# 9. TEST MAIL (SMTP)
# =============================================================
echo ""
echo -e "${BOLD}>>> 9. Test SMTP${NC}"

SMTP_RESPONSE=$(echo "QUIT" | timeout 3 nc "$SERVER_IP" 25 2>/dev/null | head -1)
if echo "$SMTP_RESPONSE" | grep -q "220"; then
    ok "SMTP répond : $SMTP_RESPONSE"
else
    fail "SMTP ne répond pas"
fi

# =============================================================
# 10. TEST IMAP
# =============================================================
echo ""
echo -e "${BOLD}>>> 10. Test IMAP${NC}"

IMAP_RESPONSE=$(echo "a1 LOGOUT" | timeout 3 nc "$SERVER_IP" 143 2>/dev/null | head -1)
if echo "$IMAP_RESPONSE" | grep -qi "OK\|IMAP"; then
    ok "IMAP répond : $IMAP_RESPONSE"
else
    fail "IMAP ne répond pas"
fi

# =============================================================
# RÉSUMÉ
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
if [ $ERRORS -eq 0 ] && [ $FIXES -eq 0 ]; then
    echo -e " ${GREEN}Tout est OK ! Le client est prêt.${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e " ${YELLOW}$FIXES corrections appliquées, tout est OK.${NC}"
else
    echo -e " ${RED}$ERRORS problèmes détectés, $FIXES corrections appliquées.${NC}"
fi
echo -e "==========================================${NC}"

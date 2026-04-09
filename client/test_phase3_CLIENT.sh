#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase3_CLIENT.sh - Verification Phase 3 : DNS (Client)
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
SERVER_IP="192.168.100.1"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 3 - Verification DNS (CLIENT)"
echo -e "==========================================${NC}"

# =============================================================
# 3.7 Outils DNS installes ?
# =============================================================
echo ""
echo -e "${BOLD}>>> Prerequis : outils DNS${NC}"

for pkg in dnsutils bind9-host; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg installe"
    else
        fail "$pkg NON installe (sudo apt install $pkg)"
    fi
done

# =============================================================
# 3.7 resolv.conf pointe vers le serveur DNS ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.7 Configuration /etc/resolv.conf${NC}"

if grep -q "nameserver $SERVER_IP" /etc/resolv.conf 2>/dev/null; then
    ok "/etc/resolv.conf pointe vers $SERVER_IP"
else
    fail "/etc/resolv.conf ne pointe PAS vers $SERVER_IP"
    info "Contenu actuel :"
    grep "nameserver" /etc/resolv.conf 2>/dev/null | while read line; do
        info "  $line"
    done
    info "Pour corriger : echo 'nameserver $SERVER_IP' | sudo tee /etc/resolv.conf"
fi

# =============================================================
# 3.7 Connectivite vers le serveur DNS (port 53) ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.7 Connectivite vers le serveur DNS${NC}"

if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
    ok "Ping $SERVER_IP"
else
    fail "Ping $SERVER_IP echoue"
fi

if nc -zw2 "$SERVER_IP" 53 2>/dev/null; then
    ok "Port 53 (DNS) accessible sur $SERVER_IP"
else
    if timeout 2 bash -c "echo >/dev/tcp/$SERVER_IP/53" 2>/dev/null; then
        ok "Port 53 (TCP) accessible sur $SERVER_IP"
    else
        fail "Port 53 (DNS) PAS accessible sur $SERVER_IP"
    fi
fi

# =============================================================
# 3.8 Resolution DNS via dig @serveur
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.8 Resolution DNS (dig @$SERVER_IP)${NC}"

for domain in $ALL_DOMAINS; do
    # Enregistrement A (www)
    RESULT=$(dig @"$SERVER_IP" www.$domain +short 2>/dev/null)
    if [ -n "$RESULT" ]; then
        ok "dig www.$domain -> $RESULT"
    else
        fail "dig www.$domain -> pas de reponse"
    fi

    # Enregistrement A (@)
    RESULT_AT=$(dig @"$SERVER_IP" $domain +short 2>/dev/null)
    if [ -n "$RESULT_AT" ]; then
        ok "dig $domain -> $RESULT_AT"
    else
        fail "dig $domain -> pas de reponse"
    fi

    # Enregistrement MX
    MX=$(dig @"$SERVER_IP" $domain MX +short 2>/dev/null)
    if [ -n "$MX" ]; then
        ok "dig $domain MX -> $MX"
    else
        fail "dig $domain MX -> pas de reponse"
    fi

    # Enregistrement NS
    NS=$(dig @"$SERVER_IP" $domain NS +short 2>/dev/null)
    if [ -n "$NS" ]; then
        ok "dig $domain NS -> $NS"
    else
        fail "dig $domain NS -> pas de reponse"
    fi
done

# =============================================================
# 3.8 Resolution DNS via nslookup
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.8 Resolution DNS (nslookup)${NC}"

for domain in $ALL_DOMAINS; do
    RESULT=$(nslookup www.$domain $SERVER_IP 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    if [ -n "$RESULT" ] && [ "$RESULT" != "$SERVER_IP" ]; then
        ok "nslookup www.$domain -> $RESULT"
    else
        # Essayer autrement
        RESULT2=$(nslookup www.$domain $SERVER_IP 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}')
        if [ -n "$RESULT2" ]; then
            ok "nslookup www.$domain -> $RESULT2"
        else
            fail "nslookup www.$domain -> pas de reponse"
        fi
    fi
done

# =============================================================
# 3.8 Resolution DNS via host
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.8 Resolution DNS (host)${NC}"

for domain in $ALL_DOMAINS; do
    RESULT=$(host www.$domain $SERVER_IP 2>/dev/null | grep "has address" | awk '{print $4}')
    if [ -n "$RESULT" ]; then
        ok "host www.$domain -> $RESULT"
    else
        fail "host www.$domain -> pas de reponse"
    fi
done

# =============================================================
# 3.8 Resolution inverse (PTR)
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.8 Resolution inverse (PTR)${NC}"

PTR=$(dig @"$SERVER_IP" -x "$SERVER_IP" +short 2>/dev/null)
if [ -n "$PTR" ]; then
    ok "dig -x $SERVER_IP -> $PTR"
else
    warn "Resolution inverse $SERVER_IP -> pas de reponse (optionnel)"
fi

# =============================================================
# 3.8 Test resolution sans specifier le serveur (via resolv.conf)
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.8 Resolution via resolv.conf (sans @serveur)${NC}"

if grep -q "nameserver $SERVER_IP" /etc/resolv.conf 2>/dev/null; then
    for domain in $ALL_DOMAINS; do
        RESULT=$(dig www.$domain +short 2>/dev/null)
        if [ -n "$RESULT" ]; then
            ok "dig www.$domain (via resolv.conf) -> $RESULT"
        else
            fail "dig www.$domain (via resolv.conf) -> pas de reponse"
        fi
    done
else
    warn "resolv.conf ne pointe pas vers $SERVER_IP, test ignore"
fi

# =============================================================
# Test acces web via DNS (HTTP + HTTPS)
# =============================================================
echo ""
echo -e "${BOLD}>>> Bonus : Acces web via DNS${NC}"

for domain in $ALL_DOMAINS; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://www.$domain/" 2>/dev/null)
    if [ "$HTTP" = "200" ]; then
        ok "http://www.$domain -> $HTTP"
    else
        fail "http://www.$domain -> $HTTP"
    fi

    HTTPS=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://www.$domain/" 2>/dev/null)
    if [ "$HTTPS" = "200" ]; then
        ok "https://www.$domain -> $HTTPS"
    else
        fail "https://www.$domain -> $HTTPS"
    fi
done

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 3 CLIENT : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 3 CLIENT : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

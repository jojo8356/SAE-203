#!/bin/bash

# =============================================================
# test_phase3_SERVER.sh - Verification Phase 3 : DNS (Bind9)
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
echo " Phase 3 - Verification DNS (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 3.1 Bind9 installe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.1 Paquets Bind9 installes${NC}"

for pkg in bind9 bind9utils dnsutils; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg installe"
    else
        fail "$pkg NON installe"
    fi
done

# Bind9 actif ?
if systemctl is-active --quiet named 2>/dev/null || systemctl is-active --quiet bind9 2>/dev/null; then
    ok "Bind9 est actif"
else
    fail "Bind9 n'est PAS actif"
fi

# Bind9 active au demarrage ?
if systemctl is-enabled --quiet named 2>/dev/null || systemctl is-enabled --quiet bind9 2>/dev/null; then
    ok "Bind9 active au demarrage"
else
    fail "Bind9 PAS active au demarrage"
fi

# Port 53 ?
if ss -tlnp 2>/dev/null | grep -q ":53 " || ss -ulnp 2>/dev/null | grep -q ":53 "; then
    ok "Port 53 en ecoute"
else
    fail "Port 53 PAS en ecoute"
fi

# =============================================================
# 3.2 Zone exemple.com
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.2 Zone $DOMAIN${NC}"

# 3.2.1 Fichier de zone existe ?
ZONE_FILE="/etc/bind/db.$DOMAIN"
if [ -f "$ZONE_FILE" ]; then
    ok "Fichier de zone $ZONE_FILE existe"
else
    fail "Fichier de zone $ZONE_FILE MANQUANT"
fi

# 3.2.2 Enregistrements SOA, NS, A, MX ?
if [ -f "$ZONE_FILE" ]; then
    grep -q "SOA" "$ZONE_FILE" 2>/dev/null && ok "Enregistrement SOA present" || fail "SOA manquant dans $ZONE_FILE"
    grep -q "NS" "$ZONE_FILE" 2>/dev/null && ok "Enregistrement NS present" || fail "NS manquant dans $ZONE_FILE"
    grep -q "www" "$ZONE_FILE" 2>/dev/null && ok "Enregistrement A (www) present" || fail "A (www) manquant dans $ZONE_FILE"
    grep -q "MX" "$ZONE_FILE" 2>/dev/null && ok "Enregistrement MX present" || fail "MX manquant dans $ZONE_FILE"
    grep -q "mail" "$ZONE_FILE" 2>/dev/null && ok "Enregistrement A (mail) present" || fail "A (mail) manquant dans $ZONE_FILE"
fi

# 3.2.3 Zone declaree dans named.conf.local ?
if grep -q "zone \"$DOMAIN\"" /etc/bind/named.conf.local 2>/dev/null; then
    ok "Zone $DOMAIN declaree dans named.conf.local"
else
    fail "Zone $DOMAIN PAS declaree dans named.conf.local"
fi

# =============================================================
# 3.3 Zone exemple1.fr
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.3 Zone $DOMAIN2${NC}"

ZONE_FILE2="/etc/bind/db.$DOMAIN2"
if [ -f "$ZONE_FILE2" ]; then
    ok "Fichier de zone $ZONE_FILE2 existe"
else
    fail "Fichier de zone $ZONE_FILE2 MANQUANT"
fi

if [ -f "$ZONE_FILE2" ]; then
    grep -q "SOA" "$ZONE_FILE2" 2>/dev/null && ok "SOA present" || fail "SOA manquant"
    grep -q "NS" "$ZONE_FILE2" 2>/dev/null && ok "NS present" || fail "NS manquant"
    grep -q "www" "$ZONE_FILE2" 2>/dev/null && ok "A (www) present" || fail "A (www) manquant"
    grep -q "MX" "$ZONE_FILE2" 2>/dev/null && ok "MX present" || fail "MX manquant"
fi

if grep -q "zone \"$DOMAIN2\"" /etc/bind/named.conf.local 2>/dev/null; then
    ok "Zone $DOMAIN2 declaree dans named.conf.local"
else
    fail "Zone $DOMAIN2 PAS declaree dans named.conf.local"
fi

# =============================================================
# 3.4 Zone exemple2.eu
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.4 Zone $DOMAIN3${NC}"

ZONE_FILE3="/etc/bind/db.$DOMAIN3"
if [ -f "$ZONE_FILE3" ]; then
    ok "Fichier de zone $ZONE_FILE3 existe"
else
    fail "Fichier de zone $ZONE_FILE3 MANQUANT"
fi

if [ -f "$ZONE_FILE3" ]; then
    grep -q "SOA" "$ZONE_FILE3" 2>/dev/null && ok "SOA present" || fail "SOA manquant"
    grep -q "NS" "$ZONE_FILE3" 2>/dev/null && ok "NS present" || fail "NS manquant"
    grep -q "www" "$ZONE_FILE3" 2>/dev/null && ok "A (www) present" || fail "A (www) manquant"
    grep -q "MX" "$ZONE_FILE3" 2>/dev/null && ok "MX present" || fail "MX manquant"
fi

if grep -q "zone \"$DOMAIN3\"" /etc/bind/named.conf.local 2>/dev/null; then
    ok "Zone $DOMAIN3 declaree dans named.conf.local"
else
    fail "Zone $DOMAIN3 PAS declaree dans named.conf.local"
fi

# =============================================================
# 3.5 Zone inverse (PTR)
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.5 Zone inverse (PTR)${NC}"

# Chercher un fichier de zone inverse
REVERSE_FILE=$(ls /etc/bind/db.192* /etc/bind/db.100* 2>/dev/null | head -1)
if [ -n "$REVERSE_FILE" ]; then
    ok "Fichier de zone inverse trouve : $REVERSE_FILE"
    grep -q "PTR" "$REVERSE_FILE" 2>/dev/null && ok "Enregistrement PTR present" || fail "PTR manquant dans $REVERSE_FILE"
else
    warn "Aucun fichier de zone inverse trouve (optionnel mais recommande)"
fi

if grep -qi "in-addr.arpa" /etc/bind/named.conf.local 2>/dev/null; then
    ok "Zone inverse declaree dans named.conf.local"
else
    warn "Zone inverse PAS declaree dans named.conf.local"
fi

# =============================================================
# 3.6 Verification syntaxe Bind9
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.6 Verification syntaxe Bind9${NC}"

# named-checkconf
if command -v named-checkconf &>/dev/null; then
    if named-checkconf 2>/dev/null; then
        ok "named-checkconf : syntaxe OK"
    else
        fail "named-checkconf : ERREUR de syntaxe"
        named-checkconf 2>&1 | head -5
    fi
else
    fail "named-checkconf non disponible"
fi

# named-checkzone pour chaque domaine
if command -v named-checkzone &>/dev/null; then
    for domain in $ALL_DOMAINS; do
        zf="/etc/bind/db.$domain"
        if [ -f "$zf" ]; then
            if named-checkzone "$domain" "$zf" &>/dev/null; then
                ok "named-checkzone $domain : OK"
            else
                fail "named-checkzone $domain : ERREUR"
                named-checkzone "$domain" "$zf" 2>&1 | head -3
            fi
        fi
    done
fi

# =============================================================
# 3.6 (suite) Resolution locale
# =============================================================
echo ""
echo -e "${BOLD}>>> 3.6 Test de resolution DNS locale${NC}"

for domain in $ALL_DOMAINS; do
    RESULT=$(dig @127.0.0.1 www.$domain +short 2>/dev/null)
    if [ -n "$RESULT" ]; then
        ok "dig www.$domain -> $RESULT"
    else
        fail "dig www.$domain -> pas de reponse"
    fi
done

# Test MX
for domain in $ALL_DOMAINS; do
    MX=$(dig @127.0.0.1 $domain MX +short 2>/dev/null)
    if [ -n "$MX" ]; then
        ok "dig $domain MX -> $MX"
    else
        fail "dig $domain MX -> pas de reponse"
    fi
done

# Test resolution inverse si zone inverse existe
if [ -n "$REVERSE_FILE" ]; then
    PTR=$(dig @127.0.0.1 -x $SERVER_IP +short 2>/dev/null)
    if [ -n "$PTR" ]; then
        ok "dig -x $SERVER_IP -> $PTR"
    else
        warn "Resolution inverse pour $SERVER_IP -> pas de reponse"
    fi
fi

# =============================================================
# Contenu des fichiers de config (info)
# =============================================================
echo ""
echo -e "${BOLD}>>> Info : Contenu named.conf.local${NC}"
if [ -f /etc/bind/named.conf.local ]; then
    info "$(cat /etc/bind/named.conf.local 2>/dev/null | grep -v '^//' | grep -v '^$' | head -20)"
fi

echo ""
echo -e "${BOLD}>>> Info : IP dans les fichiers de zone${NC}"
for domain in $ALL_DOMAINS; do
    zf="/etc/bind/db.$domain"
    if [ -f "$zf" ]; then
        IP_IN_ZONE=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$zf" | head -1)
        info "$domain -> IP dans la zone : $IP_IN_ZONE"
        if [ "$IP_IN_ZONE" != "$SERVER_IP" ]; then
            warn "L'IP dans la zone ($IP_IN_ZONE) ne correspond pas a SERVER_IP ($SERVER_IP)"
        fi
    fi
done

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 3 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 3 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

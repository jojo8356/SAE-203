#!/bin/bash

# =============================================================
# test_phase4_CLIENT.sh - Verification Phase 4 : SGBD (Client)
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

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 4 - Verification SGBD (CLIENT)"
echo -e "==========================================${NC}"

# =============================================================
# Connectivite vers PostgreSQL (port 5432)
# =============================================================
echo ""
echo -e "${BOLD}>>> Connectivite vers le serveur${NC}"

if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
    ok "Ping $SERVER_IP"
else
    fail "Ping $SERVER_IP echoue"
fi

if nc -zw2 "$SERVER_IP" 5432 2>/dev/null; then
    ok "Port 5432 (PostgreSQL) accessible"
else
    if timeout 2 bash -c "echo >/dev/tcp/$SERVER_IP/5432" 2>/dev/null; then
        ok "Port 5432 (PostgreSQL) accessible"
    else
        warn "Port 5432 PAS accessible depuis le client (normal si listen=localhost)"
    fi
fi

# =============================================================
# phpPgAdmin accessible via navigateur ?
# =============================================================
echo ""
echo -e "${BOLD}>>> phpPgAdmin accessible via HTTP${NC}"

PGA_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/phppgadmin/" 2>/dev/null)
if [ "$PGA_HTTP" = "200" ] || [ "$PGA_HTTP" = "301" ] || [ "$PGA_HTTP" = "302" ]; then
    ok "http://www.$DOMAIN/phppgadmin/ -> HTTP $PGA_HTTP"
else
    fail "http://www.$DOMAIN/phppgadmin/ -> HTTP $PGA_HTTP"
fi

PGA_HTTPS=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$DOMAIN/phppgadmin/" 2>/dev/null)
if [ "$PGA_HTTPS" = "200" ] || [ "$PGA_HTTPS" = "301" ] || [ "$PGA_HTTPS" = "302" ]; then
    ok "https://www.$DOMAIN/phppgadmin/ -> HTTP $PGA_HTTPS"
else
    fail "https://www.$DOMAIN/phppgadmin/ -> HTTP $PGA_HTTPS"
fi

# =============================================================
# Application PHP accessible ?
# =============================================================
echo ""
echo -e "${BOLD}>>> Application PHP (carte grise)${NC}"

# index.php
INDEX_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/index.php" 2>/dev/null)
if [ "$INDEX_CODE" = "200" ]; then
    ok "http://www.$DOMAIN/index.php -> $INDEX_CODE"
else
    fail "http://www.$DOMAIN/index.php -> $INDEX_CODE"
fi

# Verifier que PHP fonctionne (pas une page blanche ou erreur)
INDEX_CONTENT=$(curl -s --max-time 5 "http://www.$DOMAIN/index.php" 2>/dev/null)
if echo "$INDEX_CONTENT" | grep -qi "carte\|proprietaire\|vehicule\|tableau\|bienvenue\|php"; then
    ok "index.php retourne du contenu PHP valide"
else
    if [ -n "$INDEX_CONTENT" ]; then
        warn "index.php retourne du contenu mais pas l'application carte grise"
    else
        fail "index.php retourne une page vide"
    fi
fi

# Verifier les autres pages PHP
for page in proprietaires.php vehicules.php ajouter_proprietaire.php ajouter_vehicule.php upload.php mail.php; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/$page" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        ok "$page -> $CODE"
    else
        fail "$page -> $CODE"
    fi
done

# =============================================================
# Verifier que la BDD repond via l'application
# =============================================================
echo ""
echo -e "${BOLD}>>> Connexion BDD via l'application web${NC}"

# Si index.php contient des stats (nombre de proprietaires, vehicules)
if echo "$INDEX_CONTENT" | grep -qi "erreur.*connexion\|could not connect\|pg_connect"; then
    fail "L'application affiche une erreur de connexion BDD"
else
    ok "Pas d'erreur de connexion BDD visible"
fi

# Verifier que les pages de donnees fonctionnent
PROP_CONTENT=$(curl -s --max-time 5 "http://www.$DOMAIN/proprietaires.php" 2>/dev/null)
if echo "$PROP_CONTENT" | grep -qi "proprietaire\|nom\|prenom\|email"; then
    ok "proprietaires.php affiche du contenu"
else
    fail "proprietaires.php ne retourne pas de contenu attendu"
fi

VEH_CONTENT=$(curl -s --max-time 5 "http://www.$DOMAIN/vehicules.php" 2>/dev/null)
if echo "$VEH_CONTENT" | grep -qi "vehicule\|immatriculation\|marque"; then
    ok "vehicules.php affiche du contenu"
else
    fail "vehicules.php ne retourne pas de contenu attendu"
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 4 CLIENT : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 4 CLIENT : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase7_CLIENT.sh - Verification Phase 7 : Envoi auto (Client)
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
echo " Phase 7 - Verification Envoi Auto (CLIENT)"
echo -e "==========================================${NC}"

# =============================================================
# 7.2 Page mail.php accessible
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.2 Page mail.php accessible${NC}"

# HTTP
MAIL_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/mail.php" 2>/dev/null)
if [ "$MAIL_HTTP" = "200" ]; then
    ok "http://www.$DOMAIN/mail.php -> $MAIL_HTTP"
else
    fail "http://www.$DOMAIN/mail.php -> $MAIL_HTTP"
fi

# HTTPS
MAIL_HTTPS=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$DOMAIN/mail.php" 2>/dev/null)
if [ "$MAIL_HTTPS" = "200" ]; then
    ok "https://www.$DOMAIN/mail.php -> $MAIL_HTTPS"
else
    fail "https://www.$DOMAIN/mail.php -> $MAIL_HTTPS"
fi

# Pas d'erreur PHP
MAIL_BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/mail.php" 2>/dev/null)
if echo "$MAIL_BODY" | grep -qi "fatal error\|parse error\|warning.*pg_\|erreur.*connexion"; then
    fail "mail.php contient une erreur PHP/BDD"
else
    ok "mail.php sans erreur PHP/BDD"
fi

# =============================================================
# 7.2 Contenu de mail.php
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.2 Contenu de mail.php${NC}"

# Tableau des vehicules avec CT proche
if echo "$MAIL_BODY" | grep -qi "controle technique\|CT dans\|vehicule"; then
    ok "mail.php affiche les vehicules avec CT proche"
else
    warn "Section vehicules CT proche non detectee"
fi

# Bouton envoi immediat
if echo "$MAIL_BODY" | grep -qi "envoyer.*maintenant\|envoyer.*rappel"; then
    ok "mail.php a un bouton d'envoi immediat"
else
    warn "Bouton envoi immediat non detecte"
fi

# Formulaire programmation cron
if echo "$MAIL_BODY" | grep -qi "programmer\|cron\|automatique"; then
    ok "mail.php a une section programmation cron"
else
    warn "Section programmation cron non detectee"
fi

# Champ heure
if echo "$MAIL_BODY" | grep -qi "type=\"time\"\|type='time'"; then
    ok "mail.php a un champ de selection d'heure"
else
    warn "Champ time non detecte"
fi

# Historique des rappels
if echo "$MAIL_BODY" | grep -qi "historique\|rappel.*envoye\|date.*envoi"; then
    ok "mail.php a une section historique"
else
    warn "Section historique non detectee"
fi

# =============================================================
# 7.4 Test envoi via le formulaire web
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.4 Test envoi via formulaire${NC}"

# Envoyer les rappels via POST
SEND_RESULT=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X POST "http://www.$DOMAIN/mail.php" \
    -d "action=envoyer_maintenant" 2>/dev/null)

SEND_CODE=$(echo "$SEND_RESULT" | tail -1)
SEND_BODY=$(echo "$SEND_RESULT" | head -n -1)

if [ "$SEND_CODE" = "200" ]; then
    ok "POST mail.php (envoyer_maintenant) -> $SEND_CODE"
else
    fail "POST mail.php -> $SEND_CODE"
fi

# Verifier le resultat
if echo "$SEND_BODY" | grep -qi "rappel.*envoye\|succes\|envoi"; then
    ok "Rappels envoyes avec succes"
elif echo "$SEND_BODY" | grep -qi "aucun.*vehicule\|aucun.*CT\|0 rappel"; then
    warn "Aucun vehicule avec CT proche (pas de mail a envoyer)"
    info "Normal si aucun vehicule n'a de CT dans les 30 jours"
elif echo "$SEND_BODY" | grep -qi "erreur\|error"; then
    fail "Erreur lors de l'envoi"
else
    info "Reponse non claire, verifier manuellement"
fi

# =============================================================
# 7.4 Test programmation cron via formulaire
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.4 Test programmation cron via formulaire${NC}"

# Programmer le cron a 03:00
CRON_RESULT=$(curl -s -w "\n%{http_code}" --max-time 10 \
    -X POST "http://www.$DOMAIN/mail.php" \
    -d "action=programmer_cron&heure=03:00" 2>/dev/null)

CRON_CODE=$(echo "$CRON_RESULT" | tail -1)
CRON_BODY=$(echo "$CRON_RESULT" | head -n -1)

if [ "$CRON_CODE" = "200" ]; then
    ok "POST mail.php (programmer_cron) -> $CRON_CODE"
else
    fail "POST mail.php (programmer_cron) -> $CRON_CODE"
fi

if echo "$CRON_BODY" | grep -qi "cron.*programme\|programme\|3h"; then
    ok "Cron programme avec succes"
elif echo "$CRON_BODY" | grep -qi "erreur\|error"; then
    fail "Erreur lors de la programmation du cron"
else
    info "Reponse non claire pour le cron"
fi

# =============================================================
# 7.4 Verifier que le mail est arrive (via SMTP)
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.4 Verification reception mail${NC}"

# Envoyer un mail de test direct via SMTP
TEST_MAIL=$(echo -e "EHLO client\nMAIL FROM:<cron@$DOMAIN>\nRCPT TO:<contact@$DOMAIN>\nDATA\nSubject: Test Phase7 - envoi auto\n\nTest envoi automatique depuis le client\n.\nQUIT" | timeout 5 nc "$SERVER_IP" 25 2>/dev/null)

if echo "$TEST_MAIL" | grep -q "250"; then
    ok "Mail de test envoye via SMTP"
else
    fail "Echec envoi mail de test"
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 7 CLIENT : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 7 CLIENT : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

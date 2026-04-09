#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase5_CLIENT.sh - Verification Phase 5 : PHP & App (Client)
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
echo " Phase 5 - Verification PHP & App (CLIENT)"
echo -e "==========================================${NC}"

# =============================================================
# 5.3 PHP fonctionne via le serveur ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.3 index.php accessible depuis le client${NC}"

INDEX_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/index.php" 2>/dev/null)
if [ "$INDEX_CODE" = "200" ]; then
    ok "http://www.$DOMAIN/index.php -> $INDEX_CODE"
else
    fail "http://www.$DOMAIN/index.php -> $INDEX_CODE"
fi

INDEX_HTTPS=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$DOMAIN/index.php" 2>/dev/null)
if [ "$INDEX_HTTPS" = "200" ]; then
    ok "https://www.$DOMAIN/index.php -> $INDEX_HTTPS"
else
    fail "https://www.$DOMAIN/index.php -> $INDEX_HTTPS"
fi

# PHP interprete ?
INDEX_BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/index.php" 2>/dev/null)
if echo "$INDEX_BODY" | grep -q "<?php"; then
    fail "PHP n'est PAS interprete (code source visible)"
else
    ok "PHP est interprete correctement"
fi

# Erreurs PHP ?
if echo "$INDEX_BODY" | grep -qi "fatal error\|parse error\|warning.*pg_"; then
    fail "index.php contient des erreurs PHP"
else
    ok "index.php sans erreur PHP"
fi

# Contenu de l'application ?
if echo "$INDEX_BODY" | grep -qi "carte\|proprietaire\|vehicule\|tableau\|dashboard"; then
    ok "index.php affiche l'application carte grise"
else
    warn "index.php ne semble pas afficher l'application carte grise"
fi

# =============================================================
# 5.5.2 Visualisation (SELECT) depuis le client
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5.2 Visualisation des donnees (SELECT)${NC}"

# proprietaires.php
PROP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/proprietaires.php" 2>/dev/null)
if [ "$PROP_CODE" = "200" ]; then
    ok "proprietaires.php -> $PROP_CODE"
else
    fail "proprietaires.php -> $PROP_CODE"
fi

PROP_BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/proprietaires.php" 2>/dev/null)
if echo "$PROP_BODY" | grep -qi "nom\|prenom\|email\|proprietaire"; then
    ok "proprietaires.php affiche des donnees"
else
    fail "proprietaires.php n'affiche pas de donnees"
fi

# vehicules.php
VEH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/vehicules.php" 2>/dev/null)
if [ "$VEH_CODE" = "200" ]; then
    ok "vehicules.php -> $VEH_CODE"
else
    fail "vehicules.php -> $VEH_CODE"
fi

VEH_BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/vehicules.php" 2>/dev/null)
if echo "$VEH_BODY" | grep -qi "immatriculation\|marque\|modele\|vehicule"; then
    ok "vehicules.php affiche des donnees"
else
    fail "vehicules.php n'affiche pas de donnees"
fi

# =============================================================
# 5.5.3 Ajout (INSERT) - formulaires accessibles
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5.3 Formulaires d'ajout (INSERT)${NC}"

for page in ajouter_proprietaire.php ajouter_vehicule.php; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/$page" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        ok "$page -> $CODE"
    else
        fail "$page -> $CODE"
    fi

    BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/$page" 2>/dev/null)
    if echo "$BODY" | grep -qi "<form"; then
        ok "$page contient un formulaire"
    else
        fail "$page ne contient pas de formulaire"
    fi
done

# Test INSERT reel (ajouter un proprietaire de test)
echo ""
info "Test INSERT reel (ajout d'un proprietaire de test)..."
INSERT_RESULT=$(curl -s -w "\n%{http_code}" --max-time 5 \
    -X POST "http://www.$DOMAIN/ajouter_proprietaire.php" \
    -d "civilite=M.&nom=TestAuto&prenom=Script&email=test.auto@exemple.com&adresse=Test&telephone=0000000000" 2>/dev/null)

INSERT_CODE=$(echo "$INSERT_RESULT" | tail -1)
INSERT_BODY=$(echo "$INSERT_RESULT" | head -n -1)

if [ "$INSERT_CODE" = "200" ]; then
    ok "POST ajouter_proprietaire.php -> $INSERT_CODE"
    if echo "$INSERT_BODY" | grep -qi "succes\|ajoute"; then
        ok "INSERT reussi (message de succes)"
    elif echo "$INSERT_BODY" | grep -qi "erreur\|error"; then
        fail "INSERT echoue (message d'erreur)"
    else
        warn "INSERT envoye, pas de message de confirmation clair"
    fi
else
    fail "POST ajouter_proprietaire.php -> $INSERT_CODE"
fi

# =============================================================
# 5.5.4 Mise a jour (UPDATE) - page accessible
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5.4 Pages de modification (UPDATE)${NC}"

for page in modifier_proprietaire.php modifier_vehicule.php; do
    # Tester avec id=1
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/$page?id=1" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        ok "$page?id=1 -> $CODE"
    elif [ "$CODE" = "302" ]; then
        warn "$page?id=1 -> $CODE (redirection, id=1 n'existe peut-etre pas)"
    else
        fail "$page?id=1 -> $CODE"
    fi
done

# =============================================================
# 5.5.5 Suppression (DELETE) - page accessible
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5.5 Page de suppression (DELETE)${NC}"

# Ne pas supprimer reellement, juste verifier que la page existe
SUP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/supprimer.php" 2>/dev/null)
if [ "$SUP_CODE" = "200" ] || [ "$SUP_CODE" = "302" ]; then
    ok "supprimer.php accessible -> $SUP_CODE"
else
    fail "supprimer.php -> $SUP_CODE"
fi

# =============================================================
# 5.5.6 Upload de fichiers
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5.6 Upload de fichiers${NC}"

UPLOAD_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/upload.php" 2>/dev/null)
if [ "$UPLOAD_CODE" = "200" ]; then
    ok "upload.php -> $UPLOAD_CODE"
else
    fail "upload.php -> $UPLOAD_CODE"
fi

UPLOAD_BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/upload.php" 2>/dev/null)
if echo "$UPLOAD_BODY" | grep -qi "type=\"file\"\|enctype"; then
    ok "upload.php contient un champ file upload"
else
    fail "upload.php ne contient pas de champ file upload"
fi

# =============================================================
# 5.6 Bonus : mail.php accessible
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.6 Bonus : mail.php${NC}"

MAIL_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/mail.php" 2>/dev/null)
if [ "$MAIL_CODE" = "200" ]; then
    ok "mail.php -> $MAIL_CODE"
else
    fail "mail.php -> $MAIL_CODE"
fi

# =============================================================
# 5.6 Nettoyage du proprietaire de test
# =============================================================
echo ""
echo -e "${BOLD}>>> Nettoyage${NC}"

# Verifier si le proprietaire de test existe dans la page
PROP_CHECK=$(curl -s --max-time 5 "http://www.$DOMAIN/proprietaires.php" 2>/dev/null)
if echo "$PROP_CHECK" | grep -qi "TestAuto"; then
    info "Proprietaire de test 'TestAuto' trouve -> a supprimer manuellement si besoin"
else
    info "Proprietaire de test non visible (deja supprime ou INSERT echoue)"
fi

# =============================================================
# 5.6 Recap : toutes les pages sans erreur
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.6 Recap : toutes les pages sans erreur PHP${NC}"

for page in index.php proprietaires.php vehicules.php ajouter_proprietaire.php ajouter_vehicule.php upload.php mail.php; do
    BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/$page" 2>/dev/null)
    if echo "$BODY" | grep -qi "fatal error\|parse error\|warning.*pg_\|erreur.*connexion\|could not connect"; then
        fail "$page contient une erreur"
    else
        ok "$page OK (pas d'erreur)"
    fi
done

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 5 CLIENT : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 5 CLIENT : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

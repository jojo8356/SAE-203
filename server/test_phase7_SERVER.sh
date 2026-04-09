#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase7_SERVER.sh - Verification Phase 7 : Envoi auto mails
# Aucune creation, uniquement des verifications
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DOMAIN="exemple.com"
USER="exemple"
WWW_DIR="/users/firms/exemple/www"
DB_NAME="carte_grise"
DB_USER="exemple"
DB_PASS="but1"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 7 - Verification Envoi Auto (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 7.1 Script PHP d'envoi de mails automatiques
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.1 Script cron_mail.php${NC}"

if [ -f "$WWW_DIR/cron_mail.php" ]; then
    ok "cron_mail.php existe"
else
    fail "cron_mail.php MANQUANT"
fi

if [ -f "$WWW_DIR/cron_mail.php" ]; then
    # Connexion BDD
    if grep -q "pg_connect" "$WWW_DIR/cron_mail.php" 2>/dev/null; then
        ok "cron_mail.php contient pg_connect()"
    else
        fail "pg_connect() manquant dans cron_mail.php"
    fi

    # Requete pour CT dans les 30 jours
    if grep -qi "date_controle_technique" "$WWW_DIR/cron_mail.php" 2>/dev/null; then
        ok "cron_mail.php verifie date_controle_technique"
    else
        fail "date_controle_technique non verifie dans cron_mail.php"
    fi

    if grep -qi "30 days\|30.*day\|INTERVAL" "$WWW_DIR/cron_mail.php" 2>/dev/null; then
        ok "cron_mail.php filtre sur 30 jours"
    else
        warn "Filtre 30 jours non detecte dans cron_mail.php"
    fi

    # Fonction mail()
    if grep -q "mail(" "$WWW_DIR/cron_mail.php" 2>/dev/null; then
        ok "cron_mail.php contient mail()"
    else
        fail "mail() manquant dans cron_mail.php"
    fi

    # Enregistrement dans rappel_envoye
    if grep -qi "rappel_envoye\|INSERT" "$WWW_DIR/cron_mail.php" 2>/dev/null; then
        ok "cron_mail.php enregistre les rappels envoyes"
    else
        warn "Enregistrement dans rappel_envoye non detecte"
    fi

    # Anti-spam (ne pas renvoyer si deja envoye recemment)
    if grep -qi "NOT IN\|7 days\|rappel_envoye" "$WWW_DIR/cron_mail.php" 2>/dev/null; then
        ok "cron_mail.php a une protection anti-spam"
    else
        warn "Pas de protection anti-spam detectee"
    fi

    # Test execution PHP (syntaxe)
    PHP_CHECK=$(php -l "$WWW_DIR/cron_mail.php" 2>&1)
    if echo "$PHP_CHECK" | grep -q "No syntax errors"; then
        ok "cron_mail.php syntaxe PHP OK"
    else
        fail "cron_mail.php erreur de syntaxe PHP"
        info "$PHP_CHECK"
    fi
fi

# =============================================================
# 7.1 Script mail.php (interface web)
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.1 Interface mail.php${NC}"

if [ -f "$WWW_DIR/mail.php" ]; then
    ok "mail.php existe"
else
    fail "mail.php MANQUANT"
fi

if [ -f "$WWW_DIR/mail.php" ]; then
    # Fonction mail()
    if grep -q "mail(" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php contient mail()"
    else
        fail "mail() manquant dans mail.php"
    fi

    # Envoi immediat
    if grep -qi "envoyer_maintenant\|envoyer.*maintenant" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php a un bouton envoi immediat"
    else
        warn "Bouton envoi immediat non detecte"
    fi

    # Historique rappels
    if grep -qi "rappel_envoye\|historique" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php affiche l'historique des rappels"
    else
        warn "Historique des rappels non detecte"
    fi

    # Liste vehicules CT proche
    if grep -qi "date_controle_technique.*30\|30.*days\|INTERVAL" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php liste les vehicules avec CT proche"
    else
        warn "Liste vehicules CT proche non detectee"
    fi

    # Syntaxe PHP
    PHP_CHECK=$(php -l "$WWW_DIR/mail.php" 2>&1)
    if echo "$PHP_CHECK" | grep -q "No syntax errors"; then
        ok "mail.php syntaxe PHP OK"
    else
        fail "mail.php erreur de syntaxe PHP"
    fi
fi

# =============================================================
# 7.2 Formulaire HTML pour programmer l'heure d'envoi
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.2 Formulaire programmation cron${NC}"

if [ -f "$WWW_DIR/mail.php" ]; then
    # Formulaire avec input time
    if grep -qi "type=\"time\"\|type='time'" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php a un champ input type=time"
    else
        warn "Pas de champ time detecte dans mail.php"
    fi

    # Action programmer_cron
    if grep -qi "programmer_cron\|crontab\|cron" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php gere la programmation cron"
    else
        fail "Programmation cron non detectee dans mail.php"
    fi

    # Formulaire POST
    if grep -qi "<form.*POST\|method.*POST" "$WWW_DIR/mail.php" 2>/dev/null; then
        ok "mail.php a un formulaire POST"
    else
        fail "Formulaire POST manquant dans mail.php"
    fi

    # Accessible via HTTP
    MAIL_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost/mail.php" 2>/dev/null)
    if [ "$MAIL_CODE" = "200" ]; then
        ok "http://localhost/mail.php -> $MAIL_CODE"
    else
        fail "http://localhost/mail.php -> $MAIL_CODE"
    fi

    # Pas d'erreur PHP
    MAIL_BODY=$(curl -s --max-time 5 "http://localhost/mail.php" 2>/dev/null)
    if echo "$MAIL_BODY" | grep -qi "fatal error\|parse error\|warning.*pg_"; then
        fail "mail.php contient une erreur PHP"
    else
        ok "mail.php sans erreur PHP"
    fi
fi

# =============================================================
# 7.3 Cron job configure
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.3 Cron job${NC}"

# Verifier crontab de l'utilisateur exemple
CRON_USER=$(crontab -u "$USER" -l 2>/dev/null)
if [ -n "$CRON_USER" ]; then
    CRON_MAIL=$(echo "$CRON_USER" | grep "cron_mail.php")
    if [ -n "$CRON_MAIL" ]; then
        ok "Cron configure pour $USER"
        info "Ligne cron : $CRON_MAIL"

        # Verifier le chemin du script
        if echo "$CRON_MAIL" | grep -q "$WWW_DIR/cron_mail.php"; then
            ok "Chemin du script correct dans le cron"
        else
            CRON_PATH=$(echo "$CRON_MAIL" | grep -oE '/[^ ]+cron_mail\.php')
            warn "Chemin dans cron : $CRON_PATH (attendu: $WWW_DIR/cron_mail.php)"
        fi

        # Verifier l'heure
        CRON_HOUR=$(echo "$CRON_MAIL" | awk '{print $2}')
        CRON_MIN=$(echo "$CRON_MAIL" | awk '{print $1}')
        info "Heure programmee : ${CRON_HOUR}h${CRON_MIN}"
    else
        fail "Pas de cron pour cron_mail.php"
    fi
else
    # Verifier aussi le crontab root
    CRON_ROOT=$(crontab -l 2>/dev/null | grep "cron_mail.php")
    if [ -n "$CRON_ROOT" ]; then
        ok "Cron configure (root)"
        info "Ligne cron : $CRON_ROOT"
    else
        fail "Aucun cron configure pour cron_mail.php"
    fi
fi

# Verifier que le service cron tourne
if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    ok "Service cron actif"
else
    fail "Service cron PAS actif"
fi

# =============================================================
# 7.3 Verifier le log de cron
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.3 Log cron mail${NC}"

if [ -f /var/log/carte_grise_mail.log ]; then
    ok "Log /var/log/carte_grise_mail.log existe"
    LAST_LOG=$(tail -3 /var/log/carte_grise_mail.log 2>/dev/null)
    if [ -n "$LAST_LOG" ]; then
        info "Derniers logs :"
        echo "$LAST_LOG" | while read line; do
            info "  $line"
        done
    else
        info "Log vide (le cron n'a pas encore tourne)"
    fi
else
    warn "Log /var/log/carte_grise_mail.log n'existe pas encore"
    info "Il sera cree au premier declenchement du cron"
fi

# =============================================================
# 7.4 Test envoi automatique (simulation)
# =============================================================
echo ""
echo -e "${BOLD}>>> 7.4 Test envoi automatique (simulation)${NC}"

# Verifier qu'il y a des vehicules avec CT dans les 30 jours
NB_CT=$(sudo -u postgres psql -d "$DB_NAME" -tAc \
    "SELECT COUNT(*) FROM vehicule WHERE date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days';" \
    2>/dev/null | tr -d ' ')

if [ -n "$NB_CT" ] && [ "$NB_CT" -gt 0 ] 2>/dev/null; then
    ok "$NB_CT vehicule(s) avec CT dans les 30 prochains jours"
else
    warn "Aucun vehicule avec CT dans les 30 jours (le test d'envoi n'enverra rien)"
    info "Pour tester, mettre a jour un vehicule :"
    info "  UPDATE vehicule SET date_controle_technique = CURRENT_DATE + INTERVAL '15 days' WHERE id=1;"
fi

# Tester l'execution du script cron_mail.php
if [ -f "$WWW_DIR/cron_mail.php" ]; then
    info "Execution de cron_mail.php en test..."
    CRON_OUTPUT=$(php "$WWW_DIR/cron_mail.php" 2>&1)
    if [ -n "$CRON_OUTPUT" ]; then
        echo "$CRON_OUTPUT" | while read line; do
            if echo "$line" | grep -qi "OK\|envoye\|termine"; then
                ok "$line"
            elif echo "$line" | grep -qi "ERREUR\|ECHEC\|fail"; then
                fail "$line"
            else
                info "$line"
            fi
        done
    else
        warn "cron_mail.php n'a produit aucune sortie"
    fi
fi

# Verifier si des rappels ont ete enregistres
NB_RAPPELS=$(sudo -u postgres psql -d "$DB_NAME" -tAc \
    "SELECT COUNT(*) FROM rappel_envoye;" 2>/dev/null | tr -d ' ')
info "Total rappels envoyes dans la BDD : ${NB_RAPPELS:-0}"

# Derniers rappels
if [ -n "$NB_RAPPELS" ] && [ "$NB_RAPPELS" -gt 0 ] 2>/dev/null; then
    info "Derniers rappels :"
    sudo -u postgres psql -d "$DB_NAME" -tAc \
        "SELECT r.date_envoi, v.immatriculation, r.type_rappel FROM rappel_envoye r JOIN vehicule v ON r.vehicule_id=v.id ORDER BY r.date_envoi DESC LIMIT 5;" \
        2>/dev/null | while read line; do
        info "  $line"
    done
fi

# Verifier que Postfix a traite des mails
MAIL_SENT=$(grep -c "status=sent" /var/log/mail.log 2>/dev/null)
info "Mails envoyes par Postfix (total dans les logs) : ${MAIL_SENT:-0}"

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 7 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 7 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

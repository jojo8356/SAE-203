#!/bin/bash

# =============================================================
# setup_thunderbird.sh - SAE S203 - Configuration Thunderbird
# Configure automatiquement les comptes mail dans Thunderbird
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./setup_thunderbird.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SERVER_IP="192.168.1.1"
DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"
MAIL_PASS="but1"
MAIL_USER="contact"

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
fix()  { echo -e "  ${YELLOW}[FIX]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Configuration Thunderbird"
echo -e "==========================================${NC}"

# =============================================================
# 1. TROUVER LE PROFIL THUNDERBIRD
# =============================================================
echo ""
echo -e "${BOLD}>>> 1. Recherche du profil Thunderbird${NC}"

# Trouver l'utilisateur réel (pas root)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

TB_DIR="$REAL_HOME/.thunderbird"

# Lancer Thunderbird une fois pour créer le profil si nécessaire
if [ ! -d "$TB_DIR" ]; then
    fix "Création du profil Thunderbird..."
    sudo -u "$REAL_USER" thunderbird --headless &
    sleep 3
    kill %1 2>/dev/null
    sleep 1
fi

if [ ! -d "$TB_DIR" ]; then
    fail "Impossible de trouver le répertoire Thunderbird"
    exit 1
fi

# Trouver le profil par défaut
PROFILE_DIR=$(find "$TB_DIR" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1)
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find "$TB_DIR" -maxdepth 1 -name "*.default" -type d 2>/dev/null | head -1)
fi

if [ -z "$PROFILE_DIR" ]; then
    fail "Aucun profil Thunderbird trouvé"
    exit 1
fi

ok "Profil trouvé : $(basename $PROFILE_DIR)"

# =============================================================
# 2. CONFIGURATION DES COMPTES MAIL
# =============================================================
echo ""
echo -e "${BOLD}>>> 2. Configuration des comptes mail${NC}"

PREFS_FILE="$PROFILE_DIR/prefs.js"

# Fermer Thunderbird s'il tourne
pkill -f thunderbird 2>/dev/null
sleep 2

# Sauvegarder le fichier prefs.js
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" "$PREFS_FILE.bak"
    ok "Sauvegarde de prefs.js"
fi

ACCOUNT_NUM=0
SMTP_NUM=0
ACCOUNT_LIST=""
SMTP_LIST=""

for domain in $ALL_DOMAINS; do
    EMAIL="contact@$domain"

    fix "Configuration du compte $EMAIL..."

    # Identité
    cat >> "$PREFS_FILE" <<EOF

// === Compte $EMAIL ===
user_pref("mail.identity.id${ACCOUNT_NUM}.fullName", "Contact $domain");
user_pref("mail.identity.id${ACCOUNT_NUM}.useremail", "$EMAIL");
user_pref("mail.identity.id${ACCOUNT_NUM}.smtpServer", "smtp${SMTP_NUM}");
user_pref("mail.identity.id${ACCOUNT_NUM}.valid", true);
EOF

    # Serveur IMAP
    cat >> "$PREFS_FILE" <<EOF
user_pref("mail.server.server${ACCOUNT_NUM}.hostname", "$SERVER_IP");
user_pref("mail.server.server${ACCOUNT_NUM}.name", "$EMAIL");
user_pref("mail.server.server${ACCOUNT_NUM}.port", 143);
user_pref("mail.server.server${ACCOUNT_NUM}.socketType", 0);
user_pref("mail.server.server${ACCOUNT_NUM}.type", "imap");
user_pref("mail.server.server${ACCOUNT_NUM}.userName", "$USER");
user_pref("mail.server.server${ACCOUNT_NUM}.authMethod", 3);
EOF

    # Serveur SMTP
    cat >> "$PREFS_FILE" <<EOF
user_pref("mail.smtpserver.smtp${SMTP_NUM}.hostname", "$SERVER_IP");
user_pref("mail.smtpserver.smtp${SMTP_NUM}.port", 25);
user_pref("mail.smtpserver.smtp${SMTP_NUM}.socketType", 0);
user_pref("mail.smtpserver.smtp${SMTP_NUM}.username", "$USER");
user_pref("mail.smtpserver.smtp${SMTP_NUM}.authMethod", 3);
user_pref("mail.smtpserver.smtp${SMTP_NUM}.description", "SMTP $domain");
EOF

    # Compte
    cat >> "$PREFS_FILE" <<EOF
user_pref("mail.account.account${ACCOUNT_NUM}.identities", "id${ACCOUNT_NUM}");
user_pref("mail.account.account${ACCOUNT_NUM}.server", "server${ACCOUNT_NUM}");
EOF

    if [ -n "$ACCOUNT_LIST" ]; then
        ACCOUNT_LIST="$ACCOUNT_LIST,account${ACCOUNT_NUM}"
        SMTP_LIST="$SMTP_LIST,smtp${SMTP_NUM}"
    else
        ACCOUNT_LIST="account${ACCOUNT_NUM}"
        SMTP_LIST="smtp${SMTP_NUM}"
    fi

    ok "$EMAIL configuré (IMAP: $SERVER_IP:143, SMTP: $SERVER_IP:25)"

    ACCOUNT_NUM=$((ACCOUNT_NUM + 1))
    SMTP_NUM=$((SMTP_NUM + 1))
done

# Liste des comptes et serveurs SMTP
cat >> "$PREFS_FILE" <<EOF

// === Configuration globale ===
user_pref("mail.accountmanager.accounts", "$ACCOUNT_LIST");
user_pref("mail.accountmanager.defaultaccount", "account0");
user_pref("mail.smtpservers", "$SMTP_LIST");
user_pref("mail.smtp.defaultserver", "smtp0");
user_pref("mail.startup.enabledMailCheckOnce", true);
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mail.rights.version", 1);
EOF

# Corriger les permissions
chown -R "$REAL_USER:$REAL_USER" "$TB_DIR"
ok "Permissions corrigées"

# =============================================================
# 3. TEST D'ENVOI DE MAIL
# =============================================================
echo ""
echo -e "${BOLD}>>> 3. Test d'envoi de mail${NC}"

# Envoyer un mail de test via le serveur
if command -v nc &>/dev/null; then
    SMTP_TEST=$(echo -e "EHLO client\nMAIL FROM:<test@$DOMAIN>\nRCPT TO:<contact@$DOMAIN>\nDATA\nSubject: Test SAE 203\n\nCeci est un mail de test.\n.\nQUIT" | nc -w 5 "$SERVER_IP" 25 2>/dev/null)
    if echo "$SMTP_TEST" | grep -q "250"; then
        ok "Mail de test envoyé à contact@$DOMAIN"
    else
        fail "Impossible d'envoyer le mail de test"
    fi
else
    fail "netcat non disponible pour le test"
fi

# =============================================================
# RÉSUMÉ
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
echo -e " Configuration terminée !${NC}"
echo ""
echo " Comptes configurés :"
for domain in $ALL_DOMAINS; do
    echo "   - contact@$domain"
done
echo ""
echo " Serveur IMAP : $SERVER_IP:143"
echo " Serveur SMTP : $SERVER_IP:25"
echo " Utilisateur  : $USER"
echo " Mot de passe : $MAIL_PASS"
echo ""
echo " Lancez Thunderbird pour vérifier les comptes."
echo -e "==========================================${NC}"

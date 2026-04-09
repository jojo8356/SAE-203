#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# setup_thunderbird.sh - SAE S203 - Configuration Thunderbird
# Configure automatiquement les 3 comptes mail
# Supprime les anciens comptes et recree proprement
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit etre execute en root (sudo ./setup_thunderbird.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SERVER_IP="192.168.100.1"
DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"
MAIL_PASS="but1"

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
fix()  { echo -e "  ${YELLOW}[FIX]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Configuration Thunderbird"
echo -e "==========================================${NC}"

# =============================================================
# 0. FERMER THUNDERBIRD
# =============================================================
echo ""
echo -e "${BOLD}>>> 0. Fermeture de Thunderbird${NC}"
TB_PID=$(pgrep -x thunderbird 2>/dev/null || pgrep -x thunderbird-bin 2>/dev/null)
if [ -n "$TB_PID" ]; then
    kill $TB_PID 2>/dev/null
    sleep 3
    fix "Thunderbird ferme (PID: $TB_PID)"
else
    ok "Thunderbird deja ferme"
fi

# =============================================================
# 1. TROUVER LE PROFIL THUNDERBIRD
# =============================================================
echo ""
echo -e "${BOLD}>>> 1. Recherche du profil Thunderbird${NC}"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
TB_DIR="$REAL_HOME/.thunderbird"

# Creer le profil si necessaire
if [ ! -d "$TB_DIR" ]; then
    fix "Creation du profil Thunderbird..."
    sudo -u "$REAL_USER" thunderbird --headless &
    sleep 5
    pkill -f thunderbird 2>/dev/null
    sleep 2
fi

if [ ! -d "$TB_DIR" ]; then
    fail "Impossible de trouver le repertoire Thunderbird"
    exit 1
fi

# Trouver le profil par defaut
PROFILE_DIR=$(find "$TB_DIR" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1)
if [ -z "$PROFILE_DIR" ]; then
    PROFILE_DIR=$(find "$TB_DIR" -maxdepth 1 -name "*.default" -type d 2>/dev/null | head -1)
fi

if [ -z "$PROFILE_DIR" ]; then
    fail "Aucun profil Thunderbird trouve"
    exit 1
fi

ok "Profil : $(basename $PROFILE_DIR)"
PREFS_FILE="$PROFILE_DIR/prefs.js"

# =============================================================
# 2. SAUVEGARDE ET NETTOYAGE DE PREFS.JS
# =============================================================
echo ""
echo -e "${BOLD}>>> 2. Nettoyage de prefs.js${NC}"

if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" "$PREFS_FILE.bak.$(date +%s)"
    ok "Sauvegarde creee"

    # Compter les lignes avant
    BEFORE=$(wc -l < "$PREFS_FILE")

    # Supprimer TOUTES les lignes liees aux comptes mail
    sed -i '/mail\.identity\./d' "$PREFS_FILE"
    sed -i '/mail\.server\.server/d' "$PREFS_FILE"
    sed -i '/mail\.smtpserver\./d' "$PREFS_FILE"
    sed -i '/mail\.smtpservers/d' "$PREFS_FILE"
    sed -i '/mail\.smtp\.defaultserver/d' "$PREFS_FILE"
    sed -i '/mail\.account\./d' "$PREFS_FILE"
    sed -i '/mail\.accountmanager\./d' "$PREFS_FILE"
    sed -i '/mail\.startup\.enabledMailCheckOnce/d' "$PREFS_FILE"
    sed -i '/mail\.shell\.checkDefaultClient/d' "$PREFS_FILE"
    sed -i '/mail\.rights\.version/d' "$PREFS_FILE"
    # Supprimer les anciennes IPs
    sed -i '/192\.168\.1\.1/d' "$PREFS_FILE"
    # Supprimer les commentaires de comptes
    sed -i '/=== Compte/d' "$PREFS_FILE"
    sed -i '/=== Configuration globale/d' "$PREFS_FILE"
    # Supprimer les lignes vides en double
    sed -i '/^$/N;/^\n$/d' "$PREFS_FILE"

    AFTER=$(wc -l < "$PREFS_FILE")
    fix "Anciennes configs supprimees ($BEFORE -> $AFTER lignes)"
else
    info "prefs.js n'existe pas, creation..."
    touch "$PREFS_FILE"
fi

# =============================================================
# 3. ECRITURE DES NOUVEAUX COMPTES
# =============================================================
echo ""
echo -e "${BOLD}>>> 3. Configuration des comptes mail${NC}"

# Thunderbird utilise des numeros a partir de 1 pour les comptes utilisateur
# server1, server2, server3 = IMAP pour les 3 domaines
# server4 = Local Folders (obligatoire)
# smtp1, smtp2, smtp3 = SMTP pour les 3 domaines
# account1, account2, account3 = les 3 comptes
# account4 = Local Folders
# id1, id2, id3 = les 3 identites

cat >> "$PREFS_FILE" <<EOF

// ============================================================
// SAE S203 - Comptes mail configures automatiquement
// Serveur : $SERVER_IP
// Date : $(date '+%Y-%m-%d %H:%M:%S')
// ============================================================

// --- Identite 1 : contact@$DOMAIN ---
user_pref("mail.identity.id1.fullName", "Contact $DOMAIN");
user_pref("mail.identity.id1.useremail", "contact@$DOMAIN");
user_pref("mail.identity.id1.smtpServer", "smtp1");
user_pref("mail.identity.id1.valid", true);

// --- Identite 2 : contact@$DOMAIN2 ---
user_pref("mail.identity.id2.fullName", "Contact $DOMAIN2");
user_pref("mail.identity.id2.useremail", "contact@$DOMAIN2");
user_pref("mail.identity.id2.smtpServer", "smtp2");
user_pref("mail.identity.id2.valid", true);

// --- Identite 3 : contact@$DOMAIN3 ---
user_pref("mail.identity.id3.fullName", "Contact $DOMAIN3");
user_pref("mail.identity.id3.useremail", "contact@$DOMAIN3");
user_pref("mail.identity.id3.smtpServer", "smtp3");
user_pref("mail.identity.id3.valid", true);

// --- Serveur IMAP 1 : $DOMAIN ---
user_pref("mail.server.server1.hostname", "$SERVER_IP");
user_pref("mail.server.server1.name", "contact@$DOMAIN");
user_pref("mail.server.server1.port", 143);
user_pref("mail.server.server1.socketType", 0);
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.userName", "$USER");
user_pref("mail.server.server1.authMethod", 3);

// --- Serveur IMAP 2 : $DOMAIN2 ---
user_pref("mail.server.server2.hostname", "$SERVER_IP");
user_pref("mail.server.server2.name", "contact@$DOMAIN2");
user_pref("mail.server.server2.port", 143);
user_pref("mail.server.server2.socketType", 0);
user_pref("mail.server.server2.type", "imap");
user_pref("mail.server.server2.userName", "$USER");
user_pref("mail.server.server2.authMethod", 3);

// --- Serveur IMAP 3 : $DOMAIN3 ---
user_pref("mail.server.server3.hostname", "$SERVER_IP");
user_pref("mail.server.server3.name", "contact@$DOMAIN3");
user_pref("mail.server.server3.port", 143);
user_pref("mail.server.server3.socketType", 0);
user_pref("mail.server.server3.type", "imap");
user_pref("mail.server.server3.userName", "$USER");
user_pref("mail.server.server3.authMethod", 3);

// --- Local Folders (obligatoire) ---
user_pref("mail.server.server4.directory-rel", "[ProfD]Mail/Local Folders");
user_pref("mail.server.server4.hostname", "Local Folders");
user_pref("mail.server.server4.name", "Dossiers locaux");
user_pref("mail.server.server4.type", "none");
user_pref("mail.server.server4.userName", "nobody");

// --- SMTP 1 : $DOMAIN ---
user_pref("mail.smtpserver.smtp1.hostname", "$SERVER_IP");
user_pref("mail.smtpserver.smtp1.port", 25);
user_pref("mail.smtpserver.smtp1.socketType", 0);
user_pref("mail.smtpserver.smtp1.try_ssl", 0);
user_pref("mail.smtpserver.smtp1.username", "$USER");
user_pref("mail.smtpserver.smtp1.authMethod", 3);
user_pref("mail.smtpserver.smtp1.description", "SMTP $DOMAIN");

// --- SMTP 2 : $DOMAIN2 ---
user_pref("mail.smtpserver.smtp2.hostname", "$SERVER_IP");
user_pref("mail.smtpserver.smtp2.port", 25);
user_pref("mail.smtpserver.smtp2.socketType", 0);
user_pref("mail.smtpserver.smtp2.try_ssl", 0);
user_pref("mail.smtpserver.smtp2.username", "$USER");
user_pref("mail.smtpserver.smtp2.authMethod", 3);
user_pref("mail.smtpserver.smtp2.description", "SMTP $DOMAIN2");

// --- SMTP 3 : $DOMAIN3 ---
user_pref("mail.smtpserver.smtp3.hostname", "$SERVER_IP");
user_pref("mail.smtpserver.smtp3.port", 25);
user_pref("mail.smtpserver.smtp3.socketType", 0);
user_pref("mail.smtpserver.smtp3.try_ssl", 0);
user_pref("mail.smtpserver.smtp3.username", "$USER");
user_pref("mail.smtpserver.smtp3.authMethod", 3);
user_pref("mail.smtpserver.smtp3.description", "SMTP $DOMAIN3");

// --- Comptes ---
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.account.account2.identities", "id2");
user_pref("mail.account.account2.server", "server2");
user_pref("mail.account.account3.identities", "id3");
user_pref("mail.account.account3.server", "server3");
user_pref("mail.account.account4.server", "server4");

// --- Configuration globale ---
user_pref("mail.accountmanager.accounts", "account1,account2,account3,account4");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.accountmanager.localfoldersserver", "server4");
user_pref("mail.smtpservers", "smtp1,smtp2,smtp3");
user_pref("mail.smtp.defaultserver", "smtp1");
user_pref("mail.startup.enabledMailCheckOnce", true);
user_pref("mail.shell.checkDefaultClient", false);
user_pref("mail.rights.version", 1);
EOF

ok "3 comptes ecrits dans prefs.js"

# =============================================================
# 4. PERMISSIONS
# =============================================================
echo ""
echo -e "${BOLD}>>> 4. Permissions${NC}"
chown -R "$REAL_USER:$REAL_USER" "$TB_DIR"
ok "Permissions corrigees"

# =============================================================
# 5. VERIFICATION
# =============================================================
echo ""
echo -e "${BOLD}>>> 5. Verification${NC}"

NB_EMAILS=$(grep -c "useremail" "$PREFS_FILE" 2>/dev/null)
NB_SERVERS=$(grep -c "server.*hostname.*$SERVER_IP" "$PREFS_FILE" 2>/dev/null)
NB_SMTP=$(grep -c "smtpserver.*hostname.*$SERVER_IP" "$PREFS_FILE" 2>/dev/null)

info "Identites (emails) : $NB_EMAILS"
info "Serveurs IMAP      : $NB_SERVERS"
info "Serveurs SMTP      : $NB_SMTP"

for domain in $ALL_DOMAINS; do
    if grep -q "contact@$domain" "$PREFS_FILE" 2>/dev/null; then
        ok "contact@$domain present"
    else
        fail "contact@$domain MANQUANT"
    fi
done

if grep -q "$SERVER_IP" "$PREFS_FILE" 2>/dev/null; then
    ok "IP $SERVER_IP presente"
else
    fail "IP $SERVER_IP MANQUANTE"
fi

# Verifier qu'il n'y a plus d'ancienne IP
if grep -q "192.168.1.1" "$PREFS_FILE" 2>/dev/null; then
    fail "Ancienne IP 192.168.1.1 encore presente !"
else
    ok "Pas d'ancienne IP residuelle"
fi

# =============================================================
# 6. TEST SMTP
# =============================================================
echo ""
echo -e "${BOLD}>>> 6. Test SMTP${NC}"

if command -v nc &>/dev/null; then
    for domain in $ALL_DOMAINS; do
        SMTP_TEST=$(echo -e "EHLO client\nMAIL FROM:<test@$domain>\nRCPT TO:<contact@$domain>\nDATA\nSubject: Test setup Thunderbird - $domain\n\nTest automatique depuis setup_thunderbird.sh\n.\nQUIT" | nc -w 5 "$SERVER_IP" 25 2>/dev/null)
        if echo "$SMTP_TEST" | grep -q "250"; then
            ok "Mail de test envoye a contact@$domain"
        else
            fail "Echec envoi a contact@$domain"
        fi
    done
else
    info "netcat non disponible, test SMTP ignore"
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
echo -e " Configuration terminee !${NC}"
echo ""
echo "  Comptes configures :"
for domain in $ALL_DOMAINS; do
    echo -e "    ${CYAN}contact@$domain${NC}"
done
echo ""
echo -e "  Serveur IMAP : ${CYAN}$SERVER_IP:143${NC} (pas de SSL)"
echo -e "  Serveur SMTP : ${CYAN}$SERVER_IP:25${NC} (pas de SSL)"
echo -e "  Utilisateur  : ${CYAN}$USER${NC}"
echo -e "  Mot de passe : ${CYAN}$MAIL_PASS${NC}"
echo ""
echo "  Lancez Thunderbird pour verifier les comptes."
echo "  Le mot de passe sera demande au premier lancement."
echo -e "${BOLD}==========================================${NC}"

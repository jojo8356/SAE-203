#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase6_SERVER.sh - Verification Phase 6 : Service Mail
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
USER="exemple"
USER_HOME="/users/firms/exemple"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 6 - Verification Mail (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 6.1 Paquets installes ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.1 Paquets mail installes${NC}"

for pkg in postfix dovecot-core dovecot-imapd dovecot-pop3d; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg installe"
    else
        fail "$pkg NON installe"
    fi
done

# Postfix actif ?
if systemctl is-active --quiet postfix; then
    ok "Postfix est actif"
else
    fail "Postfix n'est PAS actif"
fi

if systemctl is-enabled --quiet postfix; then
    ok "Postfix active au demarrage"
else
    fail "Postfix PAS active au demarrage"
fi

# Dovecot actif ?
if systemctl is-active --quiet dovecot; then
    ok "Dovecot est actif"
else
    fail "Dovecot n'est PAS actif"
fi

if systemctl is-enabled --quiet dovecot; then
    ok "Dovecot active au demarrage"
else
    fail "Dovecot PAS active au demarrage"
fi

# Ports
echo ""
echo -e "${BOLD}>>> 6.1 Ports en ecoute${NC}"

for port_info in "25:SMTP/Postfix" "143:IMAP/Dovecot" "110:POP3/Dovecot"; do
    port=$(echo "$port_info" | cut -d: -f1)
    svc=$(echo "$port_info" | cut -d: -f2)
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        ok "Port $port ($svc) en ecoute"
    else
        if [ "$port" = "110" ]; then
            warn "Port $port ($svc) PAS en ecoute (optionnel si IMAP suffit)"
        else
            fail "Port $port ($svc) PAS en ecoute"
        fi
    fi
done

# =============================================================
# 6.2 Configuration Postfix
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.2 Configuration Postfix${NC}"

# 6.2.1 myhostname
MYHOSTNAME=$(postconf -h myhostname 2>/dev/null)
if [ -n "$MYHOSTNAME" ]; then
    info "myhostname = $MYHOSTNAME"
else
    fail "myhostname non configure"
fi

# mydestination contient les 3 domaines ?
MYDEST=$(postconf -h mydestination 2>/dev/null)
info "mydestination = $MYDEST"

for domain in $ALL_DOMAINS; do
    if echo "$MYDEST" | grep -q "$domain"; then
        ok "$domain dans mydestination"
    else
        fail "$domain PAS dans mydestination"
    fi
done

# home_mailbox
HOME_MAILBOX=$(postconf -h home_mailbox 2>/dev/null)
if [ -n "$HOME_MAILBOX" ] && [ "$HOME_MAILBOX" != "" ]; then
    ok "home_mailbox = $HOME_MAILBOX"
else
    fail "home_mailbox non configure (devrait etre Maildir/)"
fi

# inet_interfaces
INET_IF=$(postconf -h inet_interfaces 2>/dev/null)
info "inet_interfaces = $INET_IF"
if [ "$INET_IF" = "all" ]; then
    ok "Postfix ecoute sur toutes les interfaces"
elif [ "$INET_IF" = "loopback-only" ] || [ "$INET_IF" = "localhost" ]; then
    warn "Postfix ecoute uniquement en local (le client ne pourra pas envoyer)"
fi

# 6.2.2 Alias contact
echo ""
echo -e "${BOLD}>>> 6.2.2 Alias mail${NC}"

if [ -f /etc/aliases ]; then
    if grep -q "^contact:" /etc/aliases 2>/dev/null; then
        ALIAS_TARGET=$(grep "^contact:" /etc/aliases | awk -F: '{print $2}' | tr -d ' ')
        ok "Alias 'contact' -> $ALIAS_TARGET"
    else
        fail "Alias 'contact' MANQUANT dans /etc/aliases"
    fi
else
    fail "/etc/aliases introuvable"
fi

# aliases.db a jour ?
if [ -f /etc/aliases.db ]; then
    ALIASES_TIME=$(stat -c %Y /etc/aliases 2>/dev/null)
    DB_TIME=$(stat -c %Y /etc/aliases.db 2>/dev/null)
    if [ -n "$ALIASES_TIME" ] && [ -n "$DB_TIME" ] && [ "$DB_TIME" -ge "$ALIASES_TIME" ]; then
        ok "aliases.db a jour"
    else
        warn "aliases.db peut etre obsolete (lancer sudo newaliases)"
    fi
else
    fail "aliases.db manquant (lancer sudo newaliases)"
fi

# =============================================================
# 6.3 Configuration Dovecot
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.3 Configuration Dovecot${NC}"

# mail_location
MAIL_LOC=$(doveconf -h mail_location 2>/dev/null)
if [ -n "$MAIL_LOC" ]; then
    info "mail_location = $MAIL_LOC"
    if echo "$MAIL_LOC" | grep -qi "maildir"; then
        ok "Dovecot utilise le format Maildir"
    else
        warn "Dovecot n'utilise pas Maildir ($MAIL_LOC)"
    fi
else
    fail "mail_location non configure"
fi

# Protocoles actifs
PROTOCOLS=$(doveconf protocols 2>/dev/null)
info "$PROTOCOLS"
if echo "$PROTOCOLS" | grep -q "imap"; then
    ok "Protocole IMAP actif"
else
    fail "Protocole IMAP PAS actif"
fi

# Auth mechanisms
AUTH=$(doveconf -h auth_mechanisms 2>/dev/null)
info "auth_mechanisms = $AUTH"
if echo "$AUTH" | grep -q "plain"; then
    ok "Authentification plain active"
else
    warn "Authentification plain pas active"
fi

# disable_plaintext_auth
DISABLE_PLAIN=$(doveconf -h disable_plaintext_auth 2>/dev/null)
info "disable_plaintext_auth = $DISABLE_PLAIN"
if [ "$DISABLE_PLAIN" = "no" ]; then
    ok "Connexion en clair autorisee (necessaire sans SSL)"
else
    warn "Connexion en clair refusee (peut bloquer Thunderbird sans SSL)"
fi

# =============================================================
# 6.4 Boites mail
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.4 Boites mail${NC}"

# Maildir existe ?
if [ -d "$USER_HOME/Maildir" ]; then
    ok "Maildir existe : $USER_HOME/Maildir"
    for dir in new cur tmp; do
        if [ -d "$USER_HOME/Maildir/$dir" ]; then
            ok "Maildir/$dir existe"
        else
            fail "Maildir/$dir MANQUANT"
        fi
    done
else
    fail "Maildir MANQUANT ($USER_HOME/Maildir)"
fi

# Proprietaire du Maildir
MAILDIR_OWNER=$(stat -c %U "$USER_HOME/Maildir" 2>/dev/null)
if [ "$MAILDIR_OWNER" = "$USER" ]; then
    ok "Maildir appartient a $USER"
else
    fail "Maildir appartient a $MAILDIR_OWNER (devrait etre $USER)"
fi

# Mails recus ?
NB_MAILS=$(ls "$USER_HOME/Maildir/new/" 2>/dev/null | wc -l)
NB_MAILS_CUR=$(ls "$USER_HOME/Maildir/cur/" 2>/dev/null | wc -l)
info "Mails dans new/ : $NB_MAILS"
info "Mails dans cur/ : $NB_MAILS_CUR"

# 6.4.1 / 6.4.2 / 6.4.3 Test boites mail
echo ""
echo -e "${BOLD}>>> 6.4 Test des adresses mail${NC}"
info "Les 3 adresses (contact@exemple.com, contact@exemple1.fr, contact@exemple2.eu)"
info "sont gerees par l'alias 'contact' qui redirige vers l'utilisateur '$USER'"
info "Postfix accepte les mails pour les 3 domaines via mydestination"

# =============================================================
# 6.7 Test envoi/reception local
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.7 Test envoi/reception local${NC}"

# Test SMTP local
SMTP_RESPONSE=$(echo "QUIT" | timeout 3 nc 127.0.0.1 25 2>/dev/null | head -1)
if echo "$SMTP_RESPONSE" | grep -q "220"; then
    ok "SMTP local repond : $(echo $SMTP_RESPONSE | head -c 60)"
else
    fail "SMTP local ne repond pas"
fi

# Test IMAP local
IMAP_RESPONSE=$(echo "a1 LOGOUT" | timeout 3 nc 127.0.0.1 143 2>/dev/null | head -1)
if echo "$IMAP_RESPONSE" | grep -qi "OK\|Dovecot"; then
    ok "IMAP local repond : $(echo $IMAP_RESPONSE | head -c 60)"
else
    fail "IMAP local ne repond pas"
fi

# Envoyer un mail de test
if command -v mail &>/dev/null; then
    echo "Test Phase 6 - $(date)" | mail -s "Test Phase6 auto" contact@$DOMAIN 2>/dev/null
    sleep 1
    NB_AFTER=$(ls "$USER_HOME/Maildir/new/" 2>/dev/null | wc -l)
    if [ "$NB_AFTER" -gt "$NB_MAILS" ]; then
        ok "Mail de test recu dans Maildir/new/"
    else
        warn "Mail de test pas encore dans Maildir/new/ (delai possible)"
    fi
else
    warn "Commande 'mail' non disponible (sudo apt install mailutils)"
fi

# Verifier les logs
echo ""
echo -e "${BOLD}>>> 6.7 Derniers logs mail${NC}"
LAST_LOG=$(tail -5 /var/log/mail.log 2>/dev/null | grep -i "status=sent\|delivered" | tail -1)
if [ -n "$LAST_LOG" ]; then
    ok "Dernier envoi reussi dans les logs"
    info "$(echo $LAST_LOG | head -c 100)"
else
    LAST_ERR=$(tail -5 /var/log/mail.log 2>/dev/null | grep -i "error\|reject\|defer" | tail -1)
    if [ -n "$LAST_ERR" ]; then
        fail "Erreur dans les logs mail"
        info "$(echo $LAST_ERR | head -c 100)"
    else
        warn "Pas de log mail recent"
    fi
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 6 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 6 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

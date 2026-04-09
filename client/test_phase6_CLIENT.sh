#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase6_CLIENT.sh - Verification Phase 6 : Service Mail (Client)
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
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 6 - Verification Mail (CLIENT)"
echo -e "==========================================${NC}"

# =============================================================
# 6.5 Thunderbird installe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.5 Thunderbird installe${NC}"

if dpkg -l thunderbird 2>/dev/null | grep -q "^ii"; then
    ok "Thunderbird installe"
    TB_VER=$(thunderbird --version 2>/dev/null | head -1)
    [ -n "$TB_VER" ] && info "Version : $TB_VER"
else
    fail "Thunderbird NON installe (sudo apt install thunderbird)"
fi

# =============================================================
# Connectivite vers les ports mail du serveur
# =============================================================
echo ""
echo -e "${BOLD}>>> Connectivite vers le serveur mail${NC}"

if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
    ok "Ping $SERVER_IP"
else
    fail "Ping $SERVER_IP echoue"
fi

# Port 25 (SMTP)
if nc -zw3 "$SERVER_IP" 25 2>/dev/null; then
    ok "Port 25 (SMTP) accessible"
else
    if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/25" 2>/dev/null; then
        ok "Port 25 (SMTP) accessible"
    else
        fail "Port 25 (SMTP) PAS accessible"
    fi
fi

# Port 143 (IMAP)
if nc -zw3 "$SERVER_IP" 143 2>/dev/null; then
    ok "Port 143 (IMAP) accessible"
else
    if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/143" 2>/dev/null; then
        ok "Port 143 (IMAP) accessible"
    else
        fail "Port 143 (IMAP) PAS accessible"
    fi
fi

# Port 110 (POP3)
if nc -zw3 "$SERVER_IP" 110 2>/dev/null; then
    ok "Port 110 (POP3) accessible"
else
    warn "Port 110 (POP3) pas accessible (optionnel si IMAP suffit)"
fi

# =============================================================
# Test SMTP depuis le client
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.7 Test SMTP depuis le client${NC}"

SMTP_RESPONSE=$(echo "QUIT" | timeout 3 nc "$SERVER_IP" 25 2>/dev/null | head -1)
if echo "$SMTP_RESPONSE" | grep -q "220"; then
    ok "SMTP repond : $(echo $SMTP_RESPONSE | head -c 60)"
else
    fail "SMTP ne repond pas sur $SERVER_IP:25"
fi

# Test EHLO
EHLO_RESPONSE=$(echo -e "EHLO client\nQUIT" | timeout 3 nc "$SERVER_IP" 25 2>/dev/null)
if echo "$EHLO_RESPONSE" | grep -q "250"; then
    ok "EHLO accepte par le serveur"
else
    fail "EHLO refuse par le serveur"
fi

# =============================================================
# Test IMAP depuis le client
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.7 Test IMAP depuis le client${NC}"

IMAP_RESPONSE=$(echo "a1 LOGOUT" | timeout 3 nc "$SERVER_IP" 143 2>/dev/null | head -1)
if echo "$IMAP_RESPONSE" | grep -qi "OK\|Dovecot\|IMAP"; then
    ok "IMAP repond : $(echo $IMAP_RESPONSE | head -c 60)"
else
    fail "IMAP ne repond pas sur $SERVER_IP:143"
fi

# Test LOGIN IMAP
IMAP_LOGIN=$(echo -e "a1 LOGIN $USER but1\na2 LOGOUT" | timeout 3 nc "$SERVER_IP" 143 2>/dev/null)
if echo "$IMAP_LOGIN" | grep -q "a1 OK"; then
    ok "IMAP LOGIN reussi ($USER)"
else
    if echo "$IMAP_LOGIN" | grep -qi "plaintext\|PRIVACYREQUIRED"; then
        warn "IMAP refuse le login en clair (disable_plaintext_auth=yes)"
        info "Sur le serveur : doveconf -h disable_plaintext_auth"
        info "Corriger : sudo sed -i 's/^#*disable_plaintext_auth.*/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf"
    else
        fail "IMAP LOGIN echoue"
    fi
fi

# =============================================================
# Test envoi de mail depuis le client
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.7 Test envoi de mail depuis le client${NC}"

for domain in $ALL_DOMAINS; do
    MAIL_TEST=$(echo -e "EHLO client\nMAIL FROM:<test@$domain>\nRCPT TO:<contact@$domain>\nDATA\nSubject: Test Phase6 $domain\n\nTest depuis le client vers contact@$domain\n.\nQUIT" | timeout 5 nc "$SERVER_IP" 25 2>/dev/null)

    if echo "$MAIL_TEST" | grep -q "250.*queued\|250 2.0.0 Ok"; then
        ok "Mail envoye a contact@$domain (accepte par Postfix)"
    elif echo "$MAIL_TEST" | grep -q "250"; then
        ok "Mail envoye a contact@$domain"
    elif echo "$MAIL_TEST" | grep -qi "reject\|denied\|refused"; then
        fail "Mail rejete pour contact@$domain"
    else
        warn "Envoi a contact@$domain - reponse non claire"
        info "$(echo "$MAIL_TEST" | tail -3 | head -c 100)"
    fi
done

# =============================================================
# Test envoi inter-domaines
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.7 Test envoi inter-domaines${NC}"

# Envoyer de exemple.com vers exemple1.fr
CROSS_TEST=$(echo -e "EHLO client\nMAIL FROM:<contact@$DOMAIN>\nRCPT TO:<contact@$DOMAIN2>\nDATA\nSubject: Test inter-domaine\n\nMail de $DOMAIN vers $DOMAIN2\n.\nQUIT" | timeout 5 nc "$SERVER_IP" 25 2>/dev/null)

if echo "$CROSS_TEST" | grep -q "250"; then
    ok "Mail inter-domaine $DOMAIN -> $DOMAIN2 accepte"
else
    fail "Mail inter-domaine $DOMAIN -> $DOMAIN2 echoue"
fi

# =============================================================
# 6.6 Configuration Thunderbird
# =============================================================
echo ""
echo -e "${BOLD}>>> 6.6 Configuration Thunderbird${NC}"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
TB_DIR="$REAL_HOME/.thunderbird"

if [ -d "$TB_DIR" ]; then
    ok "Repertoire Thunderbird existe : $TB_DIR"

    # Lister tous les profils
    echo ""
    info "Profils trouves :"
    find "$TB_DIR" -maxdepth 1 -type d -name "*default*" 2>/dev/null | while read d; do
        info "  $(basename $d)"
    done

    # Trouver le profil
    PROFILE_DIR=$(find "$TB_DIR" -maxdepth 1 -name "*.default-release" -type d 2>/dev/null | head -1)
    if [ -z "$PROFILE_DIR" ]; then
        PROFILE_DIR=$(find "$TB_DIR" -maxdepth 1 -name "*.default" -type d 2>/dev/null | head -1)
    fi

    if [ -n "$PROFILE_DIR" ]; then
        ok "Profil utilise : $(basename $PROFILE_DIR)"
        info "Chemin complet : $PROFILE_DIR"

        # Verifier prefs.js
        if [ -f "$PROFILE_DIR/prefs.js" ]; then
            ok "prefs.js existe"
            PREFS_SIZE=$(wc -l < "$PROFILE_DIR/prefs.js" 2>/dev/null)
            info "prefs.js : $PREFS_SIZE lignes"

            # --- Dump complet des comptes mail ---
            echo ""
            info "=== COMPTES MAIL DANS PREFS.JS ==="

            # Identites (emails configures)
            echo ""
            info "-- Identites (emails) --"
            grep -i "useremail" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done

            NB_IDENTITIES=$(grep -c "useremail" "$PROFILE_DIR/prefs.js" 2>/dev/null)
            info "Nombre d'identites : $NB_IDENTITIES"

            # Serveurs IMAP configures
            echo ""
            info "-- Serveurs IMAP --"
            grep -i "mail.server.server.*hostname" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done
            grep -i "mail.server.server.*port" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done
            grep -i "mail.server.server.*type" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done
            grep -i "mail.server.server.*userName" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done

            # Serveurs SMTP configures
            echo ""
            info "-- Serveurs SMTP --"
            grep -i "mail.smtpserver" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done

            # Liste des comptes
            echo ""
            info "-- Comptes enregistres --"
            grep -i "mail.accountmanager" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done

            # --- Verification par domaine ---
            echo ""
            info "=== VERIFICATION PAR DOMAINE ==="

            for domain in $ALL_DOMAINS; do
                echo ""
                info "--- $domain ---"

                # Email present ?
                if grep -q "contact@$domain" "$PROFILE_DIR/prefs.js" 2>/dev/null; then
                    ok "Compte contact@$domain configure"
                    # Afficher les lignes liees
                    grep "contact@$domain" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                        info "  $line"
                    done
                else
                    fail "Compte contact@$domain PAS configure"
                    # Chercher toute mention du domaine
                    MENTIONS=$(grep -c "$domain" "$PROFILE_DIR/prefs.js" 2>/dev/null)
                    if [ "$MENTIONS" -gt 0 ] 2>/dev/null; then
                        info "  Mais '$domain' apparait $MENTIONS fois dans prefs.js :"
                        grep "$domain" "$PROFILE_DIR/prefs.js" 2>/dev/null | head -5 | while read line; do
                            info "    $line"
                        done
                    else
                        info "  '$domain' n'apparait NULLE PART dans prefs.js"
                    fi
                fi
            done

            # --- Verification IP serveur ---
            echo ""
            info "=== VERIFICATION IP SERVEUR ==="

            if grep -q "$SERVER_IP" "$PROFILE_DIR/prefs.js" 2>/dev/null; then
                ok "Serveur $SERVER_IP configure dans Thunderbird"
                NB_IP=$(grep -c "$SERVER_IP" "$PROFILE_DIR/prefs.js" 2>/dev/null)
                info "$SERVER_IP apparait $NB_IP fois"
            else
                fail "Serveur $SERVER_IP PAS configure dans Thunderbird"
                # Chercher d'autres IPs
                info "IPs trouvees dans prefs.js :"
                grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$PROFILE_DIR/prefs.js" 2>/dev/null | sort -u | while read ip; do
                    info "  $ip"
                done
                # Chercher les hostnames configures
                info "Hostnames configures :"
                grep "hostname" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                    info "  $line"
                done
            fi

            # --- Verification ports ---
            echo ""
            info "=== VERIFICATION PORTS ==="

            # Port IMAP 143
            if grep -q "143" "$PROFILE_DIR/prefs.js" 2>/dev/null; then
                ok "Port IMAP 143 configure"
                grep "143" "$PROFILE_DIR/prefs.js" 2>/dev/null | head -3 | while read line; do
                    info "  $line"
                done
            else
                warn "Port IMAP 143 pas trouve dans prefs.js"
            fi

            # Port SMTP 25
            if grep -q "\"25\"" "$PROFILE_DIR/prefs.js" 2>/dev/null || grep -q "port.*25" "$PROFILE_DIR/prefs.js" 2>/dev/null; then
                ok "Port SMTP 25 configure"
            else
                warn "Port SMTP 25 pas trouve dans prefs.js"
                info "Ports trouves dans les configs SMTP :"
                grep "smtpserver.*port" "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                    info "  $line"
                done
            fi

            # --- Dump brut des 30 dernieres lignes (souvent les ajouts) ---
            echo ""
            info "=== DERNIERS AJOUTS DANS PREFS.JS (30 dernieres lignes) ==="
            tail -30 "$PROFILE_DIR/prefs.js" 2>/dev/null | while read line; do
                info "  $line"
            done

        else
            warn "prefs.js manquant (Thunderbird jamais lance ?)"
            info "Lancez Thunderbird une fois, fermez-le, puis relancez ce test"
        fi
    else
        warn "Aucun profil Thunderbird trouve"
        info "Profils dans $TB_DIR :"
        ls -la "$TB_DIR" 2>/dev/null | while read line; do
            info "  $line"
        done
    fi
else
    warn "Thunderbird jamais lance (pas de repertoire .thunderbird)"
    info "Lancez Thunderbird une fois puis relancez ce test"
fi

# =============================================================
# Recap config Thunderbird attendue
# =============================================================
echo ""
echo -e "${BOLD}>>> Recap : config Thunderbird attendue${NC}"
info "Comptes : contact@$DOMAIN, contact@$DOMAIN2, contact@$DOMAIN3"
info "Serveur IMAP : $SERVER_IP port 143 (pas de SSL)"
info "Serveur SMTP : $SERVER_IP port 25 (pas de SSL)"
info "Utilisateur  : $USER"
info "Mot de passe : but1"

# =============================================================
# Enregistrements MX dans le DNS
# =============================================================
echo ""
echo -e "${BOLD}>>> DNS : enregistrements MX${NC}"

for domain in $ALL_DOMAINS; do
    MX=$(dig @"$SERVER_IP" "$domain" MX +short 2>/dev/null)
    if [ -n "$MX" ]; then
        ok "MX $domain -> $MX"
    else
        fail "MX $domain -> pas de reponse"
    fi
done

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 6 CLIENT : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 6 CLIENT : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

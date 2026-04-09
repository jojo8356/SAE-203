#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase9_SERVER.sh - Verification Phase 9 : Automatisation
# Verifie si le script d'ajout de domaine existe et fonctionne
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

USER="exemple"
USER_HOME="/users/firms/exemple"
WWW_DIR="$USER_HOME/www"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 9 - Verification Automatisation (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 9.1 Le script d'automatisation existe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1 Recherche du script d'automatisation${NC}"

# Chercher le script dans les emplacements courants
SCRIPT=""
for path in \
    "$USER_HOME/ajouter_domaine.sh" \
    "$USER_HOME/add_domain.sh" \
    "$USER_HOME/new_domain.sh" \
    "$USER_HOME/create_domain.sh" \
    "$USER_HOME/auto_domain.sh" \
    "/root/ajouter_domaine.sh" \
    "/root/add_domain.sh" \
    "/usr/local/bin/ajouter_domaine.sh" \
    "/usr/local/bin/add_domain.sh" \
    "./ajouter_domaine.sh" \
    "./add_domain.sh"; do
    if [ -f "$path" ]; then
        SCRIPT="$path"
        break
    fi
done

# Chercher plus largement
if [ -z "$SCRIPT" ]; then
    SCRIPT=$(find / -maxdepth 4 -name "*domaine*.sh" -o -name "*domain*.sh" 2>/dev/null | grep -v ".git\|/proc\|/sys" | head -1)
fi

if [ -n "$SCRIPT" ]; then
    ok "Script trouve : $SCRIPT"
    info "Taille : $(wc -l < "$SCRIPT") lignes"

    # Executable ?
    if [ -x "$SCRIPT" ]; then
        ok "Script executable"
    else
        warn "Script PAS executable (chmod +x $SCRIPT)"
    fi
else
    fail "Aucun script d'automatisation trouve"
    info "Emplacements cherches :"
    info "  ~/ajouter_domaine.sh, ~/add_domain.sh, ~/new_domain.sh"
    info "  /root/ajouter_domaine.sh, /usr/local/bin/ajouter_domaine.sh"
    info "  Recherche globale *domaine*.sh / *domain*.sh"
    echo ""
    echo -e "${BOLD}=========================================="
    echo -e " ${RED}Phase 9 : script d'automatisation absent${NC}"
    echo -e " ${YELLOW}Cette phase est un BONUS${NC}"
    echo -e "==========================================${NC}"
    exit 0
fi

# =============================================================
# 9.1.1 Le script gere Apache VirtualHost + SSL ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1.1 VirtualHost Apache + SSL${NC}"

if grep -qi "VirtualHost\|a2ensite\|sites-available" "$SCRIPT" 2>/dev/null; then
    ok "Le script gere les VirtualHosts Apache"
else
    fail "Pas de gestion VirtualHost detectee"
fi

if grep -qi "SSLEngine\|ssl\|443\|certificat\|openssl" "$SCRIPT" 2>/dev/null; then
    ok "Le script gere SSL/HTTPS"
else
    fail "Pas de gestion SSL detectee"
fi

if grep -qi "a2ensite\|a2enmod" "$SCRIPT" 2>/dev/null; then
    ok "Le script active les sites (a2ensite)"
else
    warn "a2ensite non detecte"
fi

if grep -qi "systemctl.*reload.*apache\|systemctl.*restart.*apache\|apache2ctl" "$SCRIPT" 2>/dev/null; then
    ok "Le script redemarre/recharge Apache"
else
    warn "Pas de redemarrage Apache detecte"
fi

# =============================================================
# 9.1.2 Le script gere DNS Bind9 ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1.2 Zone DNS Bind9${NC}"

if grep -qi "named.conf\|bind9\|zone\|db\." "$SCRIPT" 2>/dev/null; then
    ok "Le script gere la zone DNS"
else
    fail "Pas de gestion DNS detectee"
fi

if grep -qi "SOA\|NS.*IN\|enregistrement" "$SCRIPT" 2>/dev/null; then
    ok "Le script cree les enregistrements DNS (SOA/NS/A/MX)"
else
    if grep -qi "zone\|named" "$SCRIPT" 2>/dev/null; then
        warn "Zone DNS detectee mais enregistrements SOA/NS pas clairs"
    else
        fail "Pas d'enregistrements DNS detectes"
    fi
fi

if grep -qi "named-checkzone\|named-checkconf" "$SCRIPT" 2>/dev/null; then
    ok "Le script verifie la syntaxe DNS"
else
    warn "Pas de verification syntaxe DNS (named-checkzone)"
fi

if grep -qi "systemctl.*restart.*named\|systemctl.*restart.*bind\|systemctl.*reload.*bind" "$SCRIPT" 2>/dev/null; then
    ok "Le script redemarre Bind9"
else
    warn "Pas de redemarrage Bind9 detecte"
fi

# =============================================================
# 9.1.3 Le script gere les boites mail ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1.3 Boite mail${NC}"

if grep -qi "postfix\|mydestination\|postconf\|aliases\|mail" "$SCRIPT" 2>/dev/null; then
    ok "Le script gere la configuration mail"
else
    fail "Pas de gestion mail detectee"
fi

if grep -qi "mydestination" "$SCRIPT" 2>/dev/null; then
    ok "Le script met a jour mydestination (Postfix)"
else
    warn "mydestination non detecte"
fi

if grep -qi "aliases\|newaliases" "$SCRIPT" 2>/dev/null; then
    ok "Le script gere les alias mail"
else
    warn "Alias mail non detectes"
fi

if grep -qi "systemctl.*restart.*postfix\|systemctl.*reload.*postfix" "$SCRIPT" 2>/dev/null; then
    ok "Le script redemarre Postfix"
else
    warn "Pas de redemarrage Postfix detecte"
fi

# =============================================================
# 9.1.4 Le script gere la base de donnees ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1.4 Base de donnees${NC}"

if grep -qi "psql\|CREATE DATABASE\|postgresql\|pg_" "$SCRIPT" 2>/dev/null; then
    ok "Le script gere PostgreSQL"
else
    if grep -qi "mysql\|CREATE DATABASE\|mariadb" "$SCRIPT" 2>/dev/null; then
        ok "Le script gere MySQL/MariaDB"
    else
        warn "Pas de gestion base de donnees detectee (optionnel)"
    fi
fi

if grep -qi "CREATE DATABASE\|createdb" "$SCRIPT" 2>/dev/null; then
    ok "Le script cree une base de donnees"
else
    warn "Creation de BDD non detectee"
fi

# =============================================================
# 9.1.5 Le script gere SFTP ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1.5 Configuration SFTP${NC}"

if grep -qi "sftp\|ssh\|mkdir.*www\|chown\|useradd\|adduser" "$SCRIPT" 2>/dev/null; then
    ok "Le script gere les repertoires/utilisateurs (SFTP)"
else
    warn "Pas de gestion SFTP explicite detectee"
fi

if grep -qi "mkdir\|DocumentRoot\|www" "$SCRIPT" 2>/dev/null; then
    ok "Le script cree le repertoire web"
else
    warn "Creation de repertoire web non detectee"
fi

# =============================================================
# 9.1 Syntaxe du script
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1 Syntaxe du script${NC}"

SYNTAX_CHECK=$(bash -n "$SCRIPT" 2>&1)
if [ -z "$SYNTAX_CHECK" ]; then
    ok "Syntaxe bash OK"
else
    fail "Erreur de syntaxe bash"
    info "$SYNTAX_CHECK"
fi

# Le script prend un parametre (nom de domaine) ?
if grep -qi "\$1\|domaine\|domain.*=\|read.*domain" "$SCRIPT" 2>/dev/null; then
    ok "Le script prend un parametre (nom de domaine)"
else
    warn "Pas de parametre detecte (le domaine est peut-etre en dur)"
fi

# =============================================================
# 9.1 Resume du contenu du script
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.1 Resume du script${NC}"
info "Fichier : $SCRIPT"
info "Lignes  : $(wc -l < "$SCRIPT")"
info ""
info "Fonctionnalites detectees :"

FEATURES=""
grep -qi "VirtualHost\|a2ensite" "$SCRIPT" 2>/dev/null && FEATURES="$FEATURES Apache"
grep -qi "SSL\|443\|openssl" "$SCRIPT" 2>/dev/null && FEATURES="$FEATURES SSL"
grep -qi "named\|bind\|zone" "$SCRIPT" 2>/dev/null && FEATURES="$FEATURES DNS"
grep -qi "postfix\|mydestination\|mail" "$SCRIPT" 2>/dev/null && FEATURES="$FEATURES Mail"
grep -qi "psql\|mysql\|CREATE DATABASE" "$SCRIPT" 2>/dev/null && FEATURES="$FEATURES BDD"
grep -qi "sftp\|ssh\|mkdir.*www" "$SCRIPT" 2>/dev/null && FEATURES="$FEATURES SFTP"

for feat in $FEATURES; do
    info "  [x] $feat"
done

MISSING=""
grep -qi "VirtualHost\|a2ensite" "$SCRIPT" 2>/dev/null || MISSING="$MISSING Apache"
grep -qi "SSL\|443\|openssl" "$SCRIPT" 2>/dev/null || MISSING="$MISSING SSL"
grep -qi "named\|bind\|zone" "$SCRIPT" 2>/dev/null || MISSING="$MISSING DNS"
grep -qi "postfix\|mydestination\|mail" "$SCRIPT" 2>/dev/null || MISSING="$MISSING Mail"

for feat in $MISSING; do
    info "  [ ] $feat (manquant)"
done

# =============================================================
# 9.2 Test avec un domaine fictif (simulation sans execution)
# =============================================================
echo ""
echo -e "${BOLD}>>> 9.2 Verification test avec un nouveau domaine${NC}"

# Chercher si un domaine de test a ete ajoute (autre que les 3 principaux)
EXTRA_SITES=$(ls /etc/apache2/sites-available/*.conf 2>/dev/null | grep -v "exemple\|000-default\|default-ssl" | head -5)
if [ -n "$EXTRA_SITES" ]; then
    ok "Domaine(s) supplementaire(s) detecte(s) :"
    for site in $EXTRA_SITES; do
        info "  $(basename $site)"
    done
else
    info "Aucun domaine supplementaire detecte (script pas encore teste)"
fi

EXTRA_ZONES=$(ls /etc/bind/db.* 2>/dev/null | grep -v "exemple\|local\|127\|0\|255\|empty\|root" | head -5)
if [ -n "$EXTRA_ZONES" ]; then
    ok "Zone(s) DNS supplementaire(s) :"
    for zone in $EXTRA_ZONES; do
        info "  $(basename $zone)"
    done
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 9 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 9 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e " ${YELLOW}Note : Phase 9 est un BONUS${NC}"
echo -e "==========================================${NC}"

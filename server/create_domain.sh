#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# create_domain.sh - SAE S203 - Wrapper pour ajouter_domaine.py
# Verifie l'environnement, installe les dependances si besoin,
# puis lance le script Python d'automatisation
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit etre execute en root (sudo ./create_domain.sh monsite.org)"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/ajouter_domaine.py"

PASS=0
FAIL=0
INSTALLED=0

ok()      { echo -e "  ${GREEN}[OK]${NC}      $1"; ((PASS++)); }
fail()    { echo -e "  ${RED}[FAIL]${NC}    $1"; ((FAIL++)); }
fix()     { echo -e "  ${YELLOW}[INSTALL]${NC} $1"; ((INSTALLED++)); }
info()    { echo -e "  ${CYAN}[INFO]${NC}    $1"; }

install_if_missing() {
    local pkg="$1"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg"
    else
        fix "$pkg..."
        apt-get install -y "$pkg" >/dev/null 2>&1
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            ok "$pkg installe"
        else
            fail "$pkg echec installation"
        fi
    fi
}

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Ajout de domaine"
echo -e "==========================================${NC}"

# =============================================================
# 1. VERIFIER PYTHON3
# =============================================================
echo ""
echo -e "${BOLD}>>> 1. Python3${NC}"

if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    ok "python3 disponible ($PY_VER)"
else
    fix "Installation de python3..."
    apt-get update -qq
    apt-get install -y python3 >/dev/null 2>&1
    if command -v python3 &>/dev/null; then
        ok "python3 installe"
    else
        fail "python3 impossible a installer"
        exit 1
    fi
fi

# =============================================================
# 2. VERIFIER LE SCRIPT PYTHON
# =============================================================
echo ""
echo -e "${BOLD}>>> 2. Script ajouter_domaine.py${NC}"

if [ -f "$PYTHON_SCRIPT" ]; then
    ok "Trouve : $PYTHON_SCRIPT"
else
    # Chercher ailleurs
    for path in \
        ~/ajouter_domaine.py \
        /root/ajouter_domaine.py \
        ./ajouter_domaine.py; do
        if [ -f "$path" ]; then
            PYTHON_SCRIPT="$path"
            break
        fi
    done

    if [ -f "$PYTHON_SCRIPT" ]; then
        ok "Trouve : $PYTHON_SCRIPT"
    else
        fail "ajouter_domaine.py introuvable"
        info "Placez ajouter_domaine.py dans le meme repertoire que ce script"
        exit 1
    fi
fi

# Verifier la syntaxe Python
SYNTAX=$(python3 -c "import py_compile; py_compile.compile('$PYTHON_SCRIPT', doraise=True)" 2>&1)
if [ $? -eq 0 ]; then
    ok "Syntaxe Python OK"
else
    fail "Erreur syntaxe Python : $SYNTAX"
    exit 1
fi

# =============================================================
# 3. VERIFIER LES SERVICES REQUIS
# =============================================================
echo ""
echo -e "${BOLD}>>> 3. Services requis${NC}"

# --- Apache2 ---
install_if_missing apache2

if ! sudo a2query -m ssl &>/dev/null; then
    fix "Activation module SSL..."
    a2enmod ssl >/dev/null 2>&1
    ok "Module SSL active"
else
    ok "Module SSL"
fi

if ! sudo a2query -m rewrite &>/dev/null; then
    fix "Activation module rewrite..."
    a2enmod rewrite >/dev/null 2>&1
    ok "Module rewrite active"
else
    ok "Module rewrite"
fi

if ! systemctl is-active --quiet apache2; then
    fix "Demarrage apache2..."
    systemctl start apache2
fi

# --- Bind9 ---
install_if_missing bind9
install_if_missing bind9utils
install_if_missing dnsutils

BIND_SVC="named"
if ! systemctl is-active --quiet named 2>/dev/null; then
    BIND_SVC="bind9"
fi
if ! systemctl is-active --quiet "$BIND_SVC" 2>/dev/null; then
    fix "Demarrage $BIND_SVC..."
    systemctl start "$BIND_SVC" 2>/dev/null
fi

# --- PostgreSQL ---
install_if_missing postgresql
install_if_missing postgresql-contrib

if ! systemctl is-active --quiet postgresql; then
    fix "Demarrage postgresql..."
    systemctl start postgresql
fi

# --- PHP ---
install_if_missing php
install_if_missing libapache2-mod-php
install_if_missing php-pgsql

# --- Postfix ---
if ! dpkg -l postfix 2>/dev/null | grep -q "^ii"; then
    echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
    echo "postfix postfix/mailname string exemple.com" | debconf-set-selections
fi
install_if_missing postfix

if ! systemctl is-active --quiet postfix; then
    fix "Demarrage postfix..."
    systemctl start postfix
fi

# --- Dovecot ---
install_if_missing dovecot-core
install_if_missing dovecot-imapd

if ! systemctl is-active --quiet dovecot; then
    fix "Demarrage dovecot..."
    systemctl start dovecot
fi

# --- OpenSSH ---
install_if_missing openssh-server

if ! systemctl is-active --quiet ssh; then
    fix "Demarrage ssh..."
    systemctl start ssh
fi

# --- OpenSSL ---
install_if_missing openssl

# =============================================================
# 4. VERIFIER LE CERTIFICAT SSL
# =============================================================
echo ""
echo -e "${BOLD}>>> 4. Certificat SSL${NC}"

if [ -f /etc/ssl/certs/exemple.crt ] && [ -f /etc/ssl/private/exemple.key ]; then
    if openssl x509 -checkend 0 -noout -in /etc/ssl/certs/exemple.crt 2>/dev/null; then
        ok "Certificat SSL valide"
    else
        fix "Certificat expire, regeneration..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/exemple.key \
            -out /etc/ssl/certs/exemple.crt \
            -subj "/C=FR/ST=PACA/L=Nice/O=IUT/CN=exemple.com" 2>/dev/null
        ok "Certificat regenere"
    fi
else
    fix "Creation du certificat SSL..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/exemple.key \
        -out /etc/ssl/certs/exemple.crt \
        -subj "/C=FR/ST=PACA/L=Nice/O=IUT/CN=exemple.com" 2>/dev/null
    ok "Certificat cree"
fi

# =============================================================
# 5. VERIFIER L'UTILISATEUR
# =============================================================
echo ""
echo -e "${BOLD}>>> 5. Utilisateur${NC}"

if id exemple &>/dev/null; then
    ok "Utilisateur 'exemple' existe"
else
    fix "Creation utilisateur 'exemple'..."
    mkdir -p /users/firms
    useradd -m -d /users/firms/exemple -s /bin/bash exemple
    echo "exemple:but1" | chpasswd
    ok "Utilisateur 'exemple' cree"
fi

if [ -d /users/firms/exemple/www ]; then
    ok "Repertoire /users/firms/exemple/www/ existe"
else
    fix "Creation repertoire www..."
    mkdir -p /users/firms/exemple/www
    chown -R exemple:exemple /users/firms/exemple
    ok "Repertoire cree"
fi

# =============================================================
# 6. VERIFIER LES PORTS
# =============================================================
echo ""
echo -e "${BOLD}>>> 6. Ports en ecoute${NC}"

for port_info in "22:SSH" "25:SMTP" "53:DNS" "80:HTTP" "143:IMAP" "443:HTTPS" "5432:PostgreSQL"; do
    port=$(echo "$port_info" | cut -d: -f1)
    svc=$(echo "$port_info" | cut -d: -f2)
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        ok "Port $port ($svc)"
    else
        fail "Port $port ($svc) PAS en ecoute"
    fi
done

# =============================================================
# RESUME ENVIRONNEMENT
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Environnement OK ($PASS verifications, $INSTALLED installations)${NC}"
else
    echo -e " ${RED}$FAIL problemes detectes${NC}"
    echo -e " Corrigez les erreurs ci-dessus avant de continuer"
    echo -e "==========================================${NC}"
    exit 1
fi
echo -e "==========================================${NC}"

# =============================================================
# 7. LANCER LE SCRIPT PYTHON
# =============================================================
echo ""
echo -e "${BOLD}>>> 7. Lancement de ajouter_domaine.py${NC}"
echo ""

# Passer tous les arguments au script Python
python3 "$PYTHON_SCRIPT" "$@"

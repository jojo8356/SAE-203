#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# install_client.sh - SAE S203 - Installation du PC Client
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./install_client.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SERVER_IP="10.0.2.15"
DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Installation du Client"
echo -e "==========================================${NC}"

# --- Mise à jour ---
echo ""
echo -e "${BOLD}>>> 1. Mise à jour du système${NC}"
apt-get update && apt-get upgrade -y

# --- Fonction d'installation ---
install_if_missing() {
    local pkg="$1"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo -e "  ${GREEN}[OK]${NC} $pkg"
    else
        echo -e "  ${YELLOW}[INSTALL]${NC} $pkg..."
        apt-get install -y "$pkg" >/dev/null 2>&1
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            echo -e "  ${GREEN}[OK]${NC} $pkg installé"
        else
            echo -e "  ${RED}[FAIL]${NC} $pkg"
        fi
    fi
}

# --- Navigateur web ---
echo ""
echo -e "${BOLD}>>> 2. Navigateur web (Firefox)${NC}"
install_if_missing firefox
install_if_missing firefox-locale-fr

# --- Client mail ---
echo ""
echo -e "${BOLD}>>> 3. Client mail (Thunderbird)${NC}"
install_if_missing thunderbird
install_if_missing thunderbird-locale-fr

# --- Client FTP/SFTP ---
echo ""
echo -e "${BOLD}>>> 4. Client FTP (FileZilla)${NC}"
install_if_missing filezilla

# --- Client SSH ---
echo ""
echo -e "${BOLD}>>> 5. Client SSH${NC}"
install_if_missing openssh-client

# --- Environnement Java (Eclipse) ---
echo ""
echo -e "${BOLD}>>> 6. Environnement Java (Eclipse)${NC}"
install_if_missing default-jdk
install_if_missing eclipse

# --- Compilateur assembleur (Code::Blocks + nasm) ---
echo ""
echo -e "${BOLD}>>> 7. Compilateur assembleur (Code::Blocks + nasm)${NC}"
install_if_missing codeblocks
install_if_missing nasm
install_if_missing gcc
install_if_missing build-essential

# --- Serveur LAMP ---
echo ""
echo -e "${BOLD}>>> 8. Serveur LAMP (Apache2, MySQL, PHP, phpMyAdmin)${NC}"
install_if_missing apache2
install_if_missing mariadb-server
install_if_missing php
install_if_missing libapache2-mod-php
install_if_missing php-mysql
install_if_missing phpmyadmin

# --- Suite bureautique (LibreOffice) ---
echo ""
echo -e "${BOLD}>>> 9. Suite bureautique (LibreOffice)${NC}"
install_if_missing libreoffice
install_if_missing libreoffice-l10n-fr

# --- Lecteur PDF ---
echo ""
echo -e "${BOLD}>>> 10. Lecteur PDF${NC}"
install_if_missing evince

# --- Outils DNS ---
echo ""
echo -e "${BOLD}>>> 11. Outils DNS${NC}"
install_if_missing dnsutils
install_if_missing bind9-host

# --- Outils réseau ---
echo ""
echo -e "${BOLD}>>> 12. Outils réseau${NC}"
install_if_missing curl
install_if_missing wget
install_if_missing net-tools
install_if_missing traceroute
install_if_missing iputils-ping

# --- Éditeurs ---
echo ""
echo -e "${BOLD}>>> 13. Éditeurs${NC}"
install_if_missing nano
install_if_missing vim

# --- Configuration /etc/hosts ---
echo ""
echo -e "${BOLD}>>> 14. Configuration /etc/hosts${NC}"

HOSTS_LINE="$SERVER_IP  www.$DOMAIN $DOMAIN www.$DOMAIN2 $DOMAIN2 www.$DOMAIN3 $DOMAIN3"

if grep -q "$DOMAIN" /etc/hosts 2>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} /etc/hosts déjà configuré"
else
    echo "$HOSTS_LINE" >> /etc/hosts
    echo -e "  ${YELLOW}[FIX]${NC} Ajouté dans /etc/hosts :"
    echo -e "  ${CYAN}$HOSTS_LINE${NC}"
fi

# --- Configuration DNS vers le serveur ---
echo ""
echo -e "${BOLD}>>> 15. Configuration DNS${NC}"

if grep -q "nameserver $SERVER_IP" /etc/resolv.conf 2>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} DNS pointe déjà vers $SERVER_IP"
else
    echo -e "  ${YELLOW}[INFO]${NC} Pour utiliser le DNS du serveur, exécutez :"
    echo -e "  ${CYAN}echo 'nameserver $SERVER_IP' | sudo tee /etc/resolv.conf${NC}"
fi

# --- Résumé ---
echo ""
echo -e "${BOLD}=========================================="
echo " Installation terminée !"
echo -e "==========================================${NC}"
echo ""
echo "  Logiciels installés :"
echo "    - Firefox          (navigateur web)"
echo "    - Thunderbird      (client mail)"
echo "    - FileZilla        (client FTP/SFTP)"
echo "    - OpenSSH client   (SSH)"
echo "    - Eclipse + JDK    (environnement Java)"
echo "    - Code::Blocks     (IDE C/C++)"
echo "    - nasm + gcc       (assembleur + compilateur)"
echo "    - Apache2 + MySQL  (serveur LAMP)"
echo "    - PHP + phpMyAdmin (LAMP)"
echo "    - LibreOffice      (suite bureautique)"
echo "    - Evince           (lecteur PDF)"
echo "    - dnsutils         (dig, nslookup)"
echo "    - curl, wget       (outils réseau)"
echo ""
echo -e "  ${BOLD}Comment tester :${NC}"
echo ""
echo "  Firefox :"
echo -e "    ${CYAN}https://www.$DOMAIN${NC}"
echo -e "    ${CYAN}https://www.$DOMAIN2${NC}"
echo -e "    ${CYAN}https://www.$DOMAIN3${NC}"
echo -e "    ${CYAN}http://www.$DOMAIN/phppgadmin${NC}"
echo ""
echo "  Thunderbird :"
echo -e "    IMAP : ${CYAN}$SERVER_IP:143${NC}"
echo -e "    SMTP : ${CYAN}$SERVER_IP:25${NC}"
echo -e "    Compte : ${CYAN}contact@$DOMAIN${NC} (mdp: but1)"
echo ""
echo "  FileZilla :"
echo -e "    ${CYAN}sftp://$SERVER_IP${NC} port ${CYAN}22${NC}"
echo -e "    User : ${CYAN}exemple${NC} / mdp : ${CYAN}but1${NC}"
echo ""
echo "  SSH :"
echo -e "    ${CYAN}ssh exemple@$SERVER_IP${NC}"
echo ""
echo "  DNS :"
echo -e "    ${CYAN}dig @$SERVER_IP www.$DOMAIN${NC}"
echo -e "    ${CYAN}nslookup www.$DOMAIN $SERVER_IP${NC}"
echo ""
echo -e "${BOLD}==========================================${NC}"

#!/bin/bash

# =============================================================
# start_server.sh - SAE S203 - Démarrage de tous les services
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./start_server.sh)"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
USER="exemple"
USER_HOME="/users/firms/exemple"
WWW_DIR="$USER_HOME/www"
DB_USER="exemple"
DB_PASS="but1"

SERVICES="apache2 postgresql named ssh postfix dovecot"

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Démarrage des services"
echo -e "==========================================${NC}"
echo ""

# --- Démarrage des services ---
for svc in $SERVICES; do
    if [ "$svc" = "named" ] && ! systemctl list-unit-files | grep -q "^named"; then
        svc="bind9"
    fi

    if systemctl is-active --quiet "$svc"; then
        echo -e "  ${GREEN}[ON]${NC}     $svc"
    else
        systemctl start "$svc" 2>/dev/null
        if systemctl is-active --quiet "$svc"; then
            echo -e "  ${YELLOW}[START]${NC}  $svc"
        else
            echo -e "  ${RED}[FAIL]${NC}   $svc"
        fi
    fi
done

# --- Récupération des IPs ---
SERVER_IP=$(hostname -I | awk '{print $1}')
GATEWAY=$(ip route | awk '/default/ {print $3}' | head -1)
DNS_RESOLV=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
ALL_IPS=$(hostname -I 2>/dev/null)

# --- Ports ---
echo ""
echo -e "${BOLD}--- Ports en écoute ---${NC}"
echo ""
printf "  %-6s %-15s %s\n" "PORT" "SERVICE" "STATUT"
printf "  %-6s %-15s %s\n" "----" "-------" "------"

check_port() {
    if ss -tlnp | grep -q ":${1} "; then
        printf "  ${GREEN}%-6s${NC} %-15s %s\n" "$1" "$2" "OK"
    else
        printf "  ${RED}%-6s${NC} %-15s %s\n" "$1" "$2" "DOWN"
    fi
}

check_port 22   "SSH/SFTP"
check_port 25   "SMTP"
check_port 53   "DNS"
check_port 80   "HTTP"
check_port 143  "IMAP"
check_port 443  "HTTPS"
check_port 5432 "PostgreSQL"

# --- Infos réseau ---
echo ""
echo -e "${BOLD}--- Informations réseau ---${NC}"
echo ""
echo -e "  Hostname       : ${CYAN}$HOSTNAME${NC}"
echo -e "  IP serveur     : ${CYAN}$SERVER_IP${NC}"
echo -e "  Toutes les IPs : ${CYAN}$ALL_IPS${NC}"
echo -e "  Passerelle     : ${CYAN}$GATEWAY${NC}"
echo -e "  DNS resolv.conf: ${CYAN}$DNS_RESOLV${NC}"

# --- Infos Apache ---
echo ""
echo -e "${BOLD}--- Apache / Sites web ---${NC}"
echo ""
echo -e "  Document Root  : ${CYAN}$WWW_DIR${NC}"
echo -e "  Certificat SSL : ${CYAN}/etc/ssl/certs/exemple.crt${NC}"
echo -e "  Clé privée SSL : ${CYAN}/etc/ssl/private/exemple.key${NC}"
echo ""
echo "  Sites HTTP :"
echo -e "    ${CYAN}http://www.$DOMAIN${NC}"
echo -e "    ${CYAN}http://www.$DOMAIN2${NC}"
echo -e "    ${CYAN}http://www.$DOMAIN3${NC}"
echo ""
echo "  Sites HTTPS :"
echo -e "    ${CYAN}https://www.$DOMAIN${NC}"
echo -e "    ${CYAN}https://www.$DOMAIN2${NC}"
echo -e "    ${CYAN}https://www.$DOMAIN3${NC}"
echo ""
echo "  PHP :"
echo -e "    ${CYAN}http://www.$DOMAIN/index.php${NC}"
PHP_VER=$(php -v 2>/dev/null | head -1 | awk '{print $2}')
[ -n "$PHP_VER" ] && echo -e "    Version : ${CYAN}$PHP_VER${NC}"


# --- Infos DNS ---
echo ""
echo -e "${BOLD}--- DNS (Bind9) ---${NC}"
echo ""
echo -e "  Serveur DNS    : ${CYAN}$SERVER_IP:53${NC}"
echo "  Zones configurées :"
for domain in $DOMAIN $DOMAIN2 $DOMAIN3; do
    if [ -f "/etc/bind/db.$domain" ]; then
        echo -e "    ${GREEN}[OK]${NC} $domain  ->  ${CYAN}/etc/bind/db.$domain${NC}"
    else
        echo -e "    ${RED}[--]${NC} $domain  (fichier de zone manquant)"
    fi
done
echo ""
echo "  Test de résolution :"
for domain in $DOMAIN $DOMAIN2 $DOMAIN3; do
    RESULT=$(dig @127.0.0.1 www.$domain +short 2>/dev/null)
    if [ -n "$RESULT" ]; then
        echo -e "    www.$domain -> ${CYAN}$RESULT${NC}"
    else
        echo -e "    www.$domain -> ${RED}pas de réponse${NC}"
    fi
done

# --- Infos Mail ---
echo ""
echo -e "${BOLD}--- Mail (Postfix + Dovecot) ---${NC}"
echo ""
echo -e "  SMTP (Postfix)  : ${CYAN}$SERVER_IP:25${NC}"
echo -e "  IMAP (Dovecot)  : ${CYAN}$SERVER_IP:143${NC}"
echo ""
echo "  Boîtes mail :"
echo -e "    ${CYAN}contact@$DOMAIN${NC}"
echo -e "    ${CYAN}contact@$DOMAIN2${NC}"
echo -e "    ${CYAN}contact@$DOMAIN3${NC}"
echo ""
echo "  Config Thunderbird (client) :"
echo -e "    Serveur entrant  : IMAP - ${CYAN}$SERVER_IP${NC} - port ${CYAN}143${NC}"
echo -e "    Serveur sortant  : SMTP - ${CYAN}$SERVER_IP${NC} - port ${CYAN}25${NC}"
echo -e "    Utilisateur      : ${CYAN}$USER${NC}"
echo -e "    Mot de passe     : ${CYAN}$DB_PASS${NC}"

# --- Infos SSH/SFTP ---
echo ""
echo -e "${BOLD}--- SSH / SFTP ---${NC}"
echo ""
echo -e "  Connexion SSH  : ${CYAN}ssh $USER@$SERVER_IP${NC}"
echo -e "  Connexion SFTP : ${CYAN}sftp $USER@$SERVER_IP${NC}"
echo ""
echo "  Config FileZilla (client) :"
echo -e "    Hôte         : ${CYAN}sftp://$SERVER_IP${NC}"
echo -e "    Port         : ${CYAN}22${NC}"
echo -e "    Utilisateur  : ${CYAN}$USER${NC}"
echo -e "    Mot de passe : ${CYAN}$DB_PASS${NC}"

# --- Utilisateur système ---
echo ""
echo -e "${BOLD}--- Utilisateur système ---${NC}"
echo ""
echo -e "  Login          : ${CYAN}$USER${NC}"
echo -e "  Mot de passe   : ${CYAN}$DB_PASS${NC}"
echo -e "  Home           : ${CYAN}$USER_HOME${NC}"
echo -e "  Répertoire web : ${CYAN}$WWW_DIR${NC}"
echo -e "  Maildir        : ${CYAN}$USER_HOME/Maildir/${NC}"

# --- PostgreSQL ---
echo ""
echo -e "${BOLD}--- PostgreSQL ---${NC}"
echo ""
echo -e "  Hôte           : ${CYAN}127.0.0.1:5432${NC}"
echo -e "  Base           : ${CYAN}carte_grise${NC}"
echo -e "  Utilisateur    : ${CYAN}$DB_USER${NC}"
echo -e "  Mot de passe   : ${CYAN}$DB_PASS${NC}"
echo -e "  Connexion CLI  : ${CYAN}psql -U $DB_USER -d carte_grise${NC}"
echo ""
echo "  phpPgAdmin :"
echo -e "    ${CYAN}http://www.$DOMAIN/phppgadmin${NC}"
PG_VER=$(psql --version 2>/dev/null | awk '{print $3}')
[ -n "$PG_VER" ] && echo -e "    Version : ${CYAN}$PG_VER${NC}"
echo ""
echo "  Tables :"
su - postgres -c "psql -d carte_grise -t -c \"SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;\"" 2>/dev/null | while read table; do
    table=$(echo "$table" | xargs)
    [ -n "$table" ] && echo -e "    - ${CYAN}$table${NC}"
done

# --- Uptime & Résumé ---
echo ""
echo -e "${BOLD}--- Système ---${NC}"
echo ""
UPTIME=$(uptime -p 2>/dev/null)
LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
MEM=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
DISK=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
echo -e "  Uptime         : ${CYAN}$UPTIME${NC}"
echo -e "  Load           : ${CYAN}$LOAD${NC}"
echo -e "  RAM            : ${CYAN}$MEM${NC}"
echo -e "  Disque /       : ${CYAN}$DISK${NC}"

echo ""
echo -e "${BOLD}==========================================${NC}"

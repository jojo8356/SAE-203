#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# definitively_IP_CLIENT.sh - Configuration IP permanente
# Interface reseau interne "sae203" (enp0s3)
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit etre execute en root (sudo ./definitively_IP_CLIENT.sh)"
    exit 1
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CLIENT_IP="192.168.100.2"
SERVER_IP="192.168.100.1"
INTERFACE="enp0s3"
NETPLAN_FILE="/etc/netplan/01-internal.yaml"

DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"

echo ""
echo -e "${BOLD}=========================================="
echo " Configuration IP permanente - CLIENT"
echo -e "==========================================${NC}"

# 1. Configurer netplan
echo ""
echo -e "${BOLD}>>> 1. Configuration netplan${NC}"

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      addresses: [$CLIENT_IP/24]
EOF

chmod 600 "$NETPLAN_FILE"
echo -e "  ${GREEN}[OK]${NC} $NETPLAN_FILE cree"

# 2. Appliquer
echo ""
echo -e "${BOLD}>>> 2. Application de la configuration${NC}"
netplan apply 2>/dev/null
echo -e "  ${GREEN}[OK]${NC} netplan apply"

# 3. Attribuer l'IP immediatement si pas encore fait
if ! ip addr show "$INTERFACE" | grep -q "$CLIENT_IP"; then
    ip addr add "$CLIENT_IP/24" dev "$INTERFACE" 2>/dev/null
    ip link set "$INTERFACE" up
fi

# 4. Configurer /etc/hosts
echo ""
echo -e "${BOLD}>>> 3. Configuration /etc/hosts${NC}"

HOSTS_LINE="$SERVER_IP  www.$DOMAIN www.$DOMAIN2 www.$DOMAIN3"

sed -i '/exemple/d' /etc/hosts 2>/dev/null
sed -i '/192\.168\.100/d' /etc/hosts 2>/dev/null
echo "$HOSTS_LINE" >> /etc/hosts
echo -e "  ${GREEN}[OK]${NC} /etc/hosts mis a jour"

# 5. Verification
echo ""
echo -e "${BOLD}>>> 4. Verification${NC}"

CURRENT_IP=$(ip addr show "$INTERFACE" | grep "inet " | awk '{print $2}')
if [ -n "$CURRENT_IP" ]; then
    echo -e "  ${GREEN}[OK]${NC} $INTERFACE : ${CYAN}$CURRENT_IP${NC}"
else
    echo -e "  [FAIL] Pas d'IP sur $INTERFACE"
fi

if ping -c 1 -W 2 "$SERVER_IP" &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} Ping serveur $SERVER_IP"
else
    echo -e "  [FAIL] Ping serveur $SERVER_IP echoue"
fi

grep "$DOMAIN" /etc/hosts &>/dev/null && echo -e "  ${GREEN}[OK]${NC} /etc/hosts contient les domaines"

# 6. Resume
echo ""
echo -e "${BOLD}=========================================="
echo -e " CLIENT configure :${NC}"
echo -e "  Interface : ${CYAN}$INTERFACE${NC}"
echo -e "  IP Client : ${CYAN}$CLIENT_IP/24${NC}"
echo -e "  IP Serveur: ${CYAN}$SERVER_IP${NC}"
echo -e "  Fichier   : ${CYAN}$NETPLAN_FILE${NC}"
echo ""
echo -e "  /etc/hosts :"
echo -e "    ${CYAN}$HOSTS_LINE${NC}"
echo ""
echo -e "  Cette IP est permanente (survit au reboot)."
echo -e "${BOLD}==========================================${NC}"

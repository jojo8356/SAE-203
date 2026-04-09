#!/bin/bash

# =============================================================
# definitively_IP_SERVER.sh - Configuration IP permanente
# Interface reseau interne "sae203" (enp0s3)
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit etre execute en root (sudo ./definitively_IP_SERVER.sh)"
    exit 1
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SERVER_IP="192.168.100.1"
INTERFACE="enp0s3"
NETPLAN_FILE="/etc/netplan/01-internal.yaml"

echo ""
echo -e "${BOLD}=========================================="
echo " Configuration IP permanente - SERVEUR"
echo -e "==========================================${NC}"

# 1. Configurer netplan
echo ""
echo -e "${BOLD}>>> 1. Configuration netplan${NC}"

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      addresses: [$SERVER_IP/24]
EOF

chmod 600 "$NETPLAN_FILE"
echo -e "  ${GREEN}[OK]${NC} $NETPLAN_FILE cree"

# 2. Appliquer
echo ""
echo -e "${BOLD}>>> 2. Application de la configuration${NC}"
netplan apply 2>/dev/null
echo -e "  ${GREEN}[OK]${NC} netplan apply"

# 3. Attribuer l'IP immediatement si pas encore fait
if ! ip addr show "$INTERFACE" | grep -q "$SERVER_IP"; then
    ip addr add "$SERVER_IP/24" dev "$INTERFACE" 2>/dev/null
    ip link set "$INTERFACE" up
fi

# 4. Verification
echo ""
echo -e "${BOLD}>>> 3. Verification${NC}"
CURRENT_IP=$(ip addr show "$INTERFACE" | grep "inet " | awk '{print $2}')
if [ -n "$CURRENT_IP" ]; then
    echo -e "  ${GREEN}[OK]${NC} $INTERFACE : ${CYAN}$CURRENT_IP${NC}"
else
    echo -e "  [FAIL] Pas d'IP sur $INTERFACE"
fi

# 5. Resume
echo ""
echo -e "${BOLD}=========================================="
echo -e " SERVEUR configure :${NC}"
echo -e "  Interface : ${CYAN}$INTERFACE${NC}"
echo -e "  IP        : ${CYAN}$SERVER_IP/24${NC}"
echo -e "  Fichier   : ${CYAN}$NETPLAN_FILE${NC}"
echo ""
echo -e "  Cette IP est permanente (survit au reboot)."
echo -e "${BOLD}==========================================${NC}"

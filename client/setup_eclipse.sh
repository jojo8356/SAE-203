#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# setup_eclipse.sh - Installation d'Eclipse IDE
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./setup_eclipse.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ECLIPSE_DIR="/opt/eclipse"
ECLIPSE_TAR="/tmp/eclipse.tar.gz"
ECLIPSE_URL="https://www.eclipse.org/downloads/download.php?file=/technology/epp/downloads/release/2024-12/R/eclipse-java-2024-12-R-linux-gtk-x86_64.tar.gz&r=1"

echo ""
echo -e "${BOLD}=========================================="
echo " Installation d'Eclipse IDE"
echo -e "==========================================${NC}"

# --- 1. Vérifier si déjà installé ---
if [ -f "$ECLIPSE_DIR/eclipse" ]; then
    echo -e "  ${GREEN}[OK]${NC} Eclipse déjà installé dans $ECLIPSE_DIR"
    echo -e "  Lancez avec : ${CYAN}eclipse${NC}"
    exit 0
fi

# --- 2. Installer Java (prérequis) ---
echo ""
echo -e "${BOLD}>>> 1. Installation de Java${NC}"
if dpkg -l default-jdk 2>/dev/null | grep -q "^ii"; then
    echo -e "  ${GREEN}[OK]${NC} default-jdk"
else
    echo -e "  ${YELLOW}[INSTALL]${NC} default-jdk..."
    apt-get update -qq
    apt-get install -y default-jdk >/dev/null 2>&1
fi

JAVA_VER=$(java -version 2>&1 | head -1)
echo -e "  ${CYAN}$JAVA_VER${NC}"

# --- 3. Télécharger Eclipse ---
echo ""
echo -e "${BOLD}>>> 2. Téléchargement d'Eclipse${NC}"

if [ -f "$ECLIPSE_TAR" ]; then
    echo -e "  ${GREEN}[OK]${NC} Archive déjà téléchargée"
else
    echo -e "  ${YELLOW}[DOWNLOAD]${NC} Téléchargement en cours..."
    wget -q --show-progress -O "$ECLIPSE_TAR" "$ECLIPSE_URL"
    if [ $? -ne 0 ]; then
        echo -e "  ${RED}[FAIL]${NC} Échec du téléchargement"
        echo -e "  ${YELLOW}[INFO]${NC} Téléchargement via miroir alternatif..."
        wget -q --show-progress -O "$ECLIPSE_TAR" "https://mirror.kakao.com/eclipse/technology/epp/downloads/release/2024-12/R/eclipse-java-2024-12-R-linux-gtk-x86_64.tar.gz"
        if [ $? -ne 0 ]; then
            echo -e "  ${RED}[FAIL]${NC} Impossible de télécharger Eclipse"
            echo ""
            echo "  Téléchargez manuellement depuis :"
            echo -e "  ${CYAN}https://www.eclipse.org/downloads/packages/${NC}"
            echo "  Puis placez le .tar.gz dans /tmp/eclipse.tar.gz et relancez ce script."
            exit 1
        fi
    fi
fi

# --- 4. Extraire ---
echo ""
echo -e "${BOLD}>>> 3. Extraction${NC}"
tar -xzf "$ECLIPSE_TAR" -C /opt/
if [ -d "$ECLIPSE_DIR" ]; then
    echo -e "  ${GREEN}[OK]${NC} Extrait dans $ECLIPSE_DIR"
else
    echo -e "  ${RED}[FAIL]${NC} Extraction échouée"
    exit 1
fi

# --- 5. Créer le lanceur ---
echo ""
echo -e "${BOLD}>>> 4. Création du raccourci${NC}"

# Lien symbolique dans /usr/local/bin
ln -sf "$ECLIPSE_DIR/eclipse" /usr/local/bin/eclipse
echo -e "  ${GREEN}[OK]${NC} Commande 'eclipse' disponible"

# Raccourci bureau (.desktop)
cat > /usr/share/applications/eclipse.desktop <<EOF
[Desktop Entry]
Name=Eclipse IDE
Comment=Eclipse IDE for Java Developers
Exec=$ECLIPSE_DIR/eclipse
Icon=$ECLIPSE_DIR/icon.xpm
Terminal=false
Type=Application
Categories=Development;IDE;Java;
EOF
echo -e "  ${GREEN}[OK]${NC} Raccourci ajouté au menu Applications"

# --- 6. Nettoyage ---
rm -f "$ECLIPSE_TAR"
echo -e "  ${GREEN}[OK]${NC} Archive supprimée"

# --- Résumé ---
echo ""
echo -e "${BOLD}=========================================="
echo " Eclipse installé !"
echo -e "==========================================${NC}"
echo ""
echo -e "  Emplacement : ${CYAN}$ECLIPSE_DIR${NC}"
echo -e "  Commande    : ${CYAN}eclipse${NC}"
echo -e "  Java        : ${CYAN}$JAVA_VER${NC}"
echo ""
echo -e "${BOLD}==========================================${NC}"

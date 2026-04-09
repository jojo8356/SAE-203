#!/bin/bash

# =============================================================
# demonstration.sh - SAE S203 - Menu de demonstration
# Script interactif pour la demo devant le jury
# Fonctionne sur le SERVEUR et le CLIENT
# =============================================================

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Detection automatique : serveur ou client ?
if systemctl is-active --quiet apache2 2>/dev/null && [ -d /users/firms/exemple/www ]; then
    ROLE="SERVEUR"
else
    ROLE="CLIENT"
fi

DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
SERVER_IP="192.168.100.1"
USER="exemple"
DB_NAME="carte_grise"
DB_USER="exemple"
DB_PASS="but1"
WWW_DIR="/users/firms/exemple/www"

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

pause() {
    echo ""
    echo -e "${DIM}Appuyez sur Entree pour continuer...${NC}"
    read
}

header() {
    clear
    echo -e "${BOLD}=========================================="
    echo " SAE S203 - Demonstration [$ROLE]"
    echo -e "==========================================${NC}"
    echo ""
}

section() {
    echo ""
    echo -e "${BOLD}------------------------------------------"
    echo " $1"
    echo -e "------------------------------------------${NC}"
    echo ""
}

# =============================================================
# MENU PRINCIPAL
# =============================================================

show_menu() {
    header
    echo -e " ${BOLD}VOIR${NC}"
    echo -e "  ${CYAN}1${NC}  - Dashboard (vue d'ensemble)"
    echo -e "  ${CYAN}2${NC}  - Informations reseau"
    echo -e "  ${CYAN}3${NC}  - Services et ports"
    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "  ${CYAN}4${NC}  - VirtualHosts Apache"
        echo -e "  ${CYAN}5${NC}  - Certificat SSL (local)"
        echo -e "  ${CYAN}6${NC}  - Fichiers de zone DNS"
        echo -e "  ${CYAN}7${NC}  - Tables et donnees (BDD)"
        echo -e "  ${CYAN}8${NC}  - Structure des tables"
        echo -e "  ${CYAN}9${NC}  - Fichiers PHP deployes"
        echo -e "  ${CYAN}10${NC} - Mails recus (Maildir)"
        echo -e "  ${CYAN}11${NC} - Logs mail"
        echo -e "  ${CYAN}12${NC} - Cron configure"
        echo -e "  ${CYAN}13${NC} - Rappels envoyes"
        echo -e "  ${CYAN}14${NC} - Log cron"
        echo -e "  ${CYAN}16${NC} - Executer une requete SQL"
    else
        echo -e "  ${CYAN}5${NC}  - Certificat SSL (distant)"
    fi
    echo -e "  ${CYAN}15${NC} - Config FileZilla"
    echo -e "  ${CYAN}17${NC} - Ouvrir dans le navigateur"
    echo ""
    echo -e " ${BOLD}TESTS${NC}"
    echo -e "  ${CYAN}20${NC} - Test rapide (essentiel)"
    echo -e "  ${CYAN}21${NC} - Test COMPLET (toutes les phases)"
    echo -e "  ${CYAN}22${NC} - Tester HTTP (tous les domaines)"
    echo -e "  ${CYAN}23${NC} - Tester HTTPS (tous les domaines)"
    echo -e "  ${CYAN}24${NC} - Tester DNS (dig)"
    echo -e "  ${CYAN}25${NC} - Tester DNS (nslookup)"
    echo -e "  ${CYAN}26${NC} - Tester enregistrements MX"
    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "  ${CYAN}27${NC} - Verifier syntaxe DNS"
    fi
    echo -e "  ${CYAN}28${NC} - Tester phpPgAdmin"
    echo -e "  ${CYAN}29${NC} - Tester toutes les pages PHP"
    echo -e "  ${CYAN}30${NC} - Tester INSERT (ajout proprietaire)"
    echo -e "  ${CYAN}31${NC} - Tester SELECT (liste proprietaires)"
    echo -e "  ${CYAN}32${NC} - Tester SMTP (envoi)"
    echo -e "  ${CYAN}33${NC} - Tester IMAP (reception)"
    echo -e "  ${CYAN}34${NC} - Envoyer un mail de test"
    echo -e "  ${CYAN}35${NC} - Tester SSH/SFTP"
    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "  ${CYAN}36${NC} - Executer cron_mail.php"
    fi
    echo ""
    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e " ${BOLD}BONUS${NC}"
        echo -e "  ${CYAN}90${NC} - Ajouter un domaine"
        echo -e "  ${CYAN}91${NC} - Lister les domaines"
        echo -e "  ${CYAN}92${NC} - Supprimer un domaine"
        echo ""
    fi
    echo -e "  ${CYAN}0${NC}  - Quitter"
    echo ""
    echo -ne " ${BOLD}Choix : ${NC}"
}

# =============================================================
# 1 - DASHBOARD
# =============================================================

dashboard() {
    header
    section "Dashboard - Vue d'ensemble"

    # Systeme
    echo -e "${BOLD}Systeme :${NC}"
    info "Hostname : $(hostname)"
    info "IP       : $(hostname -I 2>/dev/null | awk '{print $1}')"
    info "Uptime   : $(uptime -p 2>/dev/null)"
    info "RAM      : $(free -h | awk '/Mem:/ {print $3 "/" $2}')"
    info "Disque   : $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    info "Role     : $ROLE"
    echo ""

    # Services
    echo -e "${BOLD}Services :${NC}"
    for svc in apache2 postgresql named bind9 postfix dovecot ssh; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc"
        else
            if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
                fail "$svc (inactif)"
            fi
        fi
    done
    echo ""

    # Ports
    echo -e "${BOLD}Ports :${NC}"
    for port_info in "22:SSH" "25:SMTP" "53:DNS" "80:HTTP" "143:IMAP" "443:HTTPS" "5432:PostgreSQL"; do
        port=$(echo "$port_info" | cut -d: -f1)
        svc=$(echo "$port_info" | cut -d: -f2)
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            ok "Port $port ($svc)"
        else
            fail "Port $port ($svc)"
        fi
    done

    pause
}

# =============================================================
# 2 - INFORMATIONS RESEAU
# =============================================================

network_info() {
    header
    section "Informations reseau"

    echo -e "${BOLD}Interfaces :${NC}"
    ip -br addr show 2>/dev/null
    echo ""

    echo -e "${BOLD}Passerelle :${NC}"
    ip route | grep default
    echo ""

    echo -e "${BOLD}DNS (resolv.conf) :${NC}"
    cat /etc/resolv.conf 2>/dev/null | grep -v "^#"
    echo ""

    echo -e "${BOLD}/etc/hosts :${NC}"
    cat /etc/hosts 2>/dev/null | grep -v "^#" | grep -v "^$"

    pause
}

# =============================================================
# 3 - SERVICES ET PORTS
# =============================================================

services_ports() {
    header
    section "Services et ports en ecoute"

    echo -e "${BOLD}Services systemd :${NC}"
    for svc in apache2 postgresql named bind9 postfix dovecot ssh cron; do
        STATUS=$(systemctl is-active "$svc" 2>/dev/null)
        ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null)
        if [ "$STATUS" = "active" ]; then
            echo -e "  ${GREEN}$svc${NC} : actif (demarrage: $ENABLED)"
        elif systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
            echo -e "  ${RED}$svc${NC} : $STATUS (demarrage: $ENABLED)"
        fi
    done
    echo ""

    echo -e "${BOLD}Ports TCP en ecoute :${NC}"
    ss -tlnp 2>/dev/null | head -20
    echo ""

    echo -e "${BOLD}Ports UDP en ecoute :${NC}"
    ss -ulnp 2>/dev/null | grep ":53 "

    pause
}

# =============================================================
# 10-14 - APACHE + HTTPS
# =============================================================

test_http() {
    header
    section "11.3.1 - Test HTTP sur tous les domaines"

    for domain in $ALL_DOMAINS; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$domain/" 2>/dev/null)
        if [ "$CODE" = "200" ]; then
            ok "http://www.$domain -> $CODE"
        else
            fail "http://www.$domain -> $CODE"
        fi
    done

    pause
}

test_https() {
    header
    section "11.3.1 - Test HTTPS sur tous les domaines"

    for domain in $ALL_DOMAINS; do
        CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://www.$domain/" 2>/dev/null)
        if [ "$CODE" = "200" ]; then
            ok "https://www.$domain -> $CODE"
        else
            fail "https://www.$domain -> $CODE"
        fi
    done

    echo ""
    echo -e "${BOLD}Contenu de la page :${NC}"
    curl -s --max-time 5 "http://www.$DOMAIN/" 2>/dev/null | head -10

    pause
}

show_vhosts() {
    header
    section "VirtualHosts Apache configures"

    echo -e "${BOLD}Sites actifs :${NC}"
    sudo a2query -s 2>/dev/null
    echo ""

    echo -e "${BOLD}Modules actifs (principaux) :${NC}"
    sudo a2query -m 2>/dev/null | grep -E "ssl|php|rewrite|userdir"
    echo ""

    echo -e "${BOLD}Fichiers de config :${NC}"
    ls -la /etc/apache2/sites-available/*.conf 2>/dev/null

    pause
}

show_ssl() {
    header
    section "Certificat SSL"

    if [ -f /etc/ssl/certs/exemple.crt ]; then
        echo -e "${BOLD}Certificat :${NC}"
        openssl x509 -in /etc/ssl/certs/exemple.crt -noout -subject -issuer -dates 2>/dev/null
    else
        echo -e "${BOLD}Certificat distant (via $SERVER_IP) :${NC}"
        echo | timeout 3 openssl s_client -connect "$SERVER_IP:443" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null
    fi

    pause
}

open_browser() {
    header
    section "Ouvrir dans le navigateur"

    echo " Quel domaine ?"
    echo -e "  1) ${CYAN}http://www.$DOMAIN${NC}"
    echo -e "  2) ${CYAN}https://www.$DOMAIN${NC}"
    echo -e "  3) ${CYAN}http://www.$DOMAIN/index.php${NC}"
    echo -e "  4) ${CYAN}http://www.$DOMAIN/phppgadmin${NC}"
    echo -e "  5) ${CYAN}http://www.$DOMAIN/mail.php${NC}"
    echo -ne " Choix : "
    read choice

    case $choice in
        1) URL="http://www.$DOMAIN" ;;
        2) URL="https://www.$DOMAIN" ;;
        3) URL="http://www.$DOMAIN/index.php" ;;
        4) URL="http://www.$DOMAIN/phppgadmin" ;;
        5) URL="http://www.$DOMAIN/mail.php" ;;
        *) return ;;
    esac

    if command -v firefox &>/dev/null; then
        firefox "$URL" &>/dev/null &
        info "Firefox ouvert sur $URL"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$URL" &>/dev/null &
        info "Navigateur ouvert sur $URL"
    else
        info "Ouvrez manuellement : $URL"
    fi

    pause
}

# =============================================================
# 20-24 - DNS
# =============================================================

test_dns_dig() {
    header
    section "11.3.2 - Resolution DNS (dig)"

    DNS_SERVER="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        DNS_SERVER="127.0.0.1"
    fi

    for domain in $ALL_DOMAINS; do
        echo -e "${BOLD}--- $domain ---${NC}"
        echo -ne "  A   www.$domain  : "
        dig @"$DNS_SERVER" "www.$domain" +short 2>/dev/null || echo "pas de reponse"
        echo -ne "  A   $domain      : "
        dig @"$DNS_SERVER" "$domain" +short 2>/dev/null || echo "pas de reponse"
        echo -ne "  MX  $domain      : "
        dig @"$DNS_SERVER" "$domain" MX +short 2>/dev/null || echo "pas de reponse"
        echo -ne "  NS  $domain      : "
        dig @"$DNS_SERVER" "$domain" NS +short 2>/dev/null || echo "pas de reponse"
        echo ""
    done

    pause
}

test_dns_nslookup() {
    header
    section "11.3.2 - Resolution DNS (nslookup)"

    DNS_SERVER="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        DNS_SERVER="127.0.0.1"
    fi

    for domain in $ALL_DOMAINS; do
        echo -e "${BOLD}--- www.$domain ---${NC}"
        nslookup "www.$domain" "$DNS_SERVER" 2>/dev/null
        echo ""
    done

    pause
}

show_zones() {
    header
    section "11.3.2 - Fichiers de zone DNS"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "${BOLD}named.conf.local :${NC}"
        cat /etc/bind/named.conf.local 2>/dev/null | grep -v "^//" | grep -v "^$"
        echo ""

        for domain in $ALL_DOMAINS; do
            echo -e "${BOLD}Zone $domain :${NC}"
            cat "/etc/bind/db.$domain" 2>/dev/null || echo "  Fichier non trouve"
            echo ""
        done
    else
        info "Les fichiers de zone sont sur le SERVEUR"
        info "Utilisez dig pour tester depuis le client"
    fi

    pause
}

test_mx() {
    header
    section "11.3.2 - Enregistrements MX"

    DNS_SERVER="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        DNS_SERVER="127.0.0.1"
    fi

    for domain in $ALL_DOMAINS; do
        MX=$(dig @"$DNS_SERVER" "$domain" MX +short 2>/dev/null)
        if [ -n "$MX" ]; then
            ok "$domain MX -> $MX"
        else
            fail "$domain MX -> pas de reponse"
        fi
    done

    pause
}

check_dns_syntax() {
    header
    section "11.3.2 - Verification syntaxe DNS"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "${BOLD}named-checkconf :${NC}"
        named-checkconf 2>&1 && ok "Syntaxe OK" || fail "Erreur"
        echo ""

        for domain in $ALL_DOMAINS; do
            zf="/etc/bind/db.$domain"
            if [ -f "$zf" ]; then
                echo -ne "named-checkzone $domain : "
                named-checkzone "$domain" "$zf" 2>&1 | tail -1
            fi
        done
    else
        info "Verification syntaxe disponible uniquement sur le SERVEUR"
    fi

    pause
}

# =============================================================
# 30-33 - BASE DE DONNEES
# =============================================================

show_tables() {
    header
    section "11.3.3 - Tables et donnees"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "${BOLD}Tables dans $DB_NAME :${NC}"
        sudo -u postgres psql -d "$DB_NAME" -c "\dt" 2>/dev/null
        echo ""

        for table in proprietaire vehicule rappel_envoye; do
            echo -e "${BOLD}--- $table ---${NC}"
            NB=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM $table;" 2>/dev/null)
            info "$NB enregistrement(s)"
            sudo -u postgres psql -d "$DB_NAME" -c "SELECT * FROM $table LIMIT 5;" 2>/dev/null
            echo ""
        done
    else
        info "Acces direct a la BDD uniquement sur le SERVEUR"
        info "Utilisez phpPgAdmin : http://www.$DOMAIN/phppgadmin"
    fi

    pause
}

test_phppgadmin() {
    header
    section "11.3.3 - phpPgAdmin"

    URL="http://www.$DOMAIN/phppgadmin/"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL" 2>/dev/null)
    if [ "$CODE" = "200" ] || [ "$CODE" = "301" ] || [ "$CODE" = "302" ]; then
        ok "phpPgAdmin accessible ($CODE)"
    else
        fail "phpPgAdmin inaccessible ($CODE)"
    fi

    info "URL : $URL"
    info "User: $DB_USER / $DB_PASS"

    pause
}

run_sql() {
    header
    section "11.3.3 - Executer une requete SQL"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e " Requetes predefinies :"
        echo -e "  1) SELECT * FROM proprietaire"
        echo -e "  2) SELECT * FROM vehicule"
        echo -e "  3) SELECT v.*, p.nom FROM vehicule v JOIN proprietaire p ON v.proprietaire_id=p.id"
        echo -e "  4) SELECT COUNT(*) FROM proprietaire"
        echo -e "  5) Vehicules avec CT dans 30 jours"
        echo -e "  6) Requete personnalisee"
        echo -ne " Choix : "
        read choice

        case $choice in
            1) SQL="SELECT * FROM proprietaire;" ;;
            2) SQL="SELECT * FROM vehicule;" ;;
            3) SQL="SELECT v.immatriculation, v.marque, v.modele, p.nom, p.prenom, p.email FROM vehicule v JOIN proprietaire p ON v.proprietaire_id=p.id;" ;;
            4) SQL="SELECT COUNT(*) as nb_proprietaires FROM proprietaire;" ;;
            5) SQL="SELECT v.immatriculation, v.marque, v.date_controle_technique, p.nom, p.email FROM vehicule v JOIN proprietaire p ON v.proprietaire_id=p.id WHERE v.date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days';" ;;
            6) echo -ne " SQL : "; read SQL ;;
            *) return ;;
        esac

        echo ""
        echo -e "${BOLD}Requete :${NC} $SQL"
        echo ""
        sudo -u postgres psql -d "$DB_NAME" -c "$SQL" 2>&1
    else
        info "Requetes SQL disponibles uniquement sur le SERVEUR"
    fi

    pause
}

show_table_structure() {
    header
    section "11.3.3 - Structure des tables"

    if [ "$ROLE" = "SERVEUR" ]; then
        for table in proprietaire vehicule rappel_envoye; do
            echo -e "${BOLD}--- $table ---${NC}"
            sudo -u postgres psql -d "$DB_NAME" -c "\d $table" 2>/dev/null
            echo ""
        done
    else
        info "Structure des tables disponible uniquement sur le SERVEUR"
    fi

    pause
}

# =============================================================
# 40-43 - APPLICATION PHP
# =============================================================

test_php_pages() {
    header
    section "11.3.4 - Test des pages PHP"

    PAGES="index.php proprietaires.php vehicules.php ajouter_proprietaire.php ajouter_vehicule.php modifier_proprietaire.php modifier_vehicule.php supprimer.php upload.php mail.php"

    for page in $PAGES; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/$page" 2>/dev/null)
        BODY=$(curl -s --max-time 5 "http://www.$DOMAIN/$page" 2>/dev/null)

        if [ "$CODE" = "200" ]; then
            if echo "$BODY" | grep -qi "fatal error\|parse error"; then
                fail "$page -> $CODE (erreur PHP)"
            else
                ok "$page -> $CODE"
            fi
        elif [ "$CODE" = "302" ]; then
            ok "$page -> $CODE (redirection)"
        else
            fail "$page -> $CODE"
        fi
    done

    pause
}

test_insert() {
    header
    section "11.3.4 - Test INSERT (ajout proprietaire)"

    TIMESTAMP=$(date +%s)
    RESULT=$(curl -s -w "\n%{http_code}" --max-time 5 \
        -X POST "http://www.$DOMAIN/ajouter_proprietaire.php" \
        -d "civilite=M.&nom=Demo${TIMESTAMP}&prenom=Test&email=demo${TIMESTAMP}@test.com&adresse=Demo&telephone=0000000000" 2>/dev/null)

    CODE=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | head -n -1)

    if [ "$CODE" = "200" ]; then
        ok "POST ajouter_proprietaire.php -> $CODE"
        if echo "$BODY" | grep -qi "succes\|ajoute"; then
            ok "INSERT reussi"
        fi
    else
        fail "POST -> $CODE"
    fi

    echo ""
    info "Verification dans la BDD :"
    if [ "$ROLE" = "SERVEUR" ]; then
        sudo -u postgres psql -d "$DB_NAME" -c "SELECT id, nom, prenom, email FROM proprietaire ORDER BY id DESC LIMIT 3;" 2>/dev/null
    else
        curl -s --max-time 5 "http://www.$DOMAIN/proprietaires.php?q=Demo${TIMESTAMP}" 2>/dev/null | grep -i "Demo${TIMESTAMP}" | head -3
    fi

    pause
}

test_select() {
    header
    section "11.3.4 - Test SELECT (liste proprietaires)"

    echo -e "${BOLD}Reponse HTTP :${NC}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://www.$DOMAIN/proprietaires.php" 2>/dev/null)
    ok "proprietaires.php -> $CODE"
    echo ""

    echo -e "${BOLD}Contenu (extrait) :${NC}"
    curl -s --max-time 5 "http://www.$DOMAIN/proprietaires.php" 2>/dev/null | \
        grep -oP '(?<=<td>)[^<]+' | head -20

    pause
}

show_php_files() {
    header
    section "11.3.4 - Fichiers PHP deployes"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "${BOLD}Fichiers dans $WWW_DIR :${NC}"
        ls -la "$WWW_DIR"/*.php "$WWW_DIR"/*.html 2>/dev/null
        echo ""
        echo -e "${BOLD}Dossier uploads :${NC}"
        ls -la "$WWW_DIR/uploads/" 2>/dev/null || echo "  (vide ou inexistant)"
    else
        info "Fichiers PHP sur le SERVEUR dans $WWW_DIR"
    fi

    pause
}

# =============================================================
# 50-54 - MAIL
# =============================================================

test_smtp() {
    header
    section "11.3.5 - Test SMTP"

    TARGET="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        TARGET="127.0.0.1"
    fi

    RESPONSE=$(echo "QUIT" | timeout 3 nc "$TARGET" 25 2>/dev/null | head -1)
    if echo "$RESPONSE" | grep -q "220"; then
        ok "SMTP repond : $RESPONSE"
    else
        fail "SMTP ne repond pas"
    fi

    echo ""
    echo -e "${BOLD}Test EHLO :${NC}"
    echo -e "EHLO demo\nQUIT" | timeout 3 nc "$TARGET" 25 2>/dev/null

    pause
}

test_imap() {
    header
    section "11.3.5 - Test IMAP"

    TARGET="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        TARGET="127.0.0.1"
    fi

    RESPONSE=$(echo "a1 LOGOUT" | timeout 3 nc "$TARGET" 143 2>/dev/null | head -1)
    if echo "$RESPONSE" | grep -qi "OK\|Dovecot\|IMAP"; then
        ok "IMAP repond"
    else
        fail "IMAP ne repond pas"
    fi

    echo ""
    echo -e "${BOLD}Test LOGIN :${NC}"
    echo -e "a1 LOGIN $USER $DB_PASS\na2 LIST \"\" \"*\"\na3 LOGOUT" | timeout 3 nc "$TARGET" 143 2>/dev/null

    pause
}

send_test_mail() {
    header
    section "11.3.5 - Envoi d'un mail de test"

    TARGET="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        TARGET="127.0.0.1"
    fi

    echo " Envoyer a quel domaine ?"
    echo -e "  1) contact@$DOMAIN"
    echo -e "  2) contact@$DOMAIN2"
    echo -e "  3) contact@$DOMAIN3"
    echo -ne " Choix : "
    read choice

    case $choice in
        1) DEST="contact@$DOMAIN" ;;
        2) DEST="contact@$DOMAIN2" ;;
        3) DEST="contact@$DOMAIN3" ;;
        *) return ;;
    esac

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    RESULT=$(echo -e "EHLO demo\nMAIL FROM:<demo@$DOMAIN>\nRCPT TO:<$DEST>\nDATA\nSubject: Demo SAE 203 - $TIMESTAMP\n\nMail envoye pendant la demonstration.\nDate: $TIMESTAMP\nDepuis: $ROLE\n.\nQUIT" | timeout 5 nc "$TARGET" 25 2>/dev/null)

    echo "$RESULT"
    echo ""
    if echo "$RESULT" | grep -q "250.*queued\|250 2.0.0"; then
        ok "Mail envoye a $DEST"
    else
        warn "Verifiez le resultat ci-dessus"
    fi

    pause
}

show_maildir() {
    header
    section "11.3.5 - Mails recus (Maildir)"

    if [ "$ROLE" = "SERVEUR" ]; then
        MAILDIR="/users/firms/exemple/Maildir"
        echo -e "${BOLD}Mails dans new/ :${NC}"
        NB=$(ls "$MAILDIR/new/" 2>/dev/null | wc -l)
        info "$NB mail(s) non lu(s)"
        echo ""

        if [ "$NB" -gt 0 ]; then
            echo -e "${BOLD}Dernier mail :${NC}"
            LAST=$(ls -t "$MAILDIR/new/" 2>/dev/null | head -1)
            if [ -n "$LAST" ]; then
                head -20 "$MAILDIR/new/$LAST"
            fi
        fi
    else
        info "Maildir disponible uniquement sur le SERVEUR"
        info "Utilisez Thunderbird pour lire les mails"
    fi

    pause
}

show_mail_logs() {
    header
    section "11.3.5 - Logs mail"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "${BOLD}Derniers 20 logs :${NC}"
        sudo tail -20 /var/log/mail.log 2>/dev/null
    else
        info "Logs mail disponibles uniquement sur le SERVEUR"
    fi

    pause
}

# =============================================================
# 60-61 - SFTP
# =============================================================

test_sftp() {
    header
    section "11.3.6 - Test SSH/SFTP"

    TARGET="$SERVER_IP"
    if [ "$ROLE" = "SERVEUR" ]; then
        TARGET="127.0.0.1"
    fi

    # Banner SSH
    BANNER=$(echo "" | timeout 3 nc "$TARGET" 22 2>/dev/null | head -1)
    if echo "$BANNER" | grep -qi "SSH"; then
        ok "SSH repond : $BANNER"
    else
        fail "SSH ne repond pas"
    fi

    # Port 22
    if nc -zw3 "$TARGET" 22 2>/dev/null; then
        ok "Port 22 accessible"
    fi

    if [ "$ROLE" = "SERVEUR" ]; then
        echo ""
        echo -e "${BOLD}Config SFTP :${NC}"
        grep "Subsystem.*sftp" /etc/ssh/sshd_config 2>/dev/null
    fi

    pause
}

show_filezilla_config() {
    header
    section "11.3.6 - Configuration FileZilla"

    echo -e "${BOLD}Parametres FileZilla :${NC}"
    echo ""
    echo -e "  Hote        : ${CYAN}sftp://$SERVER_IP${NC}"
    echo -e "  Port        : ${CYAN}22${NC}"
    echo -e "  Protocole   : ${CYAN}SFTP - SSH File Transfer Protocol${NC}"
    echo -e "  Utilisateur : ${CYAN}$USER${NC}"
    echo -e "  Mot de passe: ${CYAN}$DB_PASS${NC}"
    echo -e "  Repertoire  : ${CYAN}/users/firms/exemple/www/${NC}"
    echo ""
    echo -e "${BOLD}Pour demarrer FileZilla :${NC}"
    echo "  filezilla sftp://$USER:$DB_PASS@$SERVER_IP"

    if [ "$ROLE" = "CLIENT" ] && command -v filezilla &>/dev/null; then
        echo ""
        echo -ne " Lancer FileZilla maintenant ? (o/n) : "
        read choice
        if [ "$choice" = "o" ]; then
            filezilla "sftp://$USER:$DB_PASS@$SERVER_IP" &>/dev/null &
            info "FileZilla lance"
        fi
    fi

    pause
}

# =============================================================
# 70-73 - CRON
# =============================================================

show_cron() {
    header
    section "11.3.7 - Cron configure"

    if [ "$ROLE" = "SERVEUR" ]; then
        echo -e "${BOLD}Crontab de $USER :${NC}"
        crontab -u "$USER" -l 2>/dev/null || echo "  (aucun cron)"
        echo ""

        echo -e "${BOLD}Crontab root :${NC}"
        crontab -l 2>/dev/null | grep -v "^#" || echo "  (aucun cron)"
        echo ""

        echo -e "${BOLD}Service cron :${NC}"
        systemctl is-active cron 2>/dev/null && ok "cron actif" || fail "cron inactif"
    else
        info "Cron disponible uniquement sur le SERVEUR"
    fi

    pause
}

run_cron_manual() {
    header
    section "11.3.7 - Execution manuelle de cron_mail.php"

    if [ "$ROLE" = "SERVEUR" ] && [ -f "$WWW_DIR/cron_mail.php" ]; then
        echo -e "${BOLD}Execution :${NC}"
        php "$WWW_DIR/cron_mail.php" 2>&1
    else
        info "cron_mail.php disponible uniquement sur le SERVEUR"
    fi

    pause
}

show_rappels() {
    header
    section "11.3.7 - Rappels envoyes"

    if [ "$ROLE" = "SERVEUR" ]; then
        sudo -u postgres psql -d "$DB_NAME" -c \
            "SELECT r.date_envoi, v.immatriculation, p.nom, p.prenom, p.email, r.type_rappel
             FROM rappel_envoye r
             JOIN vehicule v ON r.vehicule_id = v.id
             JOIN proprietaire p ON v.proprietaire_id = p.id
             ORDER BY r.date_envoi DESC LIMIT 10;" 2>/dev/null
    else
        info "Rappels disponibles uniquement sur le SERVEUR"
        info "Ou via http://www.$DOMAIN/mail.php"
    fi

    pause
}

show_cron_log() {
    header
    section "11.3.7 - Log cron mail"

    if [ "$ROLE" = "SERVEUR" ]; then
        if [ -f /var/log/carte_grise_mail.log ]; then
            echo -e "${BOLD}Dernieres lignes :${NC}"
            tail -20 /var/log/carte_grise_mail.log
        else
            info "Log /var/log/carte_grise_mail.log n'existe pas encore"
            info "Il sera cree au premier declenchement du cron"
        fi
    else
        info "Log disponible uniquement sur le SERVEUR"
    fi

    pause
}

# =============================================================
# 80-81 - TESTS COMPLETS
# =============================================================

run_all_tests() {
    header
    section "Tests complets - Toutes les phases"

    TOTAL_OK=0
    TOTAL_FAIL=0

    run_test() {
        local desc="$1"
        local cmd="$2"
        local result
        result=$(eval "$cmd" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            ok "$desc"
            ((TOTAL_OK++))
        else
            fail "$desc"
            ((TOTAL_FAIL++))
        fi
    }

    echo -e "${BOLD}Phase 2 - Apache :${NC}"
    for domain in $ALL_DOMAINS; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://www.$domain/" 2>/dev/null)
        if [ "$CODE" = "200" ]; then ok "HTTP www.$domain"; TOTAL_OK=$((TOTAL_OK+1)); else fail "HTTP www.$domain ($CODE)"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
        CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://www.$domain/" 2>/dev/null)
        if [ "$CODE" = "200" ]; then ok "HTTPS www.$domain"; TOTAL_OK=$((TOTAL_OK+1)); else fail "HTTPS www.$domain ($CODE)"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
    done

    echo ""
    echo -e "${BOLD}Phase 3 - DNS :${NC}"
    DNS_T="$SERVER_IP"
    [ "$ROLE" = "SERVEUR" ] && DNS_T="127.0.0.1"
    for domain in $ALL_DOMAINS; do
        R=$(dig @"$DNS_T" "www.$domain" +short 2>/dev/null)
        if [ -n "$R" ]; then ok "dig www.$domain -> $R"; TOTAL_OK=$((TOTAL_OK+1)); else fail "dig www.$domain"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
    done

    echo ""
    echo -e "${BOLD}Phase 4/5 - BDD + PHP :${NC}"
    for page in index.php proprietaires.php vehicules.php ajouter_proprietaire.php upload.php mail.php; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://www.$DOMAIN/$page" 2>/dev/null)
        if [ "$CODE" = "200" ]; then ok "$page -> $CODE"; TOTAL_OK=$((TOTAL_OK+1)); else fail "$page -> $CODE"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
    done

    echo ""
    echo -e "${BOLD}Phase 6 - Mail :${NC}"
    SMTP_R=$(echo "QUIT" | timeout 3 nc ${DNS_T} 25 2>/dev/null | head -1)
    if echo "$SMTP_R" | grep -q "220"; then ok "SMTP"; TOTAL_OK=$((TOTAL_OK+1)); else fail "SMTP"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
    IMAP_R=$(echo "a1 LOGOUT" | timeout 3 nc ${DNS_T} 143 2>/dev/null | head -1)
    if echo "$IMAP_R" | grep -qi "OK\|Dovecot"; then ok "IMAP"; TOTAL_OK=$((TOTAL_OK+1)); else fail "IMAP"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi

    echo ""
    echo -e "${BOLD}Phase 8 - SSH/SFTP :${NC}"
    if nc -zw3 "$DNS_T" 22 2>/dev/null; then ok "SSH port 22"; TOTAL_OK=$((TOTAL_OK+1)); else fail "SSH port 22"; TOTAL_FAIL=$((TOTAL_FAIL+1)); fi

    echo ""
    TOTAL=$((TOTAL_OK + TOTAL_FAIL))
    echo -e "${BOLD}=========================================="
    if [ $TOTAL_FAIL -eq 0 ]; then
        echo -e " ${GREEN}TOUS LES TESTS OK : $TOTAL_OK/$TOTAL${NC}"
    else
        echo -e " ${RED}$TOTAL_OK/$TOTAL OK, $TOTAL_FAIL ECHECS${NC}"
    fi
    echo -e "==========================================${NC}"

    pause
}

quick_test() {
    header
    section "Test rapide - Verification essentielle"

    echo -e "${BOLD}Services :${NC}"
    for svc in apache2 postgresql postfix dovecot ssh; do
        systemctl is-active --quiet "$svc" 2>/dev/null && ok "$svc" || fail "$svc"
    done
    SVC_BIND="named"
    systemctl is-active --quiet named 2>/dev/null || SVC_BIND="bind9"
    systemctl is-active --quiet "$SVC_BIND" 2>/dev/null && ok "bind9" || fail "bind9"

    echo ""
    echo -e "${BOLD}Web :${NC}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://www.$DOMAIN/index.php" 2>/dev/null)
    [ "$CODE" = "200" ] && ok "HTTP index.php" || fail "HTTP index.php ($CODE)"
    CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://www.$DOMAIN/" 2>/dev/null)
    [ "$CODE" = "200" ] && ok "HTTPS" || fail "HTTPS ($CODE)"

    echo ""
    echo -e "${BOLD}DNS :${NC}"
    DNS_T="$SERVER_IP"
    [ "$ROLE" = "SERVEUR" ] && DNS_T="127.0.0.1"
    R=$(dig @"$DNS_T" "www.$DOMAIN" +short 2>/dev/null)
    [ -n "$R" ] && ok "DNS www.$DOMAIN -> $R" || fail "DNS"

    echo ""
    echo -e "${BOLD}Mail :${NC}"
    SMTP_R=$(echo "QUIT" | timeout 2 nc ${DNS_T} 25 2>/dev/null | head -1)
    echo "$SMTP_R" | grep -q "220" && ok "SMTP" || fail "SMTP"

    pause
}

# =============================================================
# 90-92 - BONUS PHASE 9
# =============================================================

add_domain_menu() {
    header
    section "Phase 9 (Bonus) - Ajouter un domaine"

    if [ "$ROLE" != "SERVEUR" ]; then
        info "Disponible uniquement sur le SERVEUR"
        pause
        return
    fi

    echo -ne " Nom de domaine a ajouter : "
    read new_domain

    if [ -n "$new_domain" ]; then
        echo ""
        echo -ne " Simulation d'abord ? (o/n) : "
        read sim
        if [ "$sim" = "o" ]; then
            python3 /users/firms/exemple/ajouter_domaine.py "$new_domain" --dry-run 2>/dev/null || \
            bash /users/firms/exemple/create_domain.sh "$new_domain" --dry-run 2>/dev/null || \
            info "Script d'automatisation non trouve"
        else
            python3 /users/firms/exemple/ajouter_domaine.py "$new_domain" 2>/dev/null || \
            bash /users/firms/exemple/create_domain.sh "$new_domain" 2>/dev/null || \
            info "Script d'automatisation non trouve"
        fi
    fi

    pause
}

list_domains_menu() {
    header
    section "Phase 9 (Bonus) - Lister les domaines"

    python3 /users/firms/exemple/ajouter_domaine.py --list 2>/dev/null || \
    bash /users/firms/exemple/create_domain.sh --list 2>/dev/null || \
    info "Script d'automatisation non trouve"

    pause
}

remove_domain_menu() {
    header
    section "Phase 9 (Bonus) - Supprimer un domaine"

    if [ "$ROLE" != "SERVEUR" ]; then
        info "Disponible uniquement sur le SERVEUR"
        pause
        return
    fi

    echo -ne " Nom de domaine a supprimer : "
    read del_domain

    if [ -n "$del_domain" ]; then
        echo -ne " Confirmer la suppression de $del_domain ? (oui/non) : "
        read confirm
        if [ "$confirm" = "oui" ]; then
            python3 /users/firms/exemple/ajouter_domaine.py "$del_domain" --remove 2>/dev/null || \
            bash /users/firms/exemple/create_domain.sh "$del_domain" --remove 2>/dev/null || \
            info "Script d'automatisation non trouve"
        fi
    fi

    pause
}

# =============================================================
# BOUCLE PRINCIPALE
# =============================================================

while true; do
    show_menu
    read choice

    case $choice in
        0)  clear; exit 0 ;;
        # VOIR
        1)  dashboard ;;
        2)  network_info ;;
        3)  services_ports ;;
        4)  show_vhosts ;;
        5)  show_ssl ;;
        6)  show_zones ;;
        7)  show_tables ;;
        8)  show_table_structure ;;
        9)  show_php_files ;;
        10) show_maildir ;;
        11) show_mail_logs ;;
        12) show_cron ;;
        13) show_rappels ;;
        14) show_cron_log ;;
        15) show_filezilla_config ;;
        16) run_sql ;;
        17) open_browser ;;
        # TESTS
        20) quick_test ;;
        21) run_all_tests ;;
        22) test_http ;;
        23) test_https ;;
        24) test_dns_dig ;;
        25) test_dns_nslookup ;;
        26) test_mx ;;
        27) check_dns_syntax ;;
        28) test_phppgadmin ;;
        29) test_php_pages ;;
        30) test_insert ;;
        31) test_select ;;
        32) test_smtp ;;
        33) test_imap ;;
        34) send_test_mail ;;
        35) test_sftp ;;
        36) run_cron_manual ;;
        # BONUS
        90) add_domain_menu ;;
        91) list_domains_menu ;;
        92) remove_domain_menu ;;
        *)  echo -e " ${RED}Choix invalide${NC}"; sleep 1 ;;
    esac
done

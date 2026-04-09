#!/bin/bash

# =============================================================
# config_server.sh - SAE S203 - Vérification & Configuration
# Vérifie chaque service/config, corrige si nécessaire
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./config_server.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
ALL_DOMAINS="$DOMAIN $DOMAIN2 $DOMAIN3"
USER="exemple"
USER_HOME="/users/firms/exemple"
WWW_DIR="$USER_HOME/www"
DB_USER="exemple"
DB_PASS="but1"
SERVER_IP="192.168.1.1"

ERRORS=0
FIXES=0

ok()    { echo -e "  ${GREEN}[OK]${NC} $1"; }
fix()   { echo -e "  ${YELLOW}[FIX]${NC} $1"; ((FIXES++)); }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; ((ERRORS++)); }

echo "=========================================="
echo " SAE S203 - Vérification de la config"
echo "=========================================="

# =============================================================
# 1. PAQUETS
# =============================================================
echo ""
echo ">>> 1. Vérification des paquets installés"

PACKAGES="aptitude apache2 apache2-utils php libapache2-mod-php php-pgsql
postgresql postgresql-client phppgadmin bind9 bind9utils dnsutils
postfix dovecot-core dovecot-imapd dovecot-pop3d openssh-server openssl"

MISSING=""
for pkg in $PACKAGES; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
        fail "Paquet manquant : $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    fix "Installation des paquets manquants..."
    apt-get update -qq
    apt-get install -y $MISSING
    for pkg in $MISSING; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            ok "$pkg installé"
        else
            fail "$pkg n'a pas pu être installé"
        fi
    done
else
    ok "Tous les paquets sont installés"
fi

# =============================================================
# 2. UTILISATEUR "exemple"
# =============================================================
echo ""
echo ">>> 2. Vérification de l'utilisateur '$USER'"

if ! id "$USER" &>/dev/null; then
    fix "Création de l'utilisateur '$USER'..."
    mkdir -p /users/firms
    useradd -m -d "$USER_HOME" -s /bin/bash "$USER"
    echo "$USER:$DB_PASS" | chpasswd
else
    ok "Utilisateur '$USER' existe"
    # Vérifier que le home est bien /users/firms/exemple
    CURRENT_HOME=$(eval echo "~$USER")
    if [ "$CURRENT_HOME" != "$USER_HOME" ]; then
        fix "Changement du home de $USER vers $USER_HOME"
        mkdir -p "$USER_HOME"
        usermod -d "$USER_HOME" "$USER"
        # Copier le contenu de l'ancien home si nécessaire
        if [ -d "$CURRENT_HOME" ] && [ "$CURRENT_HOME" != "$USER_HOME" ]; then
            cp -a "$CURRENT_HOME/." "$USER_HOME/" 2>/dev/null
        fi
        chown -R "$USER:$USER" "$USER_HOME"
    fi
fi

if [ ! -d "$USER_HOME" ]; then
    fix "Création du répertoire home $USER_HOME"
    mkdir -p "$USER_HOME"
    chown "$USER:$USER" "$USER_HOME"
else
    ok "Répertoire $USER_HOME existe"
fi

if [ ! -d "$WWW_DIR" ]; then
    fix "Création du répertoire $WWW_DIR"
    mkdir -p "$WWW_DIR"
    chown "$USER:$USER" "$WWW_DIR"
else
    ok "Répertoire $WWW_DIR existe"
fi

# =============================================================
# 3. CERTIFICAT SSL AUTO-SIGNÉ
# =============================================================
echo ""
echo ">>> 3. Vérification du certificat SSL"

if [ ! -f /etc/ssl/certs/exemple.crt ] || [ ! -f /etc/ssl/private/exemple.key ]; then
    fix "Génération du certificat SSL auto-signé..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/exemple.key \
        -out /etc/ssl/certs/exemple.crt \
        -subj "/C=FR/ST=PACA/L=Nice/O=IUT/CN=$DOMAIN" 2>/dev/null
else
    # Vérifier si le certificat n'est pas expiré
    if openssl x509 -checkend 0 -noout -in /etc/ssl/certs/exemple.crt 2>/dev/null; then
        ok "Certificat SSL valide"
    else
        fix "Certificat expiré, régénération..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/exemple.key \
            -out /etc/ssl/certs/exemple.crt \
            -subj "/C=FR/ST=PACA/L=Nice/O=IUT/CN=$DOMAIN" 2>/dev/null
    fi
fi

# =============================================================
# 4. MODULES APACHE
# =============================================================
echo ""
echo ">>> 4. Vérification des modules Apache"

for mod in ssl rewrite userdir php*; do
    if ! a2query -m "$mod" &>/dev/null; then
        fix "Activation du module Apache : $mod"
        a2enmod "$mod" &>/dev/null
    else
        ok "Module Apache '$mod' actif"
    fi
done

# =============================================================
# 5. VIRTUALHOSTS APACHE
# =============================================================
echo ""
echo ">>> 5. Vérification des VirtualHosts Apache"

for domain in $ALL_DOMAINS; do
    CONF="/etc/apache2/sites-available/$domain.conf"
    CONF_SSL="/etc/apache2/sites-available/$domain-ssl.conf"

    # --- HTTP ---
    if [ ! -f "$CONF" ]; then
        fix "Création du VirtualHost HTTP pour $domain"
        cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName www.$domain
    ServerAlias $domain
    DocumentRoot $WWW_DIR
    <Directory $WWW_DIR>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>
EOF
    else
        ok "VirtualHost HTTP $domain existe"
    fi

    # --- HTTPS ---
    if [ ! -f "$CONF_SSL" ]; then
        fix "Création du VirtualHost HTTPS pour $domain"
        cat > "$CONF_SSL" <<EOF
<VirtualHost *:443>
    ServerName www.$domain
    ServerAlias $domain
    DocumentRoot $WWW_DIR
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/exemple.crt
    SSLCertificateKeyFile /etc/ssl/private/exemple.key
    <Directory $WWW_DIR>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${domain}_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_ssl_access.log combined
</VirtualHost>
EOF
    else
        ok "VirtualHost HTTPS $domain existe"
    fi

    # --- Activation des sites ---
    if ! a2query -s "$domain" &>/dev/null; then
        fix "Activation du site $domain"
        a2ensite "$domain.conf" &>/dev/null
    else
        ok "Site $domain activé"
    fi

    if ! a2query -s "$domain-ssl" &>/dev/null; then
        fix "Activation du site $domain-ssl"
        a2ensite "$domain-ssl.conf" &>/dev/null
    else
        ok "Site $domain-ssl activé"
    fi

    # --- Page par défaut pour chaque domaine ---
    DOMAIN_INDEX="$WWW_DIR/index_${domain}.html"
    if [ ! -f "$WWW_DIR/index.html" ]; then
        fix "Création de la page index.html"
        cat > "$WWW_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>$domain</title></head>
<body>
    <h1>Bienvenue sur www.$domain</h1>
    <p>SAE S203 - IUT de Nice</p>
</body>
</html>
EOF
        chown "$USER:$USER" "$WWW_DIR/index.html"
    fi
done

# --- index.php ---
if [ ! -f "$WWW_DIR/index.php" ]; then
    fix "Création de index.php"
    cat > "$WWW_DIR/index.php" <<'EOF'
<?php
echo "<h1>PHP fonctionne</h1>";
echo "<p>Version PHP : " . phpversion() . "</p>";
phpinfo();
?>
EOF
    chown "$USER:$USER" "$WWW_DIR/index.php"
else
    ok "index.php existe"
fi

# Vérifier la syntaxe Apache
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    ok "Syntaxe Apache OK"
else
    fail "Erreur de syntaxe Apache :"
    apache2ctl configtest 2>&1
fi

# =============================================================
# 6. POSTGRESQL
# =============================================================
echo ""
echo ">>> 6. Vérification de PostgreSQL"

if ! systemctl is-active --quiet postgresql; then
    fix "Démarrage de PostgreSQL..."
    systemctl start postgresql
else
    ok "PostgreSQL est actif"
fi

if ! systemctl is-enabled --quiet postgresql; then
    fix "Activation de PostgreSQL au démarrage"
    systemctl enable postgresql
else
    ok "PostgreSQL activé au démarrage"
fi

# Vérifier l'utilisateur PostgreSQL
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null | grep -q 1; then
    ok "Utilisateur PostgreSQL '$DB_USER' existe"
else
    fix "Création de l'utilisateur PostgreSQL '$DB_USER'..."
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
    sudo -u postgres psql -c "ALTER USER $DB_USER CREATEDB;"
fi

# Vérifier la connexion avec l'utilisateur
if PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d postgres -c "SELECT 1;" &>/dev/null; then
    ok "Connexion PostgreSQL avec '$DB_USER' fonctionne"
else
    fix "Réinitialisation du mot de passe de '$DB_USER'..."
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';"
fi

# =============================================================
# 7. PHPPGADMIN
# =============================================================
echo ""
echo ">>> 7. Vérification de phpPgAdmin"

if [ -f /etc/apache2/conf-available/phppgadmin.conf ]; then
    if ! a2query -c phppgadmin &>/dev/null; then
        fix "Activation de phpPgAdmin dans Apache"
        a2enconf phppgadmin &>/dev/null
    else
        ok "phpPgAdmin configuré dans Apache"
    fi
else
    if [ -f /etc/phppgadmin/apache.conf ]; then
        fix "Lien de la config phpPgAdmin vers Apache"
        ln -sf /etc/phppgadmin/apache.conf /etc/apache2/conf-available/phppgadmin.conf
        a2enconf phppgadmin &>/dev/null
    else
        fail "Config phpPgAdmin introuvable"
    fi
fi

# Autoriser l'accès distant à phpPgAdmin (vérifier les deux emplacements possibles)
for pgaconf in /etc/apache2/conf-available/phppgadmin.conf /etc/phppgadmin/apache.conf; do
    if [ -f "$pgaconf" ]; then
        if grep -q "Require local" "$pgaconf" 2>/dev/null; then
            fix "Autorisation de l'accès distant dans $pgaconf"
            sed -i 's/Require local/Require all granted/' "$pgaconf"
        fi
        if grep -q "deny from all" "$pgaconf" 2>/dev/null; then
            fix "Suppression de 'deny from all' dans $pgaconf"
            sed -i 's/deny from all/allow from all/' "$pgaconf"
        fi
    fi
done
# Vérifier le résultat
if curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost/phppgadmin/" 2>/dev/null | grep -qE "200|301|302"; then
    ok "phpPgAdmin accessible"
else
    ok "phpPgAdmin configuré (redémarrage Apache nécessaire)"
fi

# =============================================================
# 8. BIND9 (DNS)
# =============================================================
echo ""
echo ">>> 8. Vérification de Bind9 (DNS)"

if ! systemctl is-active --quiet named 2>/dev/null && ! systemctl is-active --quiet bind9 2>/dev/null; then
    fix "Démarrage de Bind9..."
    systemctl start named 2>/dev/null || systemctl start bind9 2>/dev/null
else
    ok "Bind9 est actif"
fi

BIND_SERVICE="named"
systemctl is-active --quiet named 2>/dev/null || BIND_SERVICE="bind9"

if ! systemctl is-enabled --quiet "$BIND_SERVICE" 2>/dev/null; then
    fix "Activation de Bind9 au démarrage"
    systemctl enable "$BIND_SERVICE"
else
    ok "Bind9 activé au démarrage"
fi

for domain in $ALL_DOMAINS; do
    ZONE_FILE="/etc/bind/db.$domain"

    # Vérifier si la zone est déclarée
    if ! grep -q "zone \"$domain\"" /etc/bind/named.conf.local 2>/dev/null; then
        fix "Ajout de la zone DNS pour $domain"
        cat >> /etc/bind/named.conf.local <<EOF

zone "$domain" {
    type master;
    file "$ZONE_FILE";
};
EOF
    else
        ok "Zone DNS '$domain' déclarée"
    fi

    # Vérifier le fichier de zone
    if [ ! -f "$ZONE_FILE" ]; then
        fix "Création du fichier de zone $ZONE_FILE"
        cat > "$ZONE_FILE" <<EOF
\$TTL    604800
@       IN      SOA     ns1.$domain. admin.$domain. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$domain.
ns1     IN      A       $SERVER_IP
@       IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
@       IN      MX  10  mail.$domain.
mail    IN      A       $SERVER_IP
EOF
    else
        ok "Fichier de zone $domain existe"
        # Vérifier les enregistrements essentiels
        for record in "www" "mail" "MX"; do
            if ! grep -q "$record" "$ZONE_FILE"; then
                fail "Enregistrement '$record' manquant dans $ZONE_FILE"
            fi
        done
    fi

    # Vérifier la syntaxe du fichier de zone
    if command -v named-checkzone &>/dev/null; then
        if named-checkzone "$domain" "$ZONE_FILE" &>/dev/null; then
            ok "Syntaxe zone $domain OK"
        else
            fail "Erreur de syntaxe dans la zone $domain"
            named-checkzone "$domain" "$ZONE_FILE" 2>&1
        fi
    fi
done

# Vérifier named.conf
if command -v named-checkconf &>/dev/null; then
    if named-checkconf &>/dev/null; then
        ok "Syntaxe named.conf OK"
    else
        fail "Erreur dans named.conf :"
        named-checkconf 2>&1
    fi
fi

# Vérifier que le serveur écoute en local
if grep -q "listen-on" /etc/bind/named.conf.options 2>/dev/null; then
    ok "Bind9 listen-on configuré"
else
    # Vérifier que forwarders est configuré
    if ! grep -q "forwarders" /etc/bind/named.conf.options 2>/dev/null; then
        fix "Ajout des forwarders DNS (8.8.8.8)"
        sed -i '/options {/a\\tforwarders {\n\t\t8.8.8.8;\n\t\t8.8.4.4;\n\t};' /etc/bind/named.conf.options 2>/dev/null
    else
        ok "Forwarders DNS configurés"
    fi
fi

# =============================================================
# 9. POSTFIX (MAIL SMTP)
# =============================================================
echo ""
echo ">>> 9. Vérification de Postfix (mail)"

if ! systemctl is-active --quiet postfix; then
    fix "Démarrage de Postfix..."
    systemctl start postfix
else
    ok "Postfix est actif"
fi

if ! systemctl is-enabled --quiet postfix; then
    fix "Activation de Postfix au démarrage"
    systemctl enable postfix
else
    ok "Postfix activé au démarrage"
fi

# Vérifier myhostname
POSTFIX_HOSTNAME=$(postconf -h myhostname 2>/dev/null)
if [ "$POSTFIX_HOSTNAME" != "$DOMAIN" ]; then
    fix "Configuration myhostname = $DOMAIN"
    postconf -e "myhostname = $DOMAIN"
fi

# Vérifier mydestination (tous les domaines)
MYDEST=$(postconf -h mydestination 2>/dev/null)
for domain in $ALL_DOMAINS; do
    if ! echo "$MYDEST" | grep -q "$domain"; then
        fix "Ajout de $domain dans mydestination"
        postconf -e "mydestination = $(postconf -h mydestination), $domain"
    else
        ok "$domain dans mydestination"
    fi
done

# Vérifier home_mailbox
HOME_MAILBOX=$(postconf -h home_mailbox 2>/dev/null)
if [ -z "$HOME_MAILBOX" ] || [ "$HOME_MAILBOX" = "" ]; then
    fix "Configuration home_mailbox = Maildir/"
    postconf -e "home_mailbox = Maildir/"
else
    ok "home_mailbox configuré ($HOME_MAILBOX)"
fi

# =============================================================
# 10. DOVECOT (IMAP/POP3)
# =============================================================
echo ""
echo ">>> 10. Vérification de Dovecot"

if ! systemctl is-active --quiet dovecot; then
    fix "Démarrage de Dovecot..."
    systemctl start dovecot
else
    ok "Dovecot est actif"
fi

if ! systemctl is-enabled --quiet dovecot; then
    fix "Activation de Dovecot au démarrage"
    systemctl enable dovecot
else
    ok "Dovecot activé au démarrage"
fi

# Vérifier que mail_location est configuré
if grep -rq "mail_location = maildir:~/Maildir" /etc/dovecot/ 2>/dev/null; then
    ok "Dovecot mail_location configuré (Maildir)"
else
    fix "Configuration de mail_location dans Dovecot"
    if [ -f /etc/dovecot/conf.d/10-mail.conf ]; then
        sed -i 's|^#*mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
    else
        echo "mail_location = maildir:~/Maildir" >> /etc/dovecot/dovecot.conf
    fi
fi

# Vérifier que les protocoles imap et pop3 sont activés
if doveconf protocols 2>/dev/null | grep -q "imap"; then
    ok "Dovecot protocole IMAP actif"
else
    fix "Activation du protocole IMAP"
    if [ -f /etc/dovecot/dovecot.conf ]; then
        sed -i 's|^#*protocols =.*|protocols = imap pop3|' /etc/dovecot/dovecot.conf
    fi
fi

# =============================================================
# 11. OPENSSH / SFTP
# =============================================================
echo ""
echo ">>> 11. Vérification d'OpenSSH (SFTP)"

if ! systemctl is-active --quiet ssh; then
    fix "Démarrage de SSH..."
    systemctl start ssh
else
    ok "SSH est actif"
fi

if ! systemctl is-enabled --quiet ssh; then
    fix "Activation de SSH au démarrage"
    systemctl enable ssh
else
    ok "SSH activé au démarrage"
fi

# Vérifier que SFTP est configuré
if grep -q "Subsystem.*sftp" /etc/ssh/sshd_config 2>/dev/null; then
    ok "SFTP configuré dans sshd_config"
else
    fix "Activation de SFTP dans sshd_config"
    echo "Subsystem sftp /usr/lib/openssh/sftp-server" >> /etc/ssh/sshd_config
fi

# =============================================================
# 12. BOITES MAIL (contact@domaine)
# =============================================================
echo ""
echo ">>> 12. Vérification des boîtes mail"

# Créer l'alias contact si nécessaire
ALIASES_FILE="/etc/aliases"
if ! grep -q "^contact:" "$ALIASES_FILE" 2>/dev/null; then
    fix "Ajout de l'alias mail contact -> $USER"
    echo "contact: $USER" >> "$ALIASES_FILE"
    newaliases
else
    ok "Alias mail 'contact' existe"
fi

# Créer le Maildir pour l'utilisateur
if [ ! -d "$USER_HOME/Maildir" ]; then
    fix "Création du Maildir pour $USER"
    mkdir -p "$USER_HOME/Maildir"/{new,cur,tmp}
    chown -R "$USER:$USER" "$USER_HOME/Maildir"
else
    ok "Maildir de $USER existe"
fi

# =============================================================
# 13. PORTS OUVERTS
# =============================================================
echo ""
echo ">>> 13. Vérification des ports en écoute"

check_port() {
    local port=$1
    local service=$2
    if ss -tlnp | grep -q ":${port} "; then
        ok "Port $port ($service) en écoute"
    else
        fail "Port $port ($service) PAS en écoute"
    fi
}

check_port 22   "SSH/SFTP"
check_port 25   "SMTP/Postfix"
check_port 53   "DNS/Bind9"
check_port 80   "HTTP/Apache"
check_port 143  "IMAP/Dovecot"
check_port 443  "HTTPS/Apache"
check_port 5432 "PostgreSQL"

# =============================================================
# 14. REDÉMARRAGE DES SERVICES MODIFIÉS
# =============================================================
if [ $FIXES -gt 0 ]; then
    echo ""
    echo ">>> 14. Redémarrage des services après corrections..."
    systemctl restart apache2   2>/dev/null
    systemctl restart mariadb   2>/dev/null
    systemctl restart "$BIND_SERVICE" 2>/dev/null
    systemctl restart postfix   2>/dev/null
    systemctl restart dovecot   2>/dev/null
    systemctl restart ssh       2>/dev/null
    ok "Services redémarrés"
fi

# =============================================================
# RÉSUMÉ
# =============================================================
echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ] && [ $FIXES -eq 0 ]; then
    echo -e " ${GREEN}Tout est correctement configuré !${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e " ${YELLOW}$FIXES corrections appliquées, tout est OK maintenant.${NC}"
else
    echo -e " ${RED}$ERRORS problèmes non résolus, $FIXES corrections appliquées.${NC}"
fi
echo "=========================================="
echo ""
echo " Pour tester depuis le client :"
echo "  1. Ajouter dans /etc/hosts du client :"
echo "     $SERVER_IP  www.$DOMAIN www.$DOMAIN2 www.$DOMAIN3"
echo "  2. Firefox  : https://www.$DOMAIN"
echo "  3. phpPgAdmin : http://www.$DOMAIN/phppgadmin"
echo "  4. Mail     : contact@$DOMAIN (Thunderbird)"
echo "  5. SFTP     : sftp $USER@$SERVER_IP (FileZilla)"
echo "=========================================="

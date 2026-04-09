#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# install.sh - SAE S203 - Installation de Services Réseaux
# IUT de Nice - BUT 1
# =============================================================

# Vérifier que le script est exécuté en root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./install.sh)"
    exit 1
fi

# Couleurs pour l'affichage
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Fonction : vérifier si un paquet est installé, sinon l'installer
install_if_missing() {
    local pkg="$1"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo -e "${GREEN}[OK]${NC} $pkg est déjà installé."
    else
        echo -e "${YELLOW}[INSTALL]${NC} Installation de $pkg..."
        apt-get install -y "$pkg"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[OK]${NC} $pkg installé avec succès."
        else
            echo -e "${RED}[ERREUR]${NC} Échec de l'installation de $pkg."
            return 1
        fi
    fi
}

# Variables de configuration
DOMAIN="exemple.com"
DOMAIN2="exemple1.fr"
DOMAIN3="exemple2.eu"
USER="exemple"
USER_HOME="/users/firms/exemple"
WWW_DIR="$USER_HOME/www"
DB_USER="exemple"
DB_PASS="but1"

echo "=========================================="
echo " SAE S203 - Installation des services"
echo "=========================================="

# ---- Mise à jour du système ----
echo ""
echo ">>> Mise à jour du système..."
apt-get update && apt-get upgrade -y

# ---- 1. Aptitude ----
echo ""
echo ">>> 1. Installation d'aptitude"
install_if_missing aptitude

# ---- 2. Apache2 (serveur web) ----
echo ""
echo ">>> 2. Installation d'Apache2"
install_if_missing apache2
install_if_missing apache2-utils

# Activer les modules nécessaires
a2enmod ssl rewrite userdir
systemctl enable apache2
systemctl start apache2

# ---- 3. HTTPS / Certificat auto-signé ----
echo ""
echo ">>> 3. Création du certificat SSL auto-signé"
if [ ! -f /etc/ssl/certs/exemple.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/exemple.key \
        -out /etc/ssl/certs/exemple.crt \
        -subj "/C=FR/ST=PACA/L=Nice/O=IUT/CN=$DOMAIN"
    echo -e "${GREEN}[OK]${NC} Certificat SSL créé."
else
    echo -e "${GREEN}[OK]${NC} Certificat SSL déjà existant."
fi

# ---- 4. PHP ----
echo ""
echo ">>> 4. Installation de PHP"
install_if_missing php
install_if_missing libapache2-mod-php
install_if_missing php-mysql
install_if_missing php-pgsql

# ---- 5. MySQL (SGBD) ----
echo ""
echo ">>> 5. Installation de MySQL"
install_if_missing mariadb-server
install_if_missing mariadb-client
systemctl enable mariadb
systemctl start mariadb

# Créer l'utilisateur MySQL
echo "Création de l'utilisateur MySQL '$DB_USER'..."
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>/dev/null
mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
echo -e "${GREEN}[OK]${NC} Utilisateur MySQL '$DB_USER' créé (mdp: $DB_PASS)."

# ---- 6. phpMyAdmin ----
echo ""
echo ">>> 6. Installation de phpMyAdmin"
if ! dpkg -l phpmyadmin 2>/dev/null | grep -q "^ii"; then
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    install_if_missing phpmyadmin
else
    echo -e "${GREEN}[OK]${NC} phpmyadmin est déjà installé."
fi

# ---- 7. Bind9 (DNS) ----
echo ""
echo ">>> 7. Installation de Bind9 (DNS)"
install_if_missing bind9
install_if_missing bind9utils
install_if_missing dnsutils
systemctl enable named
systemctl start named

# ---- 8. Serveur mail (Postfix + Dovecot) ----
echo ""
echo ">>> 8. Installation du serveur mail"
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mailname string $DOMAIN" | debconf-set-selections
install_if_missing postfix
install_if_missing dovecot-core
install_if_missing dovecot-imapd
install_if_missing dovecot-pop3d
systemctl enable postfix dovecot
systemctl start postfix dovecot

# ---- 9. OpenSSH / SFTP ----
echo ""
echo ">>> 9. Installation d'OpenSSH (SFTP)"
install_if_missing openssh-server
systemctl enable ssh
systemctl start ssh

# ---- 10. Création de l'utilisateur et des répertoires ----
echo ""
echo ">>> 10. Création de l'utilisateur et de l'arborescence"
if ! id "$USER" &>/dev/null; then
    mkdir -p /users/firms
    useradd -m -d "$USER_HOME" -s /bin/bash "$USER"
    echo "$USER:$DB_PASS" | chpasswd
    echo -e "${GREEN}[OK]${NC} Utilisateur '$USER' créé."
else
    echo -e "${GREEN}[OK]${NC} Utilisateur '$USER' existe déjà."
fi

mkdir -p "$WWW_DIR"
chown -R "$USER:$USER" "$USER_HOME"

# Page par défaut
cat > "$WWW_DIR/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>www.exemple.com</title></head>
<body>
    <h1>Bienvenue sur www.exemple.com</h1>
    <p>SAE S203 - IUT de Nice</p>
</body>
</html>
HTMLEOF

cat > "$WWW_DIR/index.php" <<'PHPEOF'
<?php
echo "<h1>PHP fonctionne sur www.exemple.com</h1>";
echo "<p>Version PHP : " . phpversion() . "</p>";
phpinfo();
?>
PHPEOF

chown -R "$USER:$USER" "$WWW_DIR"

# ---- 11. Configuration Apache VirtualHosts ----
echo ""
echo ">>> 11. Configuration des VirtualHosts Apache"

for domain in $DOMAIN $DOMAIN2 $DOMAIN3; do
    CONF="/etc/apache2/sites-available/$domain.conf"
    CONF_SSL="/etc/apache2/sites-available/$domain-ssl.conf"

    # HTTP
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

    # HTTPS
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

    a2ensite "$domain.conf"
    a2ensite "$domain-ssl.conf"
    echo -e "${GREEN}[OK]${NC} VirtualHost configuré pour $domain"
done

# ---- 12. Configuration DNS Bind9 ----
echo ""
echo ">>> 12. Configuration DNS Bind9"

# Adresse IP du serveur (à adapter)
SERVER_IP="10.0.2.15"

for domain in $DOMAIN $DOMAIN2 $DOMAIN3; do
    ZONE_FILE="/etc/bind/db.$domain"

    # Ajouter la zone dans named.conf.local
    if ! grep -q "$domain" /etc/bind/named.conf.local 2>/dev/null; then
        cat >> /etc/bind/named.conf.local <<EOF

zone "$domain" {
    type master;
    file "$ZONE_FILE";
};
EOF
    fi

    # Créer le fichier de zone
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

    echo -e "${GREEN}[OK]${NC} Zone DNS configurée pour $domain"
done

# ---- 13. Redémarrage des services ----
echo ""
echo ">>> 13. Redémarrage de tous les services"
systemctl restart apache2
systemctl restart mariadb
systemctl restart named
systemctl restart postfix
systemctl restart dovecot
systemctl restart ssh

# ---- Résumé ----
echo ""
echo "=========================================="
echo " Installation terminée !"
echo "=========================================="
echo ""
echo " Services installés :"
echo "  - Apache2       (HTTP/HTTPS)"
echo "  - PHP"
echo "  - MariaDB       (MySQL)"
echo "  - phpMyAdmin"
echo "  - Bind9         (DNS)"
echo "  - Postfix       (SMTP)"
echo "  - Dovecot       (IMAP/POP3)"
echo "  - OpenSSH       (SFTP)"
echo ""
echo " Domaines configurés :"
echo "  - www.$DOMAIN"
echo "  - www.$DOMAIN2"
echo "  - www.$DOMAIN3"
echo ""
echo " Utilisateur : $DB_USER / $DB_PASS"
echo " Site web    : $WWW_DIR"
echo ""
echo " Pour tester depuis le client, ajoutez dans /etc/hosts :"
echo "  $SERVER_IP  www.$DOMAIN www.$DOMAIN2 www.$DOMAIN3"
echo "=========================================="

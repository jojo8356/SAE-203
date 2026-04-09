#!/usr/bin/env python3
"""
ajouter_domaine.py - SAE S203 - Automatisation ajout de domaine
IUT de Nice - BUT 1

Ajoute automatiquement un nouveau domaine sur le serveur avec :
  - VirtualHost Apache (HTTP + HTTPS)
  - Zone DNS Bind9
  - Boite mail (Postfix)
  - Base de donnees PostgreSQL
  - Repertoire web + page par defaut
  - Mise a jour /etc/hosts

Usage :
  sudo python3 ajouter_domaine.py monsite.org
  sudo python3 ajouter_domaine.py monsite.org --dry-run   (simulation)
  sudo python3 ajouter_domaine.py --list                   (lister les domaines)
  sudo python3 ajouter_domaine.py monsite.org --remove     (supprimer un domaine)
"""

import os
import sys
import subprocess
import argparse
from datetime import datetime

# =============================================================
# CONFIGURATION
# =============================================================

SERVER_IP = "192.168.100.1"
USER = "exemple"
USER_HOME = "/users/firms/exemple"
WWW_DIR = f"{USER_HOME}/www"
DB_USER = "exemple"
DB_PASS = "but1"
SSL_CERT = "/etc/ssl/certs/exemple.crt"
SSL_KEY = "/etc/ssl/private/exemple.key"

# Couleurs
GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
BOLD = "\033[1m"
NC = "\033[0m"


# =============================================================
# FONCTIONS UTILITAIRES
# =============================================================

def ok(msg):
    print(f"  {GREEN}[OK]{NC}   {msg}")

def fail(msg):
    print(f"  {RED}[FAIL]{NC} {msg}")

def info(msg):
    print(f"  {CYAN}[INFO]{NC} {msg}")

def fix(msg):
    print(f"  {YELLOW}[FIX]{NC}  {msg}")

def run(cmd, check=True):
    """Execute une commande shell et retourne le resultat."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        return False, result.stderr.strip()
    return True, result.stdout.strip()

def file_contains(filepath, text):
    """Verifie si un fichier contient un texte."""
    try:
        with open(filepath, "r") as f:
            return text in f.read()
    except FileNotFoundError:
        return False

def append_to_file(filepath, content):
    """Ajoute du contenu a la fin d'un fichier."""
    with open(filepath, "a") as f:
        f.write(content)

def write_file(filepath, content):
    """Ecrit du contenu dans un fichier (ecrase)."""
    with open(filepath, "w") as f:
        f.write(content)


# =============================================================
# 9.1.1 VIRTUALHOST APACHE + SSL
# =============================================================

def create_apache_vhost(domain, dry_run=False):
    """Cree les VirtualHosts HTTP et HTTPS pour le domaine."""
    print(f"\n{BOLD}>>> 9.1.1 VirtualHost Apache + SSL : {domain}{NC}")

    conf_http = f"/etc/apache2/sites-available/{domain}.conf"
    conf_ssl = f"/etc/apache2/sites-available/{domain}-ssl.conf"

    # --- HTTP ---
    vhost_http = f"""<VirtualHost *:80>
    ServerName www.{domain}
    ServerAlias {domain}
    DocumentRoot {WWW_DIR}
    <Directory {WWW_DIR}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${{APACHE_LOG_DIR}}/{domain}_error.log
    CustomLog ${{APACHE_LOG_DIR}}/{domain}_access.log combined
</VirtualHost>
"""

    # --- HTTPS ---
    vhost_ssl = f"""<VirtualHost *:443>
    ServerName www.{domain}
    ServerAlias {domain}
    DocumentRoot {WWW_DIR}
    SSLEngine on
    SSLCertificateFile {SSL_CERT}
    SSLCertificateKeyFile {SSL_KEY}
    <Directory {WWW_DIR}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${{APACHE_LOG_DIR}}/{domain}_ssl_error.log
    CustomLog ${{APACHE_LOG_DIR}}/{domain}_ssl_access.log combined
</VirtualHost>
"""

    if dry_run:
        info(f"[DRY-RUN] Creerait {conf_http}")
        info(f"[DRY-RUN] Creerait {conf_ssl}")
        info(f"[DRY-RUN] a2ensite {domain}.conf {domain}-ssl.conf")
        return True

    # Ecrire les fichiers
    write_file(conf_http, vhost_http)
    ok(f"VirtualHost HTTP : {conf_http}")

    write_file(conf_ssl, vhost_ssl)
    ok(f"VirtualHost HTTPS : {conf_ssl}")

    # Activer les sites
    run(f"a2ensite {domain}.conf", check=False)
    run(f"a2ensite {domain}-ssl.conf", check=False)
    ok(f"Sites {domain} et {domain}-ssl actives")

    return True


# =============================================================
# 9.1.2 ZONE DNS BIND9
# =============================================================

def create_dns_zone(domain, dry_run=False):
    """Cree la zone DNS pour le domaine dans Bind9."""
    print(f"\n{BOLD}>>> 9.1.2 Zone DNS Bind9 : {domain}{NC}")

    zone_file = f"/etc/bind/db.{domain}"
    named_conf = "/etc/bind/named.conf.local"
    serial = datetime.now().strftime("%Y%m%d01")

    zone_content = f"""$TTL    604800
@       IN      SOA     ns1.{domain}. admin.{domain}. (
                              {serial}  ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.{domain}.
ns1     IN      A       {SERVER_IP}
@       IN      A       {SERVER_IP}
www     IN      A       {SERVER_IP}
@       IN      MX  10  mail.{domain}.
mail    IN      A       {SERVER_IP}
"""

    zone_declaration = f"""
zone "{domain}" {{
    type master;
    file "{zone_file}";
}};
"""

    if dry_run:
        info(f"[DRY-RUN] Creerait {zone_file}")
        info(f"[DRY-RUN] Ajouterait la zone dans {named_conf}")
        return True

    # Creer le fichier de zone
    write_file(zone_file, zone_content)
    ok(f"Fichier de zone : {zone_file}")

    # Ajouter dans named.conf.local (si pas deja present)
    if not file_contains(named_conf, f'zone "{domain}"'):
        append_to_file(named_conf, zone_declaration)
        ok(f"Zone declaree dans {named_conf}")
    else:
        info(f"Zone {domain} deja declaree dans {named_conf}")

    # Verifier la syntaxe
    success, output = run(f"named-checkzone {domain} {zone_file}", check=False)
    if success and "OK" in output:
        ok(f"named-checkzone {domain} : OK")
    else:
        fail(f"named-checkzone {domain} : erreur")
        info(output)

    success, output = run("named-checkconf", check=False)
    if success:
        ok("named-checkconf : OK")
    else:
        fail(f"named-checkconf : erreur - {output}")

    return True


# =============================================================
# 9.1.3 BOITE MAIL (POSTFIX)
# =============================================================

def create_mail(domain, dry_run=False):
    """Configure Postfix pour accepter les mails du nouveau domaine."""
    print(f"\n{BOLD}>>> 9.1.3 Boite mail : {domain}{NC}")

    if dry_run:
        info(f"[DRY-RUN] Ajouterait {domain} dans mydestination")
        info(f"[DRY-RUN] Verifierait l'alias contact")
        return True

    # Ajouter le domaine dans mydestination
    success, mydest = run("postconf -h mydestination", check=False)
    if domain not in mydest:
        new_mydest = f"{mydest}, {domain}"
        run(f'postconf -e "mydestination = {new_mydest}"')
        ok(f"{domain} ajoute dans mydestination")
    else:
        info(f"{domain} deja dans mydestination")

    # Verifier l'alias contact
    aliases_file = "/etc/aliases"
    if not file_contains(aliases_file, "contact:"):
        append_to_file(aliases_file, f"contact: {USER}\n")
        run("newaliases")
        ok("Alias contact cree")
    else:
        info("Alias contact deja present")

    return True


# =============================================================
# 9.1.4 BASE DE DONNEES POSTGRESQL
# =============================================================

def create_database(domain, dry_run=False):
    """Cree une base de donnees PostgreSQL pour le domaine."""
    print(f"\n{BOLD}>>> 9.1.4 Base de donnees : {domain}{NC}")

    # Nom de la BDD : remplacer les points et tirets par des underscores
    db_name = domain.replace(".", "_").replace("-", "_")

    if dry_run:
        info(f"[DRY-RUN] Creerait la base '{db_name}'")
        info(f"[DRY-RUN] Donnerait les droits a '{DB_USER}'")
        return True

    # Verifier si la base existe deja
    success, output = run(
        f"sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='{db_name}'\"",
        check=False
    )
    if "1" in output:
        info(f"Base '{db_name}' existe deja")
    else:
        run(f"sudo -u postgres psql -c \"CREATE DATABASE {db_name} OWNER {DB_USER};\"", check=False)
        ok(f"Base '{db_name}' creee")

    # Droits
    run(f"sudo -u postgres psql -c \"GRANT ALL PRIVILEGES ON DATABASE {db_name} TO {DB_USER};\"", check=False)
    ok(f"Droits accordes a '{DB_USER}' sur '{db_name}'")

    return True


# =============================================================
# 9.1.5 REPERTOIRE WEB + PAGE PAR DEFAUT + HOSTS
# =============================================================

def create_web_dir(domain, dry_run=False):
    """Cree le repertoire web et la page par defaut."""
    print(f"\n{BOLD}>>> 9.1.5 Repertoire web et page par defaut{NC}")

    if dry_run:
        info(f"[DRY-RUN] Creerait la page par defaut pour {domain}")
        info(f"[DRY-RUN] Ajouterait {domain} dans /etc/hosts")
        return True

    # Page par defaut (dans le WWW_DIR commun)
    index_file = f"{WWW_DIR}/index_{domain.replace('.', '_')}.html"
    if not os.path.exists(index_file):
        page = f"""<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>www.{domain}</title></head>
<body>
    <h1>Bienvenue sur www.{domain}</h1>
    <p>SAE S203 - IUT de Nice</p>
    <p>Domaine ajoute automatiquement le {datetime.now().strftime('%Y-%m-%d %H:%M')}</p>
</body>
</html>
"""
        write_file(index_file, page)
        run(f"chown {USER}:{USER} {index_file}")
        ok(f"Page : {index_file}")
    else:
        info(f"Page {index_file} existe deja")

    # Ajouter dans /etc/hosts du serveur
    hosts_file = "/etc/hosts"
    if not file_contains(hosts_file, f"www.{domain}"):
        append_to_file(hosts_file, f"127.0.0.1  www.{domain} {domain}\n")
        ok(f"www.{domain} ajoute dans /etc/hosts")
    else:
        info(f"www.{domain} deja dans /etc/hosts")

    return True


# =============================================================
# REDEMARRAGE DES SERVICES
# =============================================================

def restart_services(dry_run=False):
    """Redemarre tous les services concernes."""
    print(f"\n{BOLD}>>> Redemarrage des services{NC}")

    if dry_run:
        info("[DRY-RUN] Redemarrerait apache2, bind9, postfix")
        return

    services = [
        ("apache2", "apache2ctl configtest"),
        ("bind9", "named-checkconf"),
        ("postfix", None),
    ]

    for service, check_cmd in services:
        # Verifier la config avant de redemarrer
        if check_cmd:
            success, output = run(check_cmd, check=False)
            if not success:
                fail(f"Erreur config {service} : {output}")
                continue

        success, _ = run(f"systemctl restart {service}", check=False)
        if success:
            ok(f"{service} redemarre")
        else:
            # Essayer avec le nom alternatif pour bind9
            if service == "bind9":
                run("systemctl restart named", check=False)
                ok(f"named redemarre")
            else:
                fail(f"Echec redemarrage {service}")


# =============================================================
# SUPPRESSION D'UN DOMAINE
# =============================================================

def remove_domain(domain, dry_run=False):
    """Supprime un domaine du serveur."""
    print(f"\n{BOLD}========================================")
    print(f" Suppression du domaine : {domain}")
    print(f"========================================{NC}")

    if dry_run:
        info(f"[DRY-RUN] Simulation de suppression de {domain}")

    # Apache
    print(f"\n{BOLD}>>> Apache{NC}")
    for suffix in ["", "-ssl"]:
        conf = f"/etc/apache2/sites-available/{domain}{suffix}.conf"
        if os.path.exists(conf):
            if not dry_run:
                run(f"a2dissite {domain}{suffix}.conf", check=False)
                os.remove(conf)
            fix(f"Supprime : {conf}")

    # DNS
    print(f"\n{BOLD}>>> DNS{NC}")
    zone_file = f"/etc/bind/db.{domain}"
    if os.path.exists(zone_file):
        if not dry_run:
            os.remove(zone_file)
        fix(f"Supprime : {zone_file}")

    named_conf = "/etc/bind/named.conf.local"
    if file_contains(named_conf, f'zone "{domain}"'):
        if not dry_run:
            # Supprimer le bloc zone du fichier
            with open(named_conf, "r") as f:
                lines = f.readlines()
            with open(named_conf, "w") as f:
                skip = False
                for line in lines:
                    if f'zone "{domain}"' in line:
                        skip = True
                        continue
                    if skip and "};" in line:
                        skip = False
                        continue
                    if not skip:
                        f.write(line)
        fix(f"Zone {domain} supprimee de named.conf.local")

    # Mail
    print(f"\n{BOLD}>>> Mail{NC}")
    success, mydest = run("postconf -h mydestination", check=False)
    if domain in mydest:
        if not dry_run:
            new_mydest = ", ".join([d.strip() for d in mydest.split(",") if domain not in d])
            run(f'postconf -e "mydestination = {new_mydest}"')
        fix(f"{domain} supprime de mydestination")

    # /etc/hosts
    print(f"\n{BOLD}>>> /etc/hosts{NC}")
    if file_contains("/etc/hosts", domain):
        if not dry_run:
            run(f"sed -i '/{domain}/d' /etc/hosts")
        fix(f"{domain} supprime de /etc/hosts")

    # BDD
    print(f"\n{BOLD}>>> Base de donnees{NC}")
    db_name = domain.replace(".", "_").replace("-", "_")
    success, output = run(
        f"sudo -u postgres psql -tAc \"SELECT 1 FROM pg_database WHERE datname='{db_name}'\"",
        check=False
    )
    if "1" in output:
        if not dry_run:
            run(f"sudo -u postgres psql -c \"DROP DATABASE {db_name};\"", check=False)
        fix(f"Base '{db_name}' supprimee")
    else:
        info(f"Base '{db_name}' n'existait pas")

    if not dry_run:
        restart_services()

    print(f"\n{BOLD}==========================================")
    print(f" {domain} supprime du serveur")
    print(f"=========================================={NC}")


# =============================================================
# LISTER LES DOMAINES
# =============================================================

def list_domains():
    """Liste tous les domaines configures sur le serveur."""
    print(f"\n{BOLD}==========================================")
    print(f" Domaines configures sur le serveur")
    print(f"=========================================={NC}")

    # Apache
    print(f"\n{BOLD}>>> VirtualHosts Apache (HTTP){NC}")
    success, output = run("ls /etc/apache2/sites-available/*.conf 2>/dev/null", check=False)
    if output:
        for conf in output.split("\n"):
            name = os.path.basename(conf).replace(".conf", "")
            if "-ssl" not in name:
                enabled = os.path.exists(f"/etc/apache2/sites-enabled/{os.path.basename(conf)}")
                status = f"{GREEN}actif{NC}" if enabled else f"{RED}inactif{NC}"
                print(f"  {CYAN}{name}{NC} [{status}]")

    # DNS
    print(f"\n{BOLD}>>> Zones DNS{NC}")
    success, output = run("ls /etc/bind/db.* 2>/dev/null", check=False)
    if output:
        for zone in output.split("\n"):
            name = os.path.basename(zone).replace("db.", "")
            if name not in ["local", "127", "0", "255", "empty", "root"]:
                print(f"  {CYAN}{name}{NC}")

    # Postfix mydestination
    print(f"\n{BOLD}>>> Postfix mydestination{NC}")
    success, mydest = run("postconf -h mydestination", check=False)
    if mydest:
        for d in mydest.split(","):
            d = d.strip()
            if d:
                print(f"  {CYAN}{d}{NC}")

    # BDD
    print(f"\n{BOLD}>>> Bases PostgreSQL{NC}")
    success, output = run(
        "sudo -u postgres psql -tAc \"SELECT datname FROM pg_database WHERE datistemplate=false ORDER BY datname;\"",
        check=False
    )
    if output:
        for db in output.split("\n"):
            db = db.strip()
            if db and db != "postgres":
                print(f"  {CYAN}{db}{NC}")


# =============================================================
# FONCTION PRINCIPALE
# =============================================================

def add_domain(domain, dry_run=False):
    """Ajoute un nouveau domaine complet sur le serveur."""
    print(f"\n{BOLD}==========================================")
    print(f" Ajout du domaine : {domain}")
    if dry_run:
        print(f" MODE SIMULATION (dry-run)")
    print(f"=========================================={NC}")

    # Verifier que le domaine n'existe pas deja
    if os.path.exists(f"/etc/apache2/sites-available/{domain}.conf"):
        fail(f"Le domaine {domain} existe deja !")
        info("Utilisez --remove pour le supprimer d'abord")
        return False

    # Executer toutes les etapes
    create_apache_vhost(domain, dry_run)
    create_dns_zone(domain, dry_run)
    create_mail(domain, dry_run)
    create_database(domain, dry_run)
    create_web_dir(domain, dry_run)

    if not dry_run:
        restart_services()

    # Resume
    print(f"\n{BOLD}==========================================")
    if dry_run:
        print(f" [DRY-RUN] Simulation terminee pour {domain}")
    else:
        print(f" {GREEN}Domaine {domain} ajoute avec succes !{NC}")
    print(f"=========================================={NC}")
    print()
    print(f"  URL HTTP  : {CYAN}http://www.{domain}{NC}")
    print(f"  URL HTTPS : {CYAN}https://www.{domain}{NC}")
    print(f"  Mail      : {CYAN}contact@{domain}{NC}")
    print(f"  BDD       : {CYAN}{domain.replace('.', '_').replace('-', '_')}{NC}")
    print()
    print(f"  Sur le CLIENT, ajouter dans /etc/hosts :")
    print(f"  {CYAN}{SERVER_IP}  www.{domain}{NC}")
    print(f"{BOLD}=========================================={NC}")

    return True


# =============================================================
# MAIN
# =============================================================

if __name__ == "__main__":
    # Verifier root
    if os.geteuid() != 0:
        print(f"{RED}Ce script doit etre execute en root (sudo){NC}")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="SAE S203 - Ajout automatique de domaine",
        epilog="Exemples:\n"
               "  sudo python3 ajouter_domaine.py monsite.org\n"
               "  sudo python3 ajouter_domaine.py monsite.org --dry-run\n"
               "  sudo python3 ajouter_domaine.py --list\n"
               "  sudo python3 ajouter_domaine.py monsite.org --remove\n",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("domain", nargs="?", help="Nom de domaine a ajouter")
    parser.add_argument("--dry-run", action="store_true", help="Simulation sans modification")
    parser.add_argument("--remove", action="store_true", help="Supprimer le domaine")
    parser.add_argument("--list", action="store_true", help="Lister les domaines configures")

    args = parser.parse_args()

    if args.list:
        list_domains()
        sys.exit(0)

    if not args.domain:
        parser.print_help()
        sys.exit(1)

    domain = args.domain.lower().strip()

    # Validation basique du nom de domaine
    if "." not in domain or len(domain) < 4:
        print(f"{RED}Nom de domaine invalide : {domain}{NC}")
        print("Exemple : monsite.org, test.fr, example.com")
        sys.exit(1)

    if args.remove:
        remove_domain(domain, args.dry_run)
    else:
        add_domain(domain, args.dry_run)

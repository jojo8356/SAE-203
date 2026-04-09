#!/bin/bash

# Fix terminal inconnu (xterm-kitty via SSH)
case "$TERM" in
    xterm-kitty|*-kitty) export TERM=xterm-256color ;;
esac

# =============================================================
# test_phase4_SERVER.sh - Verification Phase 4 : SGBD PostgreSQL
# Aucune creation, uniquement des verifications
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DB_USER="exemple"
DB_PASS="but1"
DB_NAME="carte_grise"
DOMAIN="exemple.com"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 4 - Verification SGBD (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 4.1 PostgreSQL installe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.1 PostgreSQL installe${NC}"

for pkg in postgresql postgresql-contrib php-pgsql; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg installe"
    else
        fail "$pkg NON installe"
    fi
done

# Service actif ?
if systemctl is-active --quiet postgresql; then
    ok "PostgreSQL est actif"
else
    fail "PostgreSQL n'est PAS actif"
fi

# Active au demarrage ?
if systemctl is-enabled --quiet postgresql; then
    ok "PostgreSQL active au demarrage"
else
    fail "PostgreSQL PAS active au demarrage"
fi

# Port 5432 ?
if ss -tlnp 2>/dev/null | grep -q ":5432 "; then
    ok "Port 5432 en ecoute"
else
    fail "Port 5432 PAS en ecoute"
fi

# Version
PG_VER=$(psql --version 2>/dev/null | awk '{print $3}')
if [ -n "$PG_VER" ]; then
    info "Version PostgreSQL : $PG_VER"
fi

# =============================================================
# 4.2 Securisation / Configuration
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.2 Configuration PostgreSQL${NC}"

# pg_hba.conf : authentification md5 ?
PG_HBA=$(find /etc/postgresql -name "pg_hba.conf" 2>/dev/null | head -1)
if [ -n "$PG_HBA" ]; then
    ok "pg_hba.conf trouve : $PG_HBA"
    if grep -qE "^local.*all.*all.*md5|^local.*all.*all.*scram" "$PG_HBA" 2>/dev/null; then
        ok "Authentification par mot de passe (md5/scram) configuree"
    elif grep -qE "^local.*all.*all.*peer" "$PG_HBA" 2>/dev/null; then
        warn "Authentification 'peer' (pas md5). PHP pourrait ne pas se connecter"
    fi
else
    fail "pg_hba.conf introuvable"
fi

# postgresql.conf : listen_addresses ?
PG_CONF=$(find /etc/postgresql -name "postgresql.conf" 2>/dev/null | head -1)
if [ -n "$PG_CONF" ]; then
    LISTEN=$(grep "^listen_addresses" "$PG_CONF" 2>/dev/null | awk -F"'" '{print $2}')
    if [ -n "$LISTEN" ]; then
        info "listen_addresses = $LISTEN"
    else
        info "listen_addresses = localhost (par defaut)"
    fi
fi

# =============================================================
# 4.3 Utilisateur "exemple" existe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.3 Utilisateur PostgreSQL '$DB_USER'${NC}"

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" 2>/dev/null | grep -q 1; then
    ok "Utilisateur '$DB_USER' existe dans PostgreSQL"
else
    fail "Utilisateur '$DB_USER' N'EXISTE PAS dans PostgreSQL"
fi

# Test connexion avec mot de passe
if PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d postgres -tAc "SELECT 1;" 2>/dev/null | grep -q 1; then
    ok "Connexion avec $DB_USER/$DB_PASS fonctionne"
else
    warn "Connexion avec mot de passe echouee (peut etre normal si auth=peer)"
fi

# =============================================================
# 4.4 Base de donnees "carte_grise" existe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.4 Base de donnees '$DB_NAME'${NC}"

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null | grep -q 1; then
    ok "Base '$DB_NAME' existe"
else
    fail "Base '$DB_NAME' N'EXISTE PAS"
fi

# Proprietaire de la base ?
OWNER=$(sudo -u postgres psql -tAc "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname='$DB_NAME'" 2>/dev/null | tr -d ' ')
if [ "$OWNER" = "$DB_USER" ]; then
    ok "Proprietaire de '$DB_NAME' : $DB_USER"
elif [ -n "$OWNER" ]; then
    warn "Proprietaire de '$DB_NAME' : $OWNER (attendu: $DB_USER)"
fi

# =============================================================
# 4.4 Tables dans carte_grise ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.4 Tables dans '$DB_NAME'${NC}"

TABLES=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;" 2>/dev/null)

if [ -n "$TABLES" ]; then
    for table in $TABLES; do
        ok "Table '$table' existe"
    done
else
    fail "Aucune table trouvee dans '$DB_NAME'"
fi

# Tables attendues
for expected in proprietaire vehicule rappel_envoye; do
    if echo "$TABLES" | grep -q "$expected"; then
        ok "Table attendue '$expected' presente"
    else
        fail "Table attendue '$expected' MANQUANTE"
    fi
done

# Structure des tables
echo ""
echo -e "${BOLD}>>> 4.4 Structure des tables${NC}"

# Colonnes de proprietaire
COLS_PROP=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT column_name FROM information_schema.columns WHERE table_name='proprietaire' ORDER BY ordinal_position;" 2>/dev/null)
if [ -n "$COLS_PROP" ]; then
    info "Colonnes proprietaire : $(echo $COLS_PROP | tr '\n' ', ')"
    for col in id civilite nom prenom email; do
        echo "$COLS_PROP" | grep -q "$col" && ok "proprietaire.$col existe" || fail "proprietaire.$col MANQUANT"
    done
fi

# Colonnes de vehicule
COLS_VEH=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT column_name FROM information_schema.columns WHERE table_name='vehicule' ORDER BY ordinal_position;" 2>/dev/null)
if [ -n "$COLS_VEH" ]; then
    info "Colonnes vehicule : $(echo $COLS_VEH | tr '\n' ', ')"
    for col in id proprietaire_id immatriculation marque modele annee; do
        echo "$COLS_VEH" | grep -q "$col" && ok "vehicule.$col existe" || fail "vehicule.$col MANQUANT"
    done
fi

# Donnees de test ?
echo ""
echo -e "${BOLD}>>> 4.4 Donnees dans les tables${NC}"

NB_PROP=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM proprietaire;" 2>/dev/null | tr -d ' ')
NB_VEH=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM vehicule;" 2>/dev/null | tr -d ' ')
NB_RAP=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM rappel_envoye;" 2>/dev/null | tr -d ' ')

if [ -n "$NB_PROP" ] && [ "$NB_PROP" -gt 0 ] 2>/dev/null; then
    ok "proprietaire : $NB_PROP enregistrement(s)"
else
    warn "proprietaire : vide (pas de donnees de test)"
fi

if [ -n "$NB_VEH" ] && [ "$NB_VEH" -gt 0 ] 2>/dev/null; then
    ok "vehicule : $NB_VEH enregistrement(s)"
else
    warn "vehicule : vide (pas de donnees de test)"
fi

info "rappel_envoye : ${NB_RAP:-0} enregistrement(s)"

# Droits de l'utilisateur exemple sur les tables ?
echo ""
echo -e "${BOLD}>>> 4.4 Droits de '$DB_USER' sur les tables${NC}"

for table in proprietaire vehicule rappel_envoye; do
    HAS_GRANT=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT has_table_privilege('$DB_USER', '$table', 'SELECT');" 2>/dev/null | tr -d ' ')
    if [ "$HAS_GRANT" = "t" ]; then
        ok "$DB_USER a les droits sur '$table'"
    else
        fail "$DB_USER n'a PAS les droits sur '$table'"
    fi
done

# =============================================================
# 4.5 phpPgAdmin installe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.5 phpPgAdmin${NC}"

if dpkg -l phppgadmin 2>/dev/null | grep -q "^ii"; then
    ok "phppgadmin installe"
else
    fail "phppgadmin NON installe"
fi

# Config Apache pour phpPgAdmin ?
if [ -f /etc/apache2/conf-available/phppgadmin.conf ] || [ -f /etc/apache2/conf-enabled/phppgadmin.conf ]; then
    ok "phpPgAdmin configure dans Apache"
else
    if [ -f /etc/phppgadmin/apache.conf ]; then
        warn "Config phpPgAdmin existe mais pas liee a Apache"
    else
        fail "Config phpPgAdmin introuvable"
    fi
fi

# Acces distant autorise ?
for pgaconf in /etc/apache2/conf-available/phppgadmin.conf /etc/apache2/conf-enabled/phppgadmin.conf /etc/phppgadmin/apache.conf; do
    if [ -f "$pgaconf" ]; then
        if grep -q "Require all granted" "$pgaconf" 2>/dev/null; then
            ok "Acces distant autorise dans phpPgAdmin"
        elif grep -q "Require local" "$pgaconf" 2>/dev/null; then
            warn "phpPgAdmin restreint a localhost (Require local)"
        fi
        break
    fi
done

# =============================================================
# 4.6 phpPgAdmin accessible via Apache ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.6 phpPgAdmin accessible${NC}"

PGA_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost/phppgadmin/" 2>/dev/null)
if [ "$PGA_CODE" = "200" ] || [ "$PGA_CODE" = "301" ] || [ "$PGA_CODE" = "302" ]; then
    ok "phpPgAdmin accessible (HTTP $PGA_CODE)"
else
    fail "phpPgAdmin inaccessible (HTTP $PGA_CODE)"
fi

# =============================================================
# 4.7 Connexion PHP -> PostgreSQL fonctionne ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 4.7 Connexion PHP -> PostgreSQL${NC}"

if command -v php &>/dev/null; then
    PHP_TEST=$(php -r "
        \$conn = @pg_connect('host=localhost dbname=$DB_NAME user=$DB_USER password=$DB_PASS');
        if (\$conn) { echo 'OK'; pg_close(\$conn); } else { echo 'FAIL'; }
    " 2>/dev/null)

    if [ "$PHP_TEST" = "OK" ]; then
        ok "PHP pg_connect() vers $DB_NAME fonctionne"
    else
        fail "PHP pg_connect() vers $DB_NAME echoue"
    fi

    # Module php-pgsql charge ?
    if php -m 2>/dev/null | grep -qi "pgsql"; then
        ok "Module PHP pgsql charge"
    else
        fail "Module PHP pgsql PAS charge"
    fi
else
    fail "PHP non installe"
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 4 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 4 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

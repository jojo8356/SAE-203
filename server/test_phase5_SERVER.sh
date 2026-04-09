#!/bin/bash

# =============================================================
# test_phase5_SERVER.sh - Verification Phase 5 : PHP & Application
# Aucune creation, uniquement des verifications
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DOMAIN="exemple.com"
USER="exemple"
WWW_DIR="/users/firms/exemple/www"
DB_NAME="carte_grise"
DB_USER="exemple"
DB_PASS="but1"

PASS=0
FAIL=0

ok()   { echo -e "  ${GREEN}[OK]${NC}   $1"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " Phase 5 - Verification PHP & App (SERVEUR)"
echo -e "==========================================${NC}"

# =============================================================
# 5.1 PHP installe ?
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.1 PHP installe${NC}"

for pkg in php libapache2-mod-php php-pgsql; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg installe"
    else
        fail "$pkg NON installe"
    fi
done

# Version PHP
PHP_VER=$(php -v 2>/dev/null | head -1)
if [ -n "$PHP_VER" ]; then
    info "$PHP_VER"
else
    fail "PHP non disponible en CLI"
fi

# Module PHP pgsql charge ?
if php -m 2>/dev/null | grep -qi "^pgsql$"; then
    ok "Module PHP pgsql charge"
else
    fail "Module PHP pgsql PAS charge"
fi

# Module Apache PHP actif ?
if sudo a2query -m 2>/dev/null | grep -q "php"; then
    ok "Module Apache PHP actif"
else
    fail "Module Apache PHP PAS actif"
fi

# =============================================================
# 5.2 Fichiers PHP dans le DocumentRoot
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.2 Fichiers PHP dans $WWW_DIR${NC}"

# index.php existe ?
if [ -f "$WWW_DIR/index.php" ]; then
    ok "index.php existe"
else
    fail "index.php MANQUANT"
fi

# db.php (connexion BDD)
if [ -f "$WWW_DIR/db.php" ]; then
    ok "db.php existe"
    if grep -q "pg_connect" "$WWW_DIR/db.php" 2>/dev/null; then
        ok "db.php contient pg_connect()"
    else
        fail "db.php ne contient pas pg_connect()"
    fi
    if grep -q "$DB_NAME" "$WWW_DIR/db.php" 2>/dev/null; then
        ok "db.php reference la base '$DB_NAME'"
    else
        fail "db.php ne reference pas '$DB_NAME'"
    fi
else
    fail "db.php MANQUANT (connexion BDD)"
fi

# style.php (template)
if [ -f "$WWW_DIR/style.php" ]; then
    ok "style.php existe"
else
    warn "style.php manquant (template CSS)"
fi

# =============================================================
# 5.2 PHP fonctionne via Apache (test local)
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.2 PHP fonctionne via Apache${NC}"

INDEX_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost/index.php" 2>/dev/null)
if [ "$INDEX_CODE" = "200" ]; then
    ok "index.php accessible (HTTP $INDEX_CODE)"
else
    fail "index.php inaccessible (HTTP $INDEX_CODE)"
fi

# Verifier que PHP est interprete (pas affiche en texte brut)
INDEX_BODY=$(curl -s --max-time 5 "http://localhost/index.php" 2>/dev/null)
if echo "$INDEX_BODY" | grep -q "<?php"; then
    fail "PHP n'est PAS interprete (code source affiche)"
else
    ok "PHP est bien interprete par Apache"
fi

# =============================================================
# 5.4 Base de donnees carte_grise
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.4 Base de donnees carte_grise${NC}"

# 5.4.1 + 5.4.2 Tables existent ?
for table in proprietaire vehicule rappel_envoye; do
    EXISTS=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='$table';" 2>/dev/null | tr -d ' ')
    if [ "$EXISTS" = "1" ]; then
        ok "Table '$table' existe"
    else
        fail "Table '$table' MANQUANTE"
    fi
done

# Colonnes cles
echo ""
info "Verification des colonnes cles :"

# proprietaire
for col in id civilite nom prenom email adresse telephone; do
    EXISTS=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM information_schema.columns WHERE table_name='proprietaire' AND column_name='$col';" 2>/dev/null | tr -d ' ')
    [ "$EXISTS" = "1" ] && ok "proprietaire.$col" || fail "proprietaire.$col MANQUANT"
done

# vehicule
for col in id proprietaire_id immatriculation marque modele annee date_controle_technique document_path; do
    EXISTS=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM information_schema.columns WHERE table_name='vehicule' AND column_name='$col';" 2>/dev/null | tr -d ' ')
    [ "$EXISTS" = "1" ] && ok "vehicule.$col" || fail "vehicule.$col MANQUANT"
done

# Cle etrangere vehicule -> proprietaire ?
FK=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM information_schema.table_constraints WHERE table_name='vehicule' AND constraint_type='FOREIGN KEY';" 2>/dev/null | tr -d ' ')
if [ "$FK" = "1" ]; then
    ok "Cle etrangere vehicule -> proprietaire"
else
    warn "Pas de cle etrangere detectee sur vehicule"
fi

# 5.4.3 Donnees de test ?
echo ""
echo -e "${BOLD}>>> 5.4.3 Donnees de test${NC}"

NB_PROP=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM proprietaire;" 2>/dev/null | tr -d ' ')
NB_VEH=$(sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM vehicule;" 2>/dev/null | tr -d ' ')

[ -n "$NB_PROP" ] && [ "$NB_PROP" -gt 0 ] 2>/dev/null && ok "proprietaire : $NB_PROP enregistrement(s)" || warn "proprietaire : vide"
[ -n "$NB_VEH" ] && [ "$NB_VEH" -gt 0 ] 2>/dev/null && ok "vehicule : $NB_VEH enregistrement(s)" || warn "vehicule : vide"

# =============================================================
# 5.5 Pages de l'application PHP
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5 Pages de l'application PHP${NC}"

# 5.5.1 Connexion BDD (db.php)
info "5.5.1 Connexion BDD"
PHP_CONN=$(php -r "
    \$conn = @pg_connect('host=localhost dbname=$DB_NAME user=$DB_USER password=$DB_PASS');
    if (\$conn) { echo 'OK'; pg_close(\$conn); } else { echo 'FAIL'; }
" 2>/dev/null)
[ "$PHP_CONN" = "OK" ] && ok "PHP pg_connect() fonctionne" || fail "PHP pg_connect() echoue"

# 5.5.2 Page de visualisation (SELECT) - proprietaires.php
info "5.5.2 Visualisation (SELECT)"
if [ -f "$WWW_DIR/proprietaires.php" ]; then
    ok "proprietaires.php existe"
    grep -q "SELECT" "$WWW_DIR/proprietaires.php" 2>/dev/null && ok "proprietaires.php contient SELECT" || fail "pas de SELECT dans proprietaires.php"
else
    fail "proprietaires.php MANQUANT"
fi

if [ -f "$WWW_DIR/vehicules.php" ]; then
    ok "vehicules.php existe"
    grep -q "SELECT" "$WWW_DIR/vehicules.php" 2>/dev/null && ok "vehicules.php contient SELECT" || fail "pas de SELECT dans vehicules.php"
else
    fail "vehicules.php MANQUANT"
fi

# 5.5.3 Page d'ajout (INSERT) - ajouter_proprietaire.php, ajouter_vehicule.php
info "5.5.3 Ajout (INSERT)"
for page in ajouter_proprietaire.php ajouter_vehicule.php; do
    if [ -f "$WWW_DIR/$page" ]; then
        ok "$page existe"
        grep -q "INSERT" "$WWW_DIR/$page" 2>/dev/null && ok "$page contient INSERT" || fail "pas d'INSERT dans $page"
        grep -qi "form" "$WWW_DIR/$page" 2>/dev/null && ok "$page contient un formulaire" || fail "pas de formulaire dans $page"
    else
        fail "$page MANQUANT"
    fi
done

# 5.5.4 Page de mise a jour (UPDATE) - modifier_proprietaire.php, modifier_vehicule.php
info "5.5.4 Mise a jour (UPDATE)"
for page in modifier_proprietaire.php modifier_vehicule.php; do
    if [ -f "$WWW_DIR/$page" ]; then
        ok "$page existe"
        grep -q "UPDATE" "$WWW_DIR/$page" 2>/dev/null && ok "$page contient UPDATE" || fail "pas d'UPDATE dans $page"
    else
        fail "$page MANQUANT"
    fi
done

# 5.5.5 Page de suppression (DELETE) - supprimer.php
info "5.5.5 Suppression (DELETE)"
if [ -f "$WWW_DIR/supprimer.php" ]; then
    ok "supprimer.php existe"
    grep -q "DELETE" "$WWW_DIR/supprimer.php" 2>/dev/null && ok "supprimer.php contient DELETE" || fail "pas de DELETE dans supprimer.php"
else
    fail "supprimer.php MANQUANT"
fi

# 5.5.6 Upload de fichiers - upload.php
info "5.5.6 Upload de fichiers"
if [ -f "$WWW_DIR/upload.php" ]; then
    ok "upload.php existe"
    grep -q "move_uploaded_file" "$WWW_DIR/upload.php" 2>/dev/null && ok "upload.php contient move_uploaded_file()" || fail "pas de move_uploaded_file() dans upload.php"
    grep -q "enctype" "$WWW_DIR/upload.php" 2>/dev/null && ok "upload.php a enctype multipart/form-data" || fail "pas de enctype dans upload.php"
else
    fail "upload.php MANQUANT"
fi

# Dossier uploads existe ?
if [ -d "$WWW_DIR/uploads" ]; then
    ok "Dossier uploads/ existe"
    # Permissions ecriture ?
    if [ -w "$WWW_DIR/uploads" ]; then
        ok "Dossier uploads/ est accessible en ecriture"
    else
        fail "Dossier uploads/ PAS accessible en ecriture"
    fi
else
    fail "Dossier uploads/ MANQUANT"
fi

# Config PHP upload
echo ""
echo -e "${BOLD}>>> 5.5.6 Config PHP upload${NC}"
UPLOAD_MAX=$(php -i 2>/dev/null | grep "upload_max_filesize" | head -1 | awk '{print $NF}')
POST_MAX=$(php -i 2>/dev/null | grep "post_max_size" | head -1 | awk '{print $NF}')
info "upload_max_filesize = $UPLOAD_MAX"
info "post_max_size = $POST_MAX"

# =============================================================
# 5.5 (bonus) mail.php + cron_mail.php
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.5 Bonus : mail + cron${NC}"

if [ -f "$WWW_DIR/mail.php" ]; then
    ok "mail.php existe"
    grep -q "mail(" "$WWW_DIR/mail.php" 2>/dev/null && ok "mail.php contient mail()" || warn "mail() non trouve dans mail.php"
else
    warn "mail.php manquant"
fi

if [ -f "$WWW_DIR/cron_mail.php" ]; then
    ok "cron_mail.php existe"
else
    warn "cron_mail.php manquant"
fi

# Cron configure ?
CRON=$(crontab -u "$USER" -l 2>/dev/null | grep "cron_mail.php")
if [ -n "$CRON" ]; then
    ok "Cron configure : $CRON"
else
    warn "Cron pour cron_mail.php non configure"
fi

# =============================================================
# 5.6 Test CRUD via HTTP (serveur local)
# =============================================================
echo ""
echo -e "${BOLD}>>> 5.6 Test CRUD via HTTP (localhost)${NC}"

# Liste des pages qui doivent repondre 200
for page in index.php proprietaires.php vehicules.php ajouter_proprietaire.php ajouter_vehicule.php upload.php mail.php; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost/$page" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        ok "http://localhost/$page -> $CODE"
    else
        fail "http://localhost/$page -> $CODE"
    fi
done

# Verifier que les pages ne contiennent pas d'erreur PHP
for page in index.php proprietaires.php vehicules.php; do
    BODY=$(curl -s --max-time 5 "http://localhost/$page" 2>/dev/null)
    if echo "$BODY" | grep -qi "fatal error\|parse error\|warning.*pg_\|erreur.*connexion"; then
        fail "$page contient une erreur PHP/BDD"
    else
        ok "$page sans erreur PHP/BDD"
    fi
done

# =============================================================
# Liste des fichiers PHP
# =============================================================
echo ""
echo -e "${BOLD}>>> Recap : fichiers dans $WWW_DIR${NC}"
if [ -d "$WWW_DIR" ]; then
    for f in $(find "$WWW_DIR" -maxdepth 1 -name "*.php" -o -name "*.html" 2>/dev/null | sort); do
        info "$(basename $f)"
    done
fi

# =============================================================
# RESUME
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e " ${GREEN}Phase 5 SERVEUR : $PASS/$TOTAL tests OK${NC}"
else
    echo -e " ${RED}Phase 5 SERVEUR : $PASS/$TOTAL tests OK, $FAIL ECHECS${NC}"
fi
echo -e "==========================================${NC}"

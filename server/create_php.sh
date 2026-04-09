#!/bin/bash

# =============================================================
# create_php.sh - SAE S203 - Création de l'application PHP
# Carte Grise - PostgreSQL + Upload + Mail + Cron
# =============================================================

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en root (sudo ./create_php.sh)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DOMAIN="exemple.com"
USER="exemple"
USER_HOME="/users/firms/exemple"
WWW_DIR="$USER_HOME/www"
UPLOAD_DIR="$WWW_DIR/uploads"
DB_NAME="carte_grise"
DB_USER="exemple"
DB_PASS="but1"

ok()  { echo -e "  ${GREEN}[OK]${NC} $1"; }
fix() { echo -e "  ${YELLOW}[FIX]${NC} $1"; }
info() { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo ""
echo -e "${BOLD}=========================================="
echo " SAE S203 - Application Carte Grise"
echo -e "==========================================${NC}"

# =============================================================
# 1. INSTALLATION POSTGRESQL
# =============================================================
echo ""
echo -e "${BOLD}>>> 1. Installation de PostgreSQL${NC}"

for pkg in postgresql postgresql-contrib php-pgsql; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg déjà installé"
    else
        fix "Installation de $pkg..."
        apt-get install -y "$pkg" >/dev/null 2>&1
        ok "$pkg installé"
    fi
done

systemctl enable postgresql >/dev/null 2>&1
systemctl start postgresql

# Vérifier que PostgreSQL tourne
if systemctl is-active --quiet postgresql; then
    ok "PostgreSQL actif"
else
    echo -e "  ${RED}[FAIL]${NC} PostgreSQL ne démarre pas"
    exit 1
fi

# =============================================================
# 2. CRÉATION DE LA BDD ET DES TABLES
# =============================================================
echo ""
echo -e "${BOLD}>>> 2. Création de la base de données${NC}"

# Créer l'utilisateur PostgreSQL
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'\"" | grep -q 1
if [ $? -ne 0 ]; then
    fix "Création de l'utilisateur PostgreSQL '$DB_USER'..."
    su - postgres -c "psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';\""
else
    ok "Utilisateur PostgreSQL '$DB_USER' existe"
fi

# Créer la base de données
su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\"" | grep -q 1
if [ $? -ne 0 ]; then
    fix "Création de la base '$DB_NAME'..."
    su - postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\""
else
    ok "Base '$DB_NAME' existe"
fi

# Donner les droits
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;\""

# Créer les tables
info "Création des tables..."
su - postgres -c "psql -d $DB_NAME" <<'SQL'
-- Table des propriétaires
CREATE TABLE IF NOT EXISTS proprietaire (
    id SERIAL PRIMARY KEY,
    civilite VARCHAR(5) NOT NULL,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    email VARCHAR(200) NOT NULL,
    adresse TEXT,
    telephone VARCHAR(20),
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table des véhicules
CREATE TABLE IF NOT EXISTS vehicule (
    id SERIAL PRIMARY KEY,
    proprietaire_id INTEGER REFERENCES proprietaire(id) ON DELETE CASCADE,
    immatriculation VARCHAR(20) NOT NULL UNIQUE,
    marque VARCHAR(50) NOT NULL,
    modele VARCHAR(50) NOT NULL,
    annee INTEGER NOT NULL,
    date_mise_circulation DATE,
    date_controle_technique DATE,
    document_path VARCHAR(500),
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table des rappels envoyés
CREATE TABLE IF NOT EXISTS rappel_envoye (
    id SERIAL PRIMARY KEY,
    vehicule_id INTEGER REFERENCES vehicule(id) ON DELETE CASCADE,
    date_envoi TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    type_rappel VARCHAR(50) DEFAULT 'controle_technique'
);

-- Donner les droits sur les tables et séquences
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO exemple;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO exemple;

-- Insérer des données de test
INSERT INTO proprietaire (civilite, nom, prenom, email, adresse, telephone)
SELECT 'M.', 'Dupont', 'Jean', 'jean.dupont@exemple.com', '12 rue de Nice, 06000 Nice', '0612345678'
WHERE NOT EXISTS (SELECT 1 FROM proprietaire WHERE email = 'jean.dupont@exemple.com');

INSERT INTO proprietaire (civilite, nom, prenom, email, adresse, telephone)
SELECT 'Mme', 'Martin', 'Sophie', 'sophie.martin@exemple.com', '8 avenue de la Gare, 06200 Nice', '0698765432'
WHERE NOT EXISTS (SELECT 1 FROM proprietaire WHERE email = 'sophie.martin@exemple.com');

INSERT INTO vehicule (proprietaire_id, immatriculation, marque, modele, annee, date_mise_circulation, date_controle_technique)
SELECT p.id, 'AB-123-CD', 'Renault', 'Clio', 2019, '2019-03-15', CURRENT_DATE + INTERVAL '25 days'
FROM proprietaire p WHERE p.email = 'jean.dupont@exemple.com'
AND NOT EXISTS (SELECT 1 FROM vehicule WHERE immatriculation = 'AB-123-CD');

INSERT INTO vehicule (proprietaire_id, immatriculation, marque, modele, annee, date_mise_circulation, date_controle_technique)
SELECT p.id, 'EF-456-GH', 'Peugeot', '308', 2021, '2021-06-10', CURRENT_DATE + INTERVAL '60 days'
FROM proprietaire p WHERE p.email = 'sophie.martin@exemple.com'
AND NOT EXISTS (SELECT 1 FROM vehicule WHERE immatriculation = 'EF-456-GH');
SQL

ok "Tables créées (proprietaire, vehicule, rappel_envoye)"

# =============================================================
# 3. SUPPRESSION DES ANCIENS FICHIERS PHP
# =============================================================
echo ""
echo -e "${BOLD}>>> 3. Nettoyage des anciens fichiers PHP${NC}"

if [ -d "$WWW_DIR" ]; then
    OLD_FILES=$(find "$WWW_DIR" -maxdepth 1 -name "*.php" -o -name "*.html" 2>/dev/null)
    if [ -n "$OLD_FILES" ]; then
        for f in $OLD_FILES; do
            rm -f "$f"
            fix "Supprimé : $(basename $f)"
        done
    fi
else
    mkdir -p "$WWW_DIR"
fi

# Créer le dossier uploads
mkdir -p "$UPLOAD_DIR"
chown "$USER:$USER" "$UPLOAD_DIR"
chmod 755 "$UPLOAD_DIR"
ok "Dossier uploads créé"

# =============================================================
# 4. CRÉATION DES FICHIERS PHP
# =============================================================
echo ""
echo -e "${BOLD}>>> 4. Création des fichiers PHP${NC}"

# ---- db.php ----
cat > "$WWW_DIR/db.php" <<'PHPEOF'
<?php
function getConnection() {
    $conn = pg_connect("host=localhost dbname=carte_grise user=exemple password=but1");
    if (!$conn) {
        die("<div style='color:red;font-weight:bold;padding:20px;'>Erreur de connexion à la base de données.</div>");
    }
    return $conn;
}
?>
PHPEOF
ok "db.php"

# ---- style.php (CSS commun) ----
cat > "$WWW_DIR/style.php" <<'PHPEOF'
<?php function getHeader($title) { ?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($title) ?> - Carte Grise</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f2f5; color: #333; }
        .navbar {
            background: linear-gradient(135deg, #1a237e, #283593);
            padding: 15px 30px;
            display: flex; align-items: center; gap: 30px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        }
        .navbar a {
            color: white; text-decoration: none; padding: 8px 16px;
            border-radius: 5px; transition: background 0.3s;
        }
        .navbar a:hover, .navbar a.active { background: rgba(255,255,255,0.2); }
        .navbar .brand { font-size: 1.3em; font-weight: bold; margin-right: 20px; }
        .container { max-width: 1100px; margin: 30px auto; padding: 0 20px; }
        .card {
            background: white; border-radius: 10px; padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.08); margin-bottom: 20px;
        }
        h1 { color: #1a237e; margin-bottom: 20px; }
        h2 { color: #283593; margin-bottom: 15px; }
        table { border-collapse: collapse; width: 100%; margin-top: 15px; }
        th, td { border: 1px solid #e0e0e0; padding: 12px; text-align: left; }
        th { background: #1a237e; color: white; }
        tr:nth-child(even) { background: #f5f5f5; }
        tr:hover { background: #e8eaf6; }
        .btn {
            display: inline-block; padding: 10px 20px; border: none; border-radius: 5px;
            color: white; cursor: pointer; text-decoration: none; font-size: 14px;
            transition: opacity 0.3s;
        }
        .btn:hover { opacity: 0.85; }
        .btn-primary { background: #1a237e; }
        .btn-success { background: #2e7d32; }
        .btn-warning { background: #f57f17; }
        .btn-danger { background: #c62828; }
        .btn-info { background: #0277bd; }
        label { display: block; margin: 12px 0 5px; font-weight: 600; color: #444; }
        input[type=text], input[type=email], input[type=number], input[type=date],
        input[type=tel], input[type=time], select, textarea {
            padding: 10px; width: 100%; max-width: 400px; border: 1px solid #ccc;
            border-radius: 5px; font-size: 14px;
        }
        input[type=file] { margin: 10px 0; }
        .message { padding: 12px 20px; border-radius: 5px; margin-bottom: 20px; font-weight: 600; }
        .msg-success { background: #e8f5e9; color: #2e7d32; border: 1px solid #a5d6a7; }
        .msg-error { background: #ffebee; color: #c62828; border: 1px solid #ef9a9a; }
        .msg-info { background: #e3f2fd; color: #0277bd; border: 1px solid #90caf9; }
        .stats { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 20px; }
        .stat-box {
            background: white; border-radius: 10px; padding: 20px 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.08); text-align: center; flex: 1; min-width: 200px;
        }
        .stat-box .number { font-size: 2.5em; font-weight: bold; color: #1a237e; }
        .stat-box .label { color: #666; margin-top: 5px; }
        .grid-actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 20px; }
    </style>
</head>
<body>
<div class="navbar">
    <span class="brand">Carte Grise</span>
    <a href="index.php">Accueil</a>
    <a href="proprietaires.php">Proprietaires</a>
    <a href="vehicules.php">Vehicules</a>
    <a href="ajouter_proprietaire.php">+ Proprietaire</a>
    <a href="ajouter_vehicule.php">+ Vehicule</a>
    <a href="upload.php">Upload</a>
    <a href="mail.php">Rappels Mail</a>
</div>
<div class="container">
<?php } ?>

<?php function getFooter() { ?>
</div>
</body>
</html>
<?php } ?>
PHPEOF
ok "style.php"

# ---- index.php ----
cat > "$WWW_DIR/index.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();

$nb_prop = pg_fetch_result(pg_query($conn, "SELECT COUNT(*) FROM proprietaire"), 0, 0);
$nb_veh = pg_fetch_result(pg_query($conn, "SELECT COUNT(*) FROM vehicule"), 0, 0);
$nb_ct_proche = pg_fetch_result(pg_query($conn,
    "SELECT COUNT(*) FROM vehicule WHERE date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'"), 0, 0);
$nb_ct_depasse = pg_fetch_result(pg_query($conn,
    "SELECT COUNT(*) FROM vehicule WHERE date_controle_technique < CURRENT_DATE"), 0, 0);

getHeader('Accueil');
?>

<h1>Tableau de bord - Service Carte Grise</h1>

<div class="stats">
    <div class="stat-box">
        <div class="number"><?= $nb_prop ?></div>
        <div class="label">Proprietaires</div>
    </div>
    <div class="stat-box">
        <div class="number"><?= $nb_veh ?></div>
        <div class="label">Vehicules</div>
    </div>
    <div class="stat-box">
        <div class="number" style="color: #f57f17;"><?= $nb_ct_proche ?></div>
        <div class="label">CT dans les 30 jours</div>
    </div>
    <div class="stat-box">
        <div class="number" style="color: #c62828;"><?= $nb_ct_depasse ?></div>
        <div class="label">CT depasses</div>
    </div>
</div>

<div class="card">
    <h2>Vehicules avec controle technique a venir (30 jours)</h2>
    <?php
    $result = pg_query($conn,
        "SELECT v.*, p.nom, p.prenom, p.email
         FROM vehicule v
         JOIN proprietaire p ON v.proprietaire_id = p.id
         WHERE v.date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
         ORDER BY v.date_controle_technique");
    if (pg_num_rows($result) > 0): ?>
    <table>
        <tr><th>Immatriculation</th><th>Marque</th><th>Modele</th><th>Proprietaire</th><th>Email</th><th>Date CT</th><th>Jours restants</th></tr>
        <?php while ($row = pg_fetch_assoc($result)):
            $jours = (int)((strtotime($row['date_controle_technique']) - time()) / 86400);
        ?>
        <tr>
            <td><strong><?= htmlspecialchars($row['immatriculation']) ?></strong></td>
            <td><?= htmlspecialchars($row['marque']) ?></td>
            <td><?= htmlspecialchars($row['modele']) ?></td>
            <td><?= htmlspecialchars($row['prenom'] . ' ' . $row['nom']) ?></td>
            <td><?= htmlspecialchars($row['email']) ?></td>
            <td><?= $row['date_controle_technique'] ?></td>
            <td style="color: <?= $jours <= 7 ? '#c62828' : '#f57f17' ?>; font-weight:bold;"><?= $jours ?> j</td>
        </tr>
        <?php endwhile; ?>
    </table>
    <?php else: ?>
        <p>Aucun controle technique prevu dans les 30 prochains jours.</p>
    <?php endif; ?>
</div>

<div class="card">
    <h2>Actions rapides</h2>
    <div class="grid-actions">
        <a href="ajouter_proprietaire.php" class="btn btn-success">+ Ajouter un proprietaire</a>
        <a href="ajouter_vehicule.php" class="btn btn-primary">+ Ajouter un vehicule</a>
        <a href="proprietaires.php" class="btn btn-info">Voir les proprietaires</a>
        <a href="vehicules.php" class="btn btn-info">Voir les vehicules</a>
        <a href="upload.php" class="btn btn-warning">Uploader un document</a>
        <a href="mail.php" class="btn btn-danger">Envoyer des rappels</a>
    </div>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "index.php"

# ---- proprietaires.php (visualiser + recherche) ----
cat > "$WWW_DIR/proprietaires.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();

$recherche = isset($_GET['q']) ? trim($_GET['q']) : '';

if ($recherche !== '') {
    $result = pg_query_params($conn,
        "SELECT * FROM proprietaire WHERE nom ILIKE $1 OR prenom ILIKE $1 OR email ILIKE $1 ORDER BY id",
        array('%' . $recherche . '%'));
} else {
    $result = pg_query($conn, "SELECT * FROM proprietaire ORDER BY id");
}

getHeader('Proprietaires');
?>

<h1>Proprietaires</h1>
<div class="card">
    <form method="GET" style="margin-bottom:20px; display:flex; gap:10px; align-items:center;">
        <input type="text" name="q" placeholder="Rechercher par nom, prenom ou email..." value="<?= htmlspecialchars($recherche) ?>" style="flex:1;">
        <button type="submit" class="btn btn-primary">Rechercher</button>
        <?php if ($recherche !== ''): ?>
            <a href="proprietaires.php" class="btn btn-info">Tout voir</a>
        <?php endif; ?>
    </form>

    <table>
        <tr><th>ID</th><th>Civilite</th><th>Nom</th><th>Prenom</th><th>Email</th><th>Telephone</th><th>Actions</th></tr>
        <?php while ($row = pg_fetch_assoc($result)): ?>
        <tr>
            <td><?= $row['id'] ?></td>
            <td><?= htmlspecialchars($row['civilite']) ?></td>
            <td><?= htmlspecialchars($row['nom']) ?></td>
            <td><?= htmlspecialchars($row['prenom']) ?></td>
            <td><?= htmlspecialchars($row['email']) ?></td>
            <td><?= htmlspecialchars($row['telephone']) ?></td>
            <td>
                <a href="modifier_proprietaire.php?id=<?= $row['id'] ?>" class="btn btn-warning" style="padding:5px 10px;">Modifier</a>
                <a href="supprimer.php?type=proprietaire&id=<?= $row['id'] ?>" class="btn btn-danger" style="padding:5px 10px;" onclick="return confirm('Supprimer ce proprietaire et tous ses vehicules ?');">Supprimer</a>
            </td>
        </tr>
        <?php endwhile; ?>
    </table>
    <br>
    <a href="ajouter_proprietaire.php" class="btn btn-success">+ Ajouter un proprietaire</a>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "proprietaires.php"

# ---- vehicules.php (visualiser) ----
cat > "$WWW_DIR/vehicules.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();

$recherche = isset($_GET['q']) ? trim($_GET['q']) : '';

if ($recherche !== '') {
    $result = pg_query_params($conn,
        "SELECT v.*, p.nom, p.prenom, p.email
         FROM vehicule v JOIN proprietaire p ON v.proprietaire_id = p.id
         WHERE v.immatriculation ILIKE $1 OR v.marque ILIKE $1 OR v.modele ILIKE $1 OR p.nom ILIKE $1
         ORDER BY v.id",
        array('%' . $recherche . '%'));
} else {
    $result = pg_query($conn,
        "SELECT v.*, p.nom, p.prenom, p.email
         FROM vehicule v JOIN proprietaire p ON v.proprietaire_id = p.id ORDER BY v.id");
}

getHeader('Vehicules');
?>

<h1>Vehicules</h1>
<div class="card">
    <form method="GET" style="margin-bottom:20px; display:flex; gap:10px; align-items:center;">
        <input type="text" name="q" placeholder="Rechercher par immatriculation, marque, modele..." value="<?= htmlspecialchars($recherche) ?>" style="flex:1;">
        <button type="submit" class="btn btn-primary">Rechercher</button>
        <?php if ($recherche !== ''): ?>
            <a href="vehicules.php" class="btn btn-info">Tout voir</a>
        <?php endif; ?>
    </form>

    <table>
        <tr><th>Immatriculation</th><th>Marque</th><th>Modele</th><th>Annee</th><th>Proprietaire</th><th>Date CT</th><th>Document</th><th>Actions</th></tr>
        <?php while ($row = pg_fetch_assoc($result)):
            $ct_date = $row['date_controle_technique'];
            $ct_color = '';
            if ($ct_date) {
                $jours = (int)((strtotime($ct_date) - time()) / 86400);
                if ($jours < 0) $ct_color = 'color:#c62828;font-weight:bold;';
                elseif ($jours <= 30) $ct_color = 'color:#f57f17;font-weight:bold;';
            }
        ?>
        <tr>
            <td><strong><?= htmlspecialchars($row['immatriculation']) ?></strong></td>
            <td><?= htmlspecialchars($row['marque']) ?></td>
            <td><?= htmlspecialchars($row['modele']) ?></td>
            <td><?= $row['annee'] ?></td>
            <td><?= htmlspecialchars($row['prenom'] . ' ' . $row['nom']) ?></td>
            <td style="<?= $ct_color ?>"><?= $ct_date ?: 'Non renseigne' ?></td>
            <td>
                <?php if ($row['document_path']): ?>
                    <a href="<?= htmlspecialchars($row['document_path']) ?>" target="_blank" class="btn btn-info" style="padding:3px 8px;">Voir</a>
                <?php else: ?>
                    <a href="upload.php?vehicule_id=<?= $row['id'] ?>" style="color:#f57f17;">Uploader</a>
                <?php endif; ?>
            </td>
            <td>
                <a href="modifier_vehicule.php?id=<?= $row['id'] ?>" class="btn btn-warning" style="padding:5px 10px;">Modifier</a>
                <a href="supprimer.php?type=vehicule&id=<?= $row['id'] ?>" class="btn btn-danger" style="padding:5px 10px;" onclick="return confirm('Supprimer ce vehicule ?');">Supprimer</a>
            </td>
        </tr>
        <?php endwhile; ?>
    </table>
    <br>
    <a href="ajouter_vehicule.php" class="btn btn-success">+ Ajouter un vehicule</a>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "vehicules.php"

# ---- ajouter_proprietaire.php ----
cat > "$WWW_DIR/ajouter_proprietaire.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$message = '';
$msg_class = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $conn = getConnection();
    $civilite = trim($_POST['civilite']);
    $nom = trim($_POST['nom']);
    $prenom = trim($_POST['prenom']);
    $email = trim($_POST['email']);
    $adresse = trim($_POST['adresse']);
    $telephone = trim($_POST['telephone']);

    if ($nom && $prenom && $email && $civilite) {
        $result = pg_query_params($conn,
            "INSERT INTO proprietaire (civilite, nom, prenom, email, adresse, telephone) VALUES ($1,$2,$3,$4,$5,$6)",
            array($civilite, $nom, $prenom, $email, $adresse, $telephone));
        if ($result) {
            $message = "Proprietaire ajoute avec succes.";
            $msg_class = "msg-success";
        } else {
            $message = "Erreur lors de l'ajout.";
            $msg_class = "msg-error";
        }
    } else {
        $message = "Veuillez remplir tous les champs obligatoires.";
        $msg_class = "msg-error";
    }
    pg_close($conn);
}

getHeader('Ajouter un proprietaire');
?>

<h1>Ajouter un proprietaire</h1>
<div class="card">
    <?php if ($message): ?><div class="message <?= $msg_class ?>"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <form method="POST">
        <label>Civilite *</label>
        <select name="civilite" required>
            <option value="M.">M.</option>
            <option value="Mme">Mme</option>
        </select>
        <label>Nom *</label>
        <input type="text" name="nom" required>
        <label>Prenom *</label>
        <input type="text" name="prenom" required>
        <label>Email *</label>
        <input type="email" name="email" required>
        <label>Adresse</label>
        <textarea name="adresse" rows="2" style="max-width:400px;width:100%;padding:10px;border:1px solid #ccc;border-radius:5px;"></textarea>
        <label>Telephone</label>
        <input type="tel" name="telephone">
        <br><br>
        <button type="submit" class="btn btn-success">Ajouter</button>
        <a href="proprietaires.php" class="btn btn-info">Retour</a>
    </form>
</div>

<?php getFooter(); ?>
PHPEOF
ok "ajouter_proprietaire.php"

# ---- ajouter_vehicule.php ----
cat > "$WWW_DIR/ajouter_vehicule.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();
$message = '';
$msg_class = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $proprietaire_id = intval($_POST['proprietaire_id']);
    $immatriculation = strtoupper(trim($_POST['immatriculation']));
    $marque = trim($_POST['marque']);
    $modele = trim($_POST['modele']);
    $annee = intval($_POST['annee']);
    $date_mise = $_POST['date_mise_circulation'] ?: null;
    $date_ct = $_POST['date_controle_technique'] ?: null;

    if ($proprietaire_id && $immatriculation && $marque && $modele && $annee) {
        $result = pg_query_params($conn,
            "INSERT INTO vehicule (proprietaire_id, immatriculation, marque, modele, annee, date_mise_circulation, date_controle_technique)
             VALUES ($1,$2,$3,$4,$5,$6,$7)",
            array($proprietaire_id, $immatriculation, $marque, $modele, $annee, $date_mise, $date_ct));
        if ($result) {
            $message = "Vehicule ajoute avec succes.";
            $msg_class = "msg-success";
        } else {
            $message = "Erreur (immatriculation deja existante ?).";
            $msg_class = "msg-error";
        }
    } else {
        $message = "Veuillez remplir tous les champs obligatoires.";
        $msg_class = "msg-error";
    }
}

$proprietaires = pg_query($conn, "SELECT id, civilite, nom, prenom FROM proprietaire ORDER BY nom");

getHeader('Ajouter un vehicule');
?>

<h1>Ajouter un vehicule</h1>
<div class="card">
    <?php if ($message): ?><div class="message <?= $msg_class ?>"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <form method="POST">
        <label>Proprietaire *</label>
        <select name="proprietaire_id" required>
            <option value="">-- Selectionnez --</option>
            <?php while ($p = pg_fetch_assoc($proprietaires)): ?>
                <option value="<?= $p['id'] ?>"><?= htmlspecialchars($p['civilite'] . ' ' . $p['prenom'] . ' ' . $p['nom']) ?></option>
            <?php endwhile; ?>
        </select>
        <label>Immatriculation *</label>
        <input type="text" name="immatriculation" placeholder="AB-123-CD" required>
        <label>Marque *</label>
        <input type="text" name="marque" required>
        <label>Modele *</label>
        <input type="text" name="modele" required>
        <label>Annee *</label>
        <input type="number" name="annee" min="1900" max="2030" required>
        <label>Date de mise en circulation</label>
        <input type="date" name="date_mise_circulation">
        <label>Date du prochain controle technique</label>
        <input type="date" name="date_controle_technique">
        <br><br>
        <button type="submit" class="btn btn-success">Ajouter</button>
        <a href="vehicules.php" class="btn btn-info">Retour</a>
    </form>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "ajouter_vehicule.php"

# ---- modifier_proprietaire.php ----
cat > "$WWW_DIR/modifier_proprietaire.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();
$message = '';
$msg_class = '';

$id = isset($_GET['id']) ? intval($_GET['id']) : 0;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $id = intval($_POST['id']);
    $civilite = trim($_POST['civilite']);
    $nom = trim($_POST['nom']);
    $prenom = trim($_POST['prenom']);
    $email = trim($_POST['email']);
    $adresse = trim($_POST['adresse']);
    $telephone = trim($_POST['telephone']);

    $result = pg_query_params($conn,
        "UPDATE proprietaire SET civilite=$1, nom=$2, prenom=$3, email=$4, adresse=$5, telephone=$6 WHERE id=$7",
        array($civilite, $nom, $prenom, $email, $adresse, $telephone, $id));
    if ($result) {
        $message = "Proprietaire modifie avec succes.";
        $msg_class = "msg-success";
    } else {
        $message = "Erreur lors de la modification.";
        $msg_class = "msg-error";
    }
}

$row = pg_fetch_assoc(pg_query_params($conn, "SELECT * FROM proprietaire WHERE id=$1", array($id)));
if (!$row) { header("Location: proprietaires.php"); exit; }

getHeader('Modifier proprietaire');
?>

<h1>Modifier le proprietaire</h1>
<div class="card">
    <?php if ($message): ?><div class="message <?= $msg_class ?>"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <form method="POST">
        <input type="hidden" name="id" value="<?= $row['id'] ?>">
        <label>Civilite</label>
        <select name="civilite">
            <option value="M." <?= $row['civilite'] === 'M.' ? 'selected' : '' ?>>M.</option>
            <option value="Mme" <?= $row['civilite'] === 'Mme' ? 'selected' : '' ?>>Mme</option>
        </select>
        <label>Nom</label>
        <input type="text" name="nom" value="<?= htmlspecialchars($row['nom']) ?>" required>
        <label>Prenom</label>
        <input type="text" name="prenom" value="<?= htmlspecialchars($row['prenom']) ?>" required>
        <label>Email</label>
        <input type="email" name="email" value="<?= htmlspecialchars($row['email']) ?>" required>
        <label>Adresse</label>
        <textarea name="adresse" rows="2" style="max-width:400px;width:100%;padding:10px;border:1px solid #ccc;border-radius:5px;"><?= htmlspecialchars($row['adresse']) ?></textarea>
        <label>Telephone</label>
        <input type="tel" name="telephone" value="<?= htmlspecialchars($row['telephone']) ?>">
        <br><br>
        <button type="submit" class="btn btn-warning">Modifier</button>
        <a href="proprietaires.php" class="btn btn-info">Retour</a>
    </form>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "modifier_proprietaire.php"

# ---- modifier_vehicule.php ----
cat > "$WWW_DIR/modifier_vehicule.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();
$message = '';
$msg_class = '';

$id = isset($_GET['id']) ? intval($_GET['id']) : 0;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $id = intval($_POST['id']);
    $proprietaire_id = intval($_POST['proprietaire_id']);
    $immatriculation = strtoupper(trim($_POST['immatriculation']));
    $marque = trim($_POST['marque']);
    $modele = trim($_POST['modele']);
    $annee = intval($_POST['annee']);
    $date_mise = $_POST['date_mise_circulation'] ?: null;
    $date_ct = $_POST['date_controle_technique'] ?: null;

    $result = pg_query_params($conn,
        "UPDATE vehicule SET proprietaire_id=$1, immatriculation=$2, marque=$3, modele=$4, annee=$5, date_mise_circulation=$6, date_controle_technique=$7 WHERE id=$8",
        array($proprietaire_id, $immatriculation, $marque, $modele, $annee, $date_mise, $date_ct, $id));
    if ($result) {
        $message = "Vehicule modifie avec succes.";
        $msg_class = "msg-success";
    } else {
        $message = "Erreur lors de la modification.";
        $msg_class = "msg-error";
    }
}

$row = pg_fetch_assoc(pg_query_params($conn, "SELECT * FROM vehicule WHERE id=$1", array($id)));
if (!$row) { header("Location: vehicules.php"); exit; }

$proprietaires = pg_query($conn, "SELECT id, civilite, nom, prenom FROM proprietaire ORDER BY nom");

getHeader('Modifier vehicule');
?>

<h1>Modifier le vehicule</h1>
<div class="card">
    <?php if ($message): ?><div class="message <?= $msg_class ?>"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <form method="POST">
        <input type="hidden" name="id" value="<?= $row['id'] ?>">
        <label>Proprietaire</label>
        <select name="proprietaire_id" required>
            <?php while ($p = pg_fetch_assoc($proprietaires)): ?>
                <option value="<?= $p['id'] ?>" <?= $p['id'] == $row['proprietaire_id'] ? 'selected' : '' ?>><?= htmlspecialchars($p['civilite'] . ' ' . $p['prenom'] . ' ' . $p['nom']) ?></option>
            <?php endwhile; ?>
        </select>
        <label>Immatriculation</label>
        <input type="text" name="immatriculation" value="<?= htmlspecialchars($row['immatriculation']) ?>" required>
        <label>Marque</label>
        <input type="text" name="marque" value="<?= htmlspecialchars($row['marque']) ?>" required>
        <label>Modele</label>
        <input type="text" name="modele" value="<?= htmlspecialchars($row['modele']) ?>" required>
        <label>Annee</label>
        <input type="number" name="annee" value="<?= $row['annee'] ?>" min="1900" max="2030" required>
        <label>Date de mise en circulation</label>
        <input type="date" name="date_mise_circulation" value="<?= $row['date_mise_circulation'] ?>">
        <label>Date du prochain controle technique</label>
        <input type="date" name="date_controle_technique" value="<?= $row['date_controle_technique'] ?>">
        <br><br>
        <button type="submit" class="btn btn-warning">Modifier</button>
        <a href="vehicules.php" class="btn btn-info">Retour</a>
    </form>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "modifier_vehicule.php"

# ---- supprimer.php (générique) ----
cat > "$WWW_DIR/supprimer.php" <<'PHPEOF'
<?php
require_once 'db.php';
$conn = getConnection();

$type = isset($_GET['type']) ? $_GET['type'] : '';
$id = isset($_GET['id']) ? intval($_GET['id']) : 0;

if ($id > 0) {
    if ($type === 'proprietaire') {
        pg_query_params($conn, "DELETE FROM proprietaire WHERE id = $1", array($id));
        header("Location: proprietaires.php");
    } elseif ($type === 'vehicule') {
        pg_query_params($conn, "DELETE FROM vehicule WHERE id = $1", array($id));
        header("Location: vehicules.php");
    } else {
        header("Location: index.php");
    }
} else {
    header("Location: index.php");
}

pg_close($conn);
exit;
?>
PHPEOF
ok "supprimer.php"

# ---- upload.php ----
cat > "$WWW_DIR/upload.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();
$message = '';
$msg_class = '';

$vehicule_id_pre = isset($_GET['vehicule_id']) ? intval($_GET['vehicule_id']) : 0;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $vehicule_id = intval($_POST['vehicule_id']);

    if ($vehicule_id && isset($_FILES['document']) && $_FILES['document']['error'] === UPLOAD_ERR_OK) {
        $upload_dir = __DIR__ . '/uploads/';
        $ext = strtolower(pathinfo($_FILES['document']['name'], PATHINFO_EXTENSION));
        $allowed = array('pdf', 'jpg', 'jpeg', 'png', 'gif');

        if (in_array($ext, $allowed)) {
            $filename = 'carte_grise_' . $vehicule_id . '_' . time() . '.' . $ext;
            $filepath = $upload_dir . $filename;

            if (move_uploaded_file($_FILES['document']['tmp_name'], $filepath)) {
                $web_path = 'uploads/' . $filename;
                pg_query_params($conn,
                    "UPDATE vehicule SET document_path = $1 WHERE id = $2",
                    array($web_path, $vehicule_id));
                $message = "Document uploade avec succes : $filename";
                $msg_class = "msg-success";
            } else {
                $message = "Erreur lors de l'upload du fichier.";
                $msg_class = "msg-error";
            }
        } else {
            $message = "Format non autorise. Formats acceptes : " . implode(', ', $allowed);
            $msg_class = "msg-error";
        }
    } else {
        $message = "Veuillez selectionner un vehicule et un fichier.";
        $msg_class = "msg-error";
    }
}

$vehicules = pg_query($conn,
    "SELECT v.id, v.immatriculation, v.marque, v.modele, p.nom, p.prenom
     FROM vehicule v JOIN proprietaire p ON v.proprietaire_id = p.id ORDER BY v.immatriculation");

getHeader('Upload document');
?>

<h1>Uploader un document (carte grise)</h1>
<div class="card">
    <?php if ($message): ?><div class="message <?= $msg_class ?>"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <form method="POST" enctype="multipart/form-data">
        <label>Vehicule *</label>
        <select name="vehicule_id" required>
            <option value="">-- Selectionnez un vehicule --</option>
            <?php while ($v = pg_fetch_assoc($vehicules)): ?>
                <option value="<?= $v['id'] ?>" <?= $v['id'] == $vehicule_id_pre ? 'selected' : '' ?>>
                    <?= htmlspecialchars($v['immatriculation'] . ' - ' . $v['marque'] . ' ' . $v['modele'] . ' (' . $v['prenom'] . ' ' . $v['nom'] . ')') ?>
                </option>
            <?php endwhile; ?>
        </select>
        <label>Document (PDF, JPG, PNG) *</label>
        <input type="file" name="document" accept=".pdf,.jpg,.jpeg,.png,.gif" required>
        <br><br>
        <button type="submit" class="btn btn-warning">Uploader</button>
        <a href="vehicules.php" class="btn btn-info">Retour</a>
    </form>
</div>

<div class="card">
    <h2>Documents deja uploades</h2>
    <?php
    $docs = pg_query($conn,
        "SELECT v.id, v.immatriculation, v.marque, v.modele, v.document_path, p.nom, p.prenom
         FROM vehicule v JOIN proprietaire p ON v.proprietaire_id = p.id
         WHERE v.document_path IS NOT NULL AND v.document_path != ''
         ORDER BY v.immatriculation");
    if (pg_num_rows($docs) > 0): ?>
    <table>
        <tr><th>Vehicule</th><th>Proprietaire</th><th>Document</th></tr>
        <?php while ($d = pg_fetch_assoc($docs)): ?>
        <tr>
            <td><?= htmlspecialchars($d['immatriculation'] . ' - ' . $d['marque'] . ' ' . $d['modele']) ?></td>
            <td><?= htmlspecialchars($d['prenom'] . ' ' . $d['nom']) ?></td>
            <td><a href="<?= htmlspecialchars($d['document_path']) ?>" target="_blank" class="btn btn-info" style="padding:5px 10px;">Voir le document</a></td>
        </tr>
        <?php endwhile; ?>
    </table>
    <?php else: ?>
        <p>Aucun document uploade pour le moment.</p>
    <?php endif; ?>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "upload.php"

# ---- mail.php (formulaire d'envoi de rappels) ----
cat > "$WWW_DIR/mail.php" <<'PHPEOF'
<?php
require_once 'db.php';
require_once 'style.php';
$conn = getConnection();
$message = '';
$msg_class = '';
$envois = array();

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = isset($_POST['action']) ? $_POST['action'] : '';

    if ($action === 'envoyer_maintenant') {
        // Envoyer les rappels maintenant pour les CT dans les 30 jours
        $result = pg_query($conn,
            "SELECT v.id as vid, v.immatriculation, v.marque, v.modele, v.date_controle_technique,
                    p.civilite, p.nom, p.prenom, p.email
             FROM vehicule v
             JOIN proprietaire p ON v.proprietaire_id = p.id
             WHERE v.date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
             ORDER BY v.date_controle_technique");

        $count = 0;
        while ($row = pg_fetch_assoc($result)) {
            $to = $row['email'];
            $subject = "Rappel : Controle technique a venir - " . $row['immatriculation'];
            $body = "Bonjour " . $row['civilite'] . " " . $row['prenom'] . " " . $row['nom'] . ",\n\n";
            $body .= "Nous vous informons que le controle technique de votre vehicule est prevu prochainement :\n\n";
            $body .= "  Vehicule : " . $row['marque'] . " " . $row['modele'] . "\n";
            $body .= "  Immatriculation : " . $row['immatriculation'] . "\n";
            $body .= "  Date du CT : " . $row['date_controle_technique'] . "\n\n";
            $body .= "Merci de prendre rendez-vous rapidement.\n\n";
            $body .= "Cordialement,\nService Carte Grise - www.exemple.com";

            $headers = "From: contact@exemple.com\r\nReply-To: contact@exemple.com\r\nContent-Type: text/plain; charset=UTF-8";

            $sent = mail($to, $subject, $body, $headers);
            if ($sent) {
                pg_query_params($conn,
                    "INSERT INTO rappel_envoye (vehicule_id, type_rappel) VALUES ($1, 'controle_technique')",
                    array($row['vid']));
                $count++;
            }
            $envois[] = array('email' => $to, 'vehicule' => $row['immatriculation'], 'sent' => $sent);
        }
        $message = "$count rappel(s) envoye(s) avec succes.";
        $msg_class = "msg-success";

    } elseif ($action === 'programmer_cron') {
        $heure = isset($_POST['heure']) ? trim($_POST['heure']) : '03:00';
        $parts = explode(':', $heure);
        $h = intval($parts[0]);
        $m = isset($parts[1]) ? intval($parts[1]) : 0;

        $cron_line = "$m $h * * * php " . __DIR__ . "/cron_mail.php >> /var/log/carte_grise_mail.log 2>&1";

        // Lire le crontab actuel, supprimer l'ancienne ligne, ajouter la nouvelle
        $current = shell_exec("crontab -l 2>/dev/null");
        $lines = explode("\n", $current);
        $new_lines = array();
        foreach ($lines as $line) {
            if (strpos($line, 'cron_mail.php') === false && trim($line) !== '') {
                $new_lines[] = $line;
            }
        }
        $new_lines[] = $cron_line;
        $tmp = tempnam('/tmp', 'cron');
        file_put_contents($tmp, implode("\n", $new_lines) . "\n");
        exec("crontab $tmp");
        unlink($tmp);

        $message = "Cron programme : rappels envoyes chaque jour a {$h}h" . str_pad($m, 2, '0', STR_PAD_LEFT) . ".";
        $msg_class = "msg-success";
    }
}

// Véhicules concernés par un rappel
$ct_result = pg_query($conn,
    "SELECT v.immatriculation, v.marque, v.modele, v.date_controle_technique,
            p.civilite, p.nom, p.prenom, p.email
     FROM vehicule v
     JOIN proprietaire p ON v.proprietaire_id = p.id
     WHERE v.date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
     ORDER BY v.date_controle_technique");

// Historique des rappels
$historique = pg_query($conn,
    "SELECT r.date_envoi, r.type_rappel, v.immatriculation, p.nom, p.prenom, p.email
     FROM rappel_envoye r
     JOIN vehicule v ON r.vehicule_id = v.id
     JOIN proprietaire p ON v.proprietaire_id = p.id
     ORDER BY r.date_envoi DESC LIMIT 20");

// Vérifier si cron est configuré
$cron_actuel = shell_exec("crontab -l 2>/dev/null");
$cron_actif = (strpos($cron_actuel, 'cron_mail.php') !== false);

getHeader('Rappels Mail');
?>

<h1>Gestion des rappels par mail</h1>

<?php if ($message): ?><div class="message <?= $msg_class ?>"><?= htmlspecialchars($message) ?></div><?php endif; ?>

<?php if (!empty($envois)): ?>
<div class="card">
    <h2>Resultat de l'envoi</h2>
    <table>
        <tr><th>Email</th><th>Vehicule</th><th>Statut</th></tr>
        <?php foreach ($envois as $e): ?>
        <tr>
            <td><?= htmlspecialchars($e['email']) ?></td>
            <td><?= htmlspecialchars($e['vehicule']) ?></td>
            <td><?= $e['sent'] ? '<span style="color:green;">Envoye</span>' : '<span style="color:red;">Echec</span>' ?></td>
        </tr>
        <?php endforeach; ?>
    </table>
</div>
<?php endif; ?>

<div class="card">
    <h2>Vehicules concernes (CT dans les 30 jours)</h2>
    <?php if (pg_num_rows($ct_result) > 0): ?>
    <table>
        <tr><th>Proprietaire</th><th>Email</th><th>Vehicule</th><th>Immatriculation</th><th>Date CT</th><th>Jours restants</th></tr>
        <?php while ($row = pg_fetch_assoc($ct_result)):
            $jours = (int)((strtotime($row['date_controle_technique']) - time()) / 86400);
        ?>
        <tr>
            <td><?= htmlspecialchars($row['civilite'] . ' ' . $row['prenom'] . ' ' . $row['nom']) ?></td>
            <td><?= htmlspecialchars($row['email']) ?></td>
            <td><?= htmlspecialchars($row['marque'] . ' ' . $row['modele']) ?></td>
            <td><strong><?= htmlspecialchars($row['immatriculation']) ?></strong></td>
            <td><?= $row['date_controle_technique'] ?></td>
            <td style="color:<?= $jours <= 7 ? '#c62828' : '#f57f17' ?>;font-weight:bold;"><?= $jours ?> j</td>
        </tr>
        <?php endwhile; ?>
    </table>
    <?php else: ?>
        <p>Aucun vehicule avec un CT dans les 30 prochains jours.</p>
    <?php endif; ?>
</div>

<div class="card">
    <h2>Envoyer les rappels maintenant</h2>
    <p>Envoie un mail a tous les proprietaires dont le CT est dans les 30 prochains jours.</p>
    <form method="POST">
        <input type="hidden" name="action" value="envoyer_maintenant">
        <br>
        <button type="submit" class="btn btn-danger" onclick="return confirm('Envoyer les mails de rappel maintenant ?');">Envoyer les rappels maintenant</button>
    </form>
</div>

<div class="card">
    <h2>Programmer l'envoi automatique (Cron)</h2>
    <p>Configure une tache cron pour envoyer automatiquement les rappels chaque jour a l'heure choisie.</p>
    <?php if ($cron_actif): ?>
        <div class="message msg-info">Cron actif : un envoi automatique est deja programme.</div>
    <?php endif; ?>
    <form method="POST">
        <input type="hidden" name="action" value="programmer_cron">
        <label>Heure d'envoi quotidien</label>
        <input type="time" name="heure" value="03:00" style="max-width:200px;">
        <br><br>
        <button type="submit" class="btn btn-primary">Programmer le cron</button>
    </form>
</div>

<div class="card">
    <h2>Historique des rappels envoyes</h2>
    <?php if (pg_num_rows($historique) > 0): ?>
    <table>
        <tr><th>Date d'envoi</th><th>Proprietaire</th><th>Email</th><th>Vehicule</th><th>Type</th></tr>
        <?php while ($row = pg_fetch_assoc($historique)): ?>
        <tr>
            <td><?= $row['date_envoi'] ?></td>
            <td><?= htmlspecialchars($row['prenom'] . ' ' . $row['nom']) ?></td>
            <td><?= htmlspecialchars($row['email']) ?></td>
            <td><?= htmlspecialchars($row['immatriculation']) ?></td>
            <td><?= htmlspecialchars($row['type_rappel']) ?></td>
        </tr>
        <?php endwhile; ?>
    </table>
    <?php else: ?>
        <p>Aucun rappel envoye pour le moment.</p>
    <?php endif; ?>
</div>

<?php getFooter(); pg_close($conn); ?>
PHPEOF
ok "mail.php"

# ---- cron_mail.php (script appelé par cron) ----
cat > "$WWW_DIR/cron_mail.php" <<'PHPEOF'
<?php
/**
 * cron_mail.php - Script de rappel automatique par cron
 * Envoie un mail aux proprietaires dont le CT est dans les 30 jours
 * Usage cron : 0 3 * * * php /users/firms/exemple/www/cron_mail.php
 */

$conn = pg_connect("host=localhost dbname=carte_grise user=exemple password=but1");
if (!$conn) {
    echo date('Y-m-d H:i:s') . " - ERREUR : connexion BDD impossible\n";
    exit(1);
}

$result = pg_query($conn,
    "SELECT v.id as vid, v.immatriculation, v.marque, v.modele, v.date_controle_technique,
            p.civilite, p.nom, p.prenom, p.email
     FROM vehicule v
     JOIN proprietaire p ON v.proprietaire_id = p.id
     WHERE v.date_controle_technique BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
     AND v.id NOT IN (
         SELECT vehicule_id FROM rappel_envoye
         WHERE date_envoi > CURRENT_DATE - INTERVAL '7 days'
     )
     ORDER BY v.date_controle_technique");

$count = 0;

while ($row = pg_fetch_assoc($result)) {
    $to = $row['email'];
    $subject = "Rappel : Controle technique a venir - " . $row['immatriculation'];

    $body = "Bonjour " . $row['civilite'] . " " . $row['prenom'] . " " . $row['nom'] . ",\n\n";
    $body .= "Nous vous informons que le controle technique de votre vehicule est prevu prochainement :\n\n";
    $body .= "  Vehicule : " . $row['marque'] . " " . $row['modele'] . "\n";
    $body .= "  Immatriculation : " . $row['immatriculation'] . "\n";
    $body .= "  Date du CT : " . $row['date_controle_technique'] . "\n\n";
    $body .= "Merci de prendre rendez-vous dans les meilleurs delais.\n\n";
    $body .= "Cordialement,\nService Carte Grise - www.exemple.com";

    $headers = "From: contact@exemple.com\r\nReply-To: contact@exemple.com\r\nContent-Type: text/plain; charset=UTF-8";

    $sent = mail($to, $subject, $body, $headers);

    if ($sent) {
        pg_query_params($conn,
            "INSERT INTO rappel_envoye (vehicule_id, type_rappel) VALUES ($1, 'controle_technique')",
            array($row['vid']));
        $count++;
        echo date('Y-m-d H:i:s') . " - OK : mail envoye a $to pour " . $row['immatriculation'] . "\n";
    } else {
        echo date('Y-m-d H:i:s') . " - ECHEC : mail a $to pour " . $row['immatriculation'] . "\n";
    }
}

echo date('Y-m-d H:i:s') . " - Termine : $count rappel(s) envoye(s)\n";
pg_close($conn);
?>
PHPEOF
ok "cron_mail.php"

# =============================================================
# 5. DROITS ET PERMISSIONS
# =============================================================
echo ""
echo -e "${BOLD}>>> 5. Droits et permissions${NC}"

chown -R "$USER:$USER" "$WWW_DIR"
chmod -R 755 "$WWW_DIR"
chmod 777 "$UPLOAD_DIR"
ok "Droits appliques sur $WWW_DIR"

# =============================================================
# 6. CONFIGURATION APACHE POUR UPLOAD
# =============================================================
echo ""
echo -e "${BOLD}>>> 6. Configuration PHP pour upload${NC}"

PHP_INI=$(php -i 2>/dev/null | grep "Loaded Configuration File" | awk '{print $NF}')
if [ -f "$PHP_INI" ]; then
    sed -i 's/^upload_max_filesize.*/upload_max_filesize = 10M/' "$PHP_INI"
    sed -i 's/^post_max_size.*/post_max_size = 12M/' "$PHP_INI"
    ok "PHP : upload_max_filesize=10M, post_max_size=12M"
else
    fix "php.ini non trouve, config upload par defaut"
fi

# =============================================================
# 7. INSTALLATION SENDMAIL / MAIL
# =============================================================
echo ""
echo -e "${BOLD}>>> 7. Verification du systeme mail${NC}"

if dpkg -l postfix 2>/dev/null | grep -q "^ii"; then
    ok "Postfix installe (mail PHP fonctionnel)"
else
    fix "Installation de postfix pour mail()..."
    apt-get install -y postfix >/dev/null 2>&1
fi

# =============================================================
# 8. CONFIGURATION DU CRON PAR DEFAUT (3h du matin)
# =============================================================
echo ""
echo -e "${BOLD}>>> 8. Configuration du cron (3h00)${NC}"

CRON_LINE="0 3 * * * php $WWW_DIR/cron_mail.php >> /var/log/carte_grise_mail.log 2>&1"

CURRENT_CRON=$(crontab -u "$USER" -l 2>/dev/null)
if echo "$CURRENT_CRON" | grep -q "cron_mail.php"; then
    ok "Cron deja configure"
else
    fix "Ajout du cron pour $USER..."
    (echo "$CURRENT_CRON"; echo "$CRON_LINE") | crontab -u "$USER" -
    ok "Cron configure : tous les jours a 3h00"
fi

# =============================================================
# 9. REDÉMARRAGE APACHE
# =============================================================
echo ""
echo -e "${BOLD}>>> 9. Redemarrage d'Apache${NC}"
systemctl restart apache2
ok "Apache redemarre"

# =============================================================
# RÉSUMÉ
# =============================================================
echo ""
echo -e "${BOLD}=========================================="
echo " Installation terminee !"
echo -e "==========================================${NC}"
echo ""
echo "  Base de donnees : carte_grise (PostgreSQL)"
echo "  Utilisateur BDD : $DB_USER / $DB_PASS"
echo ""
echo "  Fichiers PHP crees :"

for f in $(find "$WWW_DIR" -maxdepth 1 -name "*.php" | sort); do
    echo -e "    ${CYAN}$(basename $f)${NC}"
done

echo ""
echo "  Tables :"
echo "    - proprietaire (civilite, nom, prenom, email, adresse, telephone)"
echo "    - vehicule (immatriculation, marque, modele, annee, date_ct, document)"
echo "    - rappel_envoye (historique des mails envoyes)"
echo ""
echo "  Cron mail : tous les jours a 3h00"
echo "  Uploads   : $UPLOAD_DIR"
echo ""
echo -e "  URL : ${CYAN}http://www.$DOMAIN/index.php${NC}"
echo -e "${BOLD}==========================================${NC}"

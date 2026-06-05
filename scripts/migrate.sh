#!/usr/bin/env bash
# =============================================================================
# migrate.sh  –  CoxyFi MySQL Migration Runner
# Usage : ./scripts/migrate.sh [--env <environment>] [--dry-run]
# =============================================================================
set -euo pipefail

# ---------- Configuration par défaut (surchargeable via variables d'env) -----
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-coxyfi}"
DB_USER="${DB_USER:-coxyfi_app}"
DB_PASS="${DB_PASS:-}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$(dirname "$0")/../migrations}"
DRY_RUN=false

# ---------- Parsing des arguments --------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)       ENV="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    *)           echo "Option inconnue : $1"; exit 1 ;;
  esac
done

# ---------- Chargement du fichier .env si présent ----------------------------
ENV_FILE="${ENV_FILE:-.env}"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} ${DB_PASS:+-p${DB_PASS}} ${DB_NAME}"

echo "========================================================"
echo "  CoxyFi MySQL Migration Runner"
echo "  Host    : ${DB_HOST}:${DB_PORT}"
echo "  Base    : ${DB_NAME}"
echo "  Dry-run : ${DRY_RUN}"
echo "========================================================"

# ---------- Création de la table de tracking si inexistante ------------------
if [[ "$DRY_RUN" == "false" ]]; then
  $MYSQL_CMD <<'SQL'
CREATE TABLE IF NOT EXISTS schema_version (
    version      INT UNSIGNED  NOT NULL,
    description  VARCHAR(256)  NOT NULL,
    script       VARCHAR(256)  NOT NULL,
    checksum     CHAR(64)      DEFAULT NULL,
    installed_by VARCHAR(64)   NOT NULL DEFAULT 'system',
    installed_at DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    execution_ms INT UNSIGNED  DEFAULT NULL,
    success      TINYINT(1)    NOT NULL DEFAULT 1,
    PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL
fi

# ---------- Lecture de la version courante -----------------------------------
CURRENT_VERSION=0
if [[ "$DRY_RUN" == "false" ]]; then
  CURRENT_VERSION=$($MYSQL_CMD -sN -e \
    "SELECT COALESCE(MAX(version),0) FROM schema_version WHERE success=1;" 2>/dev/null || echo 0)
fi
echo "Version actuelle du schéma : ${CURRENT_VERSION}"

# ---------- Application des migrations manquantes ----------------------------
APPLIED=0
for migration_file in $(ls -v "${MIGRATIONS_DIR}"/V*.sql 2>/dev/null); do
  filename=$(basename "$migration_file")
  # Extrait le numéro de version (ex. V3__ → 3)
  version=$(echo "$filename" | sed -E 's/^V([0-9]+)__.*/\1/')

  if [[ "$version" -le "$CURRENT_VERSION" ]]; then
    echo "  [SKIP] ${filename} (déjà appliquée)"
    continue
  fi

  echo "  [APPLY] ${filename} ..."
  CHECKSUM=$(sha256sum "$migration_file" | awk '{print $1}')
  START_MS=$(date +%s%3N)

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "         → DRY RUN : fichier lu, non appliqué."
  else
    $MYSQL_CMD < "$migration_file"
    END_MS=$(date +%s%3N)
    ELAPSED=$(( END_MS - START_MS ))
    # Description extraite du nom de fichier
    DESCRIPTION=$(echo "$filename" | sed -E 's/^V[0-9]+__(.*)\.sql$/\1/' | tr '_' ' ')
    $MYSQL_CMD -e "
      INSERT INTO schema_version (version, description, script, checksum, execution_ms)
      VALUES ($version, '${DESCRIPTION}', '${filename}', '${CHECKSUM}', ${ELAPSED})
      ON DUPLICATE KEY UPDATE checksum='${CHECKSUM}', execution_ms=${ELAPSED}, success=1;
    "
    echo "         → OK (${ELAPSED} ms)"
  fi
  APPLIED=$(( APPLIED + 1 ))
done

echo "========================================================"
echo "  Migrations appliquées : ${APPLIED}"
echo "  Terminé."
echo "========================================================"

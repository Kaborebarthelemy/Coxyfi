#!/usr/bin/env bash
# =============================================================================
# migrate.sh  –  CoxyFi MySQL Migration Runner (Hardened)
# Usage : ./scripts/migrate.sh [--env-file <path>] [--dry-run]
# =============================================================================
set -euo pipefail

# ---------- 1. Load Environment Configuration First ------------------------
ENV_FILE=".env"

# Quick scan for an overridden env file in arguments before full parsing
for arg in "$@"; do
  [[ "$arg" == --env* ]] && echo "Warning: Use --env-file to specify custom environment files."
done

# We process arguments early to allow custom .env source locations
TEMP_ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done
set -- "${TEMP_ARGS[@]}" # Reset arguments for main loop

[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# ---------- 2. Fallback Default Configurations ----------------------------
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-coxyfi}"
DB_USER="${DB_USER:-coxyfi_app}"
DB_PASS="${DB_PASS:-}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$(dirname "$0")/../migrations}"
DRY_RUN=false

# ---------- 3. Main Arguments Parsing -------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)  ENV_FILE="$2"; shift 2 ;; # Already handled, skip safely
    --dry-run)   DRY_RUN=true; shift ;;
    *)           echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Build MySQL command base (using safer configuration injection)
MYSQL_CMD="mysql -h${DB_HOST} -P${DB_PORT} -u${DB_USER} ${DB_PASS:+-p${DB_PASS}} ${DB_NAME}"

echo "========================================================"
echo "  CoxyFi MySQL Migration Runner"
echo "  Host    : ${DB_HOST}:${DB_PORT}"
echo "  Base    : ${DB_NAME}"
echo "  Dry-run : ${DRY_RUN}"
echo "========================================================"

# ---------- 4. Schema Tracking Initialization ----------------------------
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

# ---------- 5. Fetch Current Version -------------------------------------
CURRENT_VERSION=0
if [[ "$DRY_RUN" == "false" ]]; then
  CURRENT_VERSION=$($MYSQL_CMD -sN -e \
    "SELECT COALESCE(MAX(version),0) FROM schema_version WHERE success=1;" 2>/dev/null || echo 0)
fi
echo "Current Schema Version: ${CURRENT_VERSION}"

# ---------- 6. Execute Missing Migrations --------------------------------
APPLIED=0

# Use safe globbing instead of parsing ls output
# Sorts naturally using bash options if available, or processes sequentially
if [ -d "${MIGRATIONS_DIR}" ]; then
  # Enable natural version sorting in bash glob if supported
  (shopt -s nullglob; echo "${MIGRATIONS_DIR}"/V*.sql) | xargs -n1 2>/dev/null | sort -V | while read -r migration_file; do
    [[ -z "$migration_file" ]] && continue
    
    filename=$(basename "$migration_file")
    # Extract version number securely
    version=$(echo "$filename" | sed -E 's/^V([0-9]+)__.*/\1/')

    if [[ "$version" -le "$CURRENT_VERSION" ]]; then
      echo "  [SKIP] ${filename} (Already applied)"
      continue
    fi

    echo "  [APPLY] ${filename} ..."
    CHECKSUM=$(sha256sum "$migration_file" | awk '{print $1}')
    START_MS=$(date +%s%3N)

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "         → DRY RUN: File parsed, not executed."
    else
      # Escape single quotes in description to prevent SQL errors
      RAW_DESC=$(echo "$filename" | sed -E 's/^V[0-9]+__(.*)\.sql$/\1/' | tr '_' ' ')
      DESCRIPTION="${RAW_DESC//\'/\'\'}" 

      # Safely catch migration failures without crashing the entire orchestration script
      if $MYSQL_CMD < "$migration_file"; then
        END_MS=$(date +%s%3N)
        ELAPSED=$(( END_MS - START_MS ))
        
        $MYSQL_CMD -e "
          INSERT INTO schema_version (version, description, script, checksum, execution_ms, success)
          VALUES ($version, '${DESCRIPTION}', '${filename}', '${CHECKSUM}', ${ELAPSED}, 1)
          ON DUPLICATE KEY UPDATE checksum='${CHECKSUM}', execution_ms=${ELAPSED}, success=1;
        "
        echo "         → OK (${ELAPSED} ms)"
      else
        END_MS=$(date +%s%3N)
        ELAPSED=$(( END_MS - START_MS ))
        
        # Log failure into schema tracking table before stopping
        $MYSQL_CMD -e "
          INSERT INTO schema_version (version, description, script, checksum, execution_ms, success)
          VALUES ($version, '${DESCRIPTION}', '${filename}', '${CHECKSUM}', ${ELAPSED}, 0)
          ON DUPLICATE KEY UPDATE success=0, execution_ms=${ELAPSED};
        "
        echo "❌ ERROR: Migration script ${filename} failed!" >&2
        exit 1
      fi
    fi
    APPLIED=$(( APPLIED + 1 ))
  done
fi

echo "========================================================"
echo "  Migrations Applied: ${APPLIED}"
echo "  Finished Execution."
echo "========================================================"

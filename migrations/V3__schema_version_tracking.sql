-- =============================================================================
-- V3__schema_version_tracking.sql – CoxyFi
-- Version: 3
-- Description: Creates the migration tracking table (used by the native runner if Flyway/Liquibase are not available).
-- =============================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS schema_version (
    version         INT UNSIGNED     NOT NULL,
    description     VARCHAR(256)     NOT NULL,
    script          VARCHAR(256)     NOT NULL,
    checksum        CHAR(64)                  DEFAULT NULL COMMENT 'SHA-256 du fichier SQL',
    installed_by    VARCHAR(64)      NOT NULL DEFAULT 'system',
    installed_at    DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    execution_ms    INT UNSIGNED              DEFAULT NULL,
    success         TINYINT(1)       NOT NULL DEFAULT 1,

    PRIMARY KEY (version),
    INDEX idx_installed_at (installed_at)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Historique des migrations appliquées';

-- Retroactively saves previous migrations
INSERT INTO schema_version (version, description, script, installed_by)
VALUES
    (1, 'Initial schema', 'V1__init.sql', 'system'),
    (2, 'Add fulltext and perf indexes', 'V2__add_fulltext_and_perf_indexes.sql', 'system');

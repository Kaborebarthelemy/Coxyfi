-- =============================================================================
-- V1__init.sql – CoxyFi – Normalized Initial Schema
-- Version: 1
-- Author: CoxyFi Engineering
-- Description: Creates the entire normalized database schema
-- for the CoxyFi platform (cached chain state +
-- operational off-chain records).
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------------
-- TABLE: users_alias
-- Mapping between on-chain wallet addresses and application aliases.
-- A single address can have multiple aliases (e.g., pseudonym + ENS).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users_alias (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    wallet_address  VARCHAR(66)      NOT NULL COMMENT 'Adresse EVM/Cosmos (checksummed)',
    alias           VARCHAR(128)     NOT NULL COMMENT 'Alias lisible par lhumain',
    alias_type      ENUM('ens','username','email_hash','external')
                                     NOT NULL DEFAULT 'username',
    is_primary      TINYINT(1)       NOT NULL DEFAULT 0 COMMENT '1 = alias principal du portefeuille',
    created_at      DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at      DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at      DATETIME(3)               DEFAULT NULL COMMENT 'Soft-delete',

    PRIMARY KEY (id),
    UNIQUE  KEY uq_wallet_alias         (wallet_address, alias),
    INDEX   idx_wallet_address          (wallet_address),
    INDEX   idx_alias                   (alias),
    INDEX   idx_alias_type              (alias_type),
    INDEX   idx_deleted_at              (deleted_at)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Alias applicatifs associés aux adresses de portefeuille';


-- ---------------------------------------------------------------------------
--TABLE: offers
-- Loan offers published on-chain, cached off-chain for UI queries.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS offers (
    id                  BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    on_chain_id         VARCHAR(128)     NOT NULL COMMENT 'Identifiant canonique on-chain (ex. tx hash + log index)',
    offer_type          ENUM('lend','borrow')
                                         NOT NULL,
    status              ENUM('open','matched','cancelled','expired','liquidated')
                                         NOT NULL DEFAULT 'open',

    -- Parties
    lender_address      VARCHAR(66)      NOT NULL,
    borrower_address    VARCHAR(66)               DEFAULT NULL COMMENT 'Renseigné quand matched',

    -- Termes financiers
    asset_address       VARCHAR(66)      NOT NULL COMMENT 'Adresse du token ERC-20 prêté',
    asset_symbol        VARCHAR(32)      NOT NULL,
    principal_amount    DECIMAL(36,18)   NOT NULL COMMENT 'Montant principal (unités token)',
    interest_rate_bps   INT UNSIGNED     NOT NULL COMMENT 'Taux dintérêt en points de base (1 bps = 0.01%)',
    duration_seconds    INT UNSIGNED     NOT NULL COMMENT 'Durée du prêt en secondes',
    collateral_address  VARCHAR(66)               DEFAULT NULL,
    collateral_symbol   VARCHAR(32)               DEFAULT NULL,
    collateral_amount   DECIMAL(36,18)            DEFAULT NULL,
    ltv_bps             INT UNSIGNED              DEFAULT NULL COMMENT 'Loan-To-Value en bps',

    -- Horodatages on-chain
    chain_id            INT UNSIGNED     NOT NULL COMMENT 'EVM chain ID',
    block_number        BIGINT UNSIGNED  NOT NULL,
    block_timestamp     DATETIME(3)      NOT NULL,
    tx_hash             VARCHAR(66)      NOT NULL,
    log_index           INT UNSIGNED     NOT NULL,
    expires_at          DATETIME(3)               DEFAULT NULL,

    -- Métadata off-chain
    created_at          DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at          DATETIME(3)               DEFAULT NULL,

    PRIMARY KEY (id),
    -- Unicity : An on-chain event can only produce one offer
    UNIQUE  KEY uq_on_chain_id          (on_chain_id),
    UNIQUE  KEY uq_tx_log               (chain_id, tx_hash, log_index),

    -- Frequent UI Index
    INDEX   idx_status                  (status),
    INDEX   idx_offer_type_status       (offer_type, status),
    INDEX   idx_lender_status           (lender_address, status),
    INDEX   idx_asset_status            (asset_address, status),
    INDEX   idx_block_timestamp         (block_timestamp),
    INDEX   idx_expires_at              (expires_at),
    INDEX   idx_deleted_at              (deleted_at),

    -- Composite Index for Main Listing (Open Offers)
    INDEX   idx_listing                 (status, offer_type, block_timestamp DESC)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Offres de prêt on-chain mises en cache';


-- ---------------------------------------------------------------------------
-- TABLE : loans
-- Active or closed loans, resulting from the matching of an offer.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS loans (
    id                  BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    on_chain_id         VARCHAR(128)     NOT NULL,
    offer_id            BIGINT UNSIGNED  NOT NULL COMMENT 'FK → offers.id',
    status              ENUM('active','repaid','defaulted','liquidated','cancelled')
                                         NOT NULL DEFAULT 'active',

    -- Parts
    lender_address      VARCHAR(66)      NOT NULL,
    borrower_address    VARCHAR(66)      NOT NULL,

    -- Terms (snapshot at the time of origination)
    asset_address       VARCHAR(66)      NOT NULL,
    asset_symbol        VARCHAR(32)      NOT NULL,
    principal_amount    DECIMAL(36,18)   NOT NULL,
    interest_rate_bps   INT UNSIGNED     NOT NULL,
    duration_seconds    INT UNSIGNED     NOT NULL,
    collateral_address  VARCHAR(66)               DEFAULT NULL,
    collateral_symbol   VARCHAR(32)               DEFAULT NULL,
    collateral_amount   DECIMAL(36,18)            DEFAULT NULL,
    ltv_bps             INT UNSIGNED              DEFAULT NULL,

    -- Reimbursement tracking
    amount_repaid       DECIMAL(36,18)   NOT NULL DEFAULT 0,
    interest_accrued    DECIMAL(36,18)   NOT NULL DEFAULT 0,

    -- Horodatages
    chain_id            INT UNSIGNED     NOT NULL,
    originated_block    BIGINT UNSIGNED  NOT NULL,
    originated_at       DATETIME(3)      NOT NULL,
    originated_tx       VARCHAR(66)      NOT NULL,
    due_at              DATETIME(3)      NOT NULL,
    closed_at           DATETIME(3)               DEFAULT NULL,
    closed_tx           VARCHAR(66)               DEFAULT NULL,

    created_at          DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at          DATETIME(3)               DEFAULT NULL,

    PRIMARY KEY (id),
    UNIQUE  KEY uq_on_chain_id          (on_chain_id),
    UNIQUE  KEY uq_offer_loan           (offer_id),           -- 1 offre → au plus 1 prêt actif

    INDEX   idx_status                  (status),
    INDEX   idx_borrower_status         (borrower_address, status),
    INDEX   idx_lender_status           (lender_address, status),
    INDEX   idx_asset_status            (asset_address, status),
    INDEX   idx_due_at                  (due_at),
    INDEX   idx_originated_at           (originated_at),
    INDEX   idx_deleted_at              (deleted_at),

    CONSTRAINT fk_loans_offer
        FOREIGN KEY (offer_id) REFERENCES offers (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Prêts actifs ou clôturés';


-- ---------------------------------------------------------------------------
-- TABLE : registry
-- Registry of on-chain entities referenced (assets, protocols, contracts).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS registry (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    entity_type     ENUM('asset','protocol','contract','oracle','vault')
                                     NOT NULL,
    chain_id        INT UNSIGNED     NOT NULL,
    address         VARCHAR(66)      NOT NULL,
    name            VARCHAR(128)              DEFAULT NULL,
    symbol          VARCHAR(32)               DEFAULT NULL,
    decimals        TINYINT UNSIGNED          DEFAULT NULL,
    metadata_json   JSON                      DEFAULT NULL COMMENT 'Métadonnées arbitraires (logo, site…)',
    is_verified     TINYINT(1)       NOT NULL DEFAULT 0,
    is_active       TINYINT(1)       NOT NULL DEFAULT 1,

    created_at      DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at      DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

    PRIMARY KEY (id),
    UNIQUE  KEY uq_chain_address        (chain_id, address),
    INDEX   idx_entity_type             (entity_type),
    INDEX   idx_symbol                  (symbol),
    INDEX   idx_is_active               (is_active),
    INDEX   idx_is_verified             (is_verified)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Registre des entités on-chain (assets, protocoles, contrats)';


-- ---------------------------------------------------------------------------
-- TABLE : events
-- Raw log of on-chain events received by the indexer.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    chain_id        INT UNSIGNED     NOT NULL,
    block_number    BIGINT UNSIGNED  NOT NULL,
    block_timestamp DATETIME(3)      NOT NULL,
    tx_hash         VARCHAR(66)      NOT NULL,
    log_index       INT UNSIGNED     NOT NULL,
    contract_addr   VARCHAR(66)      NOT NULL COMMENT 'Adresse du contrat émetteur',
    event_name      VARCHAR(128)     NOT NULL COMMENT 'Nom de l'événement Solidity',
    event_signature VARCHAR(128)              DEFAULT NULL COMMENT 'Signature keccak (topic0)',
    raw_data        JSON             NOT NULL COMMENT 'Données brutes décodées de l'événement',
    processed       TINYINT(1)       NOT NULL DEFAULT 0 COMMENT '0=en attente, 1=traité',
    processed_at    DATETIME(3)               DEFAULT NULL,
    error_message   TEXT                      DEFAULT NULL,

    created_at      DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    PRIMARY KEY (id),
    UNIQUE  KEY uq_tx_log               (chain_id, tx_hash, log_index),
    INDEX   idx_contract_event          (contract_addr, event_name),
    INDEX   idx_block_timestamp         (block_timestamp),
    INDEX   idx_processed               (processed),
    INDEX   idx_event_name              (event_name),
    INDEX   idx_block_number            (chain_id, block_number)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Journal brut des événements on-chain (append-only)';


-- ---------------------------------------------------------------------------
-- TABLE : audit_log
-- Immutable record of all application data changes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    actor_address   VARCHAR(66)               DEFAULT NULL COMMENT 'Portefeuille ayant déclenché l'action',
    actor_service   VARCHAR(64)               DEFAULT NULL COMMENT 'Service applicatif (indexer, api, cron…)',
    action          VARCHAR(128)     NOT NULL COMMENT 'ex. offer.create, loan.repay',
    entity_type     VARCHAR(64)      NOT NULL COMMENT 'Table cible',
    entity_id       BIGINT UNSIGNED           DEFAULT NULL,
    entity_ref      VARCHAR(128)              DEFAULT NULL COMMENT 'Référence alternative (on_chain_id…)',
    before_state    JSON                      DEFAULT NULL,
    after_state     JSON                      DEFAULT NULL,
    ip_address      VARCHAR(45)               DEFAULT NULL,
    user_agent      VARCHAR(512)              DEFAULT NULL,
    created_at      DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    PRIMARY KEY (id),
    INDEX   idx_actor_address           (actor_address),
    INDEX   idx_action                  (action),
    INDEX   idx_entity                  (entity_type, entity_id),
    INDEX   idx_created_at              (created_at)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Journal d'audit immuable (append-only)';


-- ---------------------------------------------------------------------------
-- TABLE : fiat_claims
-- Fiat repayment requests linked to a loan (off-ramp gateway).
-- (Optional table – present if the fiat module is enabled.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fiat_claims (
    id                  BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    loan_id             BIGINT UNSIGNED  NOT NULL COMMENT 'FK → loans.id',
    claimant_address    VARCHAR(66)      NOT NULL,
    status              ENUM('pending','approved','rejected','paid','expired')
                                         NOT NULL DEFAULT 'pending',
    claim_amount_usd    DECIMAL(18,6)    NOT NULL,
    currency_code       CHAR(3)          NOT NULL DEFAULT 'USD',
    payment_reference   VARCHAR(128)              DEFAULT NULL COMMENT 'Référence bancaire ou PSP',
    notes               TEXT                      DEFAULT NULL,
    approved_at         DATETIME(3)               DEFAULT NULL,
    paid_at             DATETIME(3)               DEFAULT NULL,
    expires_at          DATETIME(3)               DEFAULT NULL,

    created_at          DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

    PRIMARY KEY (id),
    INDEX   idx_loan_id                 (loan_id),
    INDEX   idx_claimant_status         (claimant_address, status),
    INDEX   idx_status                  (status),
    INDEX   idx_expires_at              (expires_at),

    CONSTRAINT fk_fiat_claims_loan
        FOREIGN KEY (loan_id) REFERENCES loans (id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Demandes de remboursement fiat (module off-ramp optionnel)';


SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- V2__add_fulltext_and_perf_indexes.sql  –  CoxyFi
-- Version      : 2
-- Description  : Ajoute les index FULLTEXT pour la recherche permanente et
--                renforce les index de performance pour les requêtes top-10.
-- =============================================================================

SET NAMES utf8mb4;

-- Index FULLTEXT sur offers pour la recherche permanente (DB3)
ALTER TABLE offers
    ADD FULLTEXT INDEX ft_offers_search (asset_symbol, collateral_symbol, lender_address, borrower_address);

-- Index FULLTEXT sur registry pour la recherche d'entités
ALTER TABLE registry
    ADD FULLTEXT INDEX ft_registry_search (name, symbol);

-- Index composite couvrant pour la requête "prêts par emprunteur" (DB3)
-- Couvre : borrower_address, status, originated_at DESC, principal_amount
ALTER TABLE loans
    ADD INDEX idx_borrower_perf (borrower_address, status, originated_at, principal_amount);

-- Index composite couvrant pour les offres avec filtres (DB3)
-- Couvre : offer_type, status, asset_address, interest_rate_bps
ALTER TABLE offers
    ADD INDEX idx_offers_filter_perf (offer_type, status, asset_address, interest_rate_bps, principal_amount);

-- Index sur events pour le polling de l'indexeur (processed=0, ordre chronologique)
ALTER TABLE events
    ADD INDEX idx_events_pending_perf (processed, chain_id, block_number, log_index);

-- =============================================================================
--V2__add_fulltext_and_perf_indexes.sql – CoxyFi
-- Version: 2
-- Description: Adds fulltext indexes for persistent search and
-- enhances performance indexes for top-10 queries.
-- =============================================================================

SET NAMES utf8mb4;

-- Fulltext index on offers for permanent search (DB3)
ALTER TABLE offers
    ADD FULLTEXT INDEX ft_offers_search (asset_symbol, collateral_symbol, lender_address, borrower_address);

-- Fulltext index on registry for entity search
ALTER TABLE registry
    ADD FULLTEXT INDEX ft_registry_search (name, symbol);

-- Composite index for the "loans by borrower" query (DB3)
-- Covers: borrower_address, status, originated_at DESC, principal_amount
ALTER TABLE loans
    ADD INDEX idx_borrower_perf (borrower_address, status, originated_at, principal_amount);

-- Composite index covering offers with filters (DB3)
-- Covers: offer_type, status, asset_address, interest_rate_bps, principal_amount
ALTER TABLE offers
    ADD INDEX idx_offers_filter_perf (offer_type, status, asset_address, interest_rate_bps, principal_amount);

-- Index on events for indexer polling (processed=0, chronological order)
ALTER TABLE events
    ADD INDEX idx_events_pending_perf (processed, chain_id, block_number, log_index);

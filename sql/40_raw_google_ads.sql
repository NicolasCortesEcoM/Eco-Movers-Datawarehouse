-- 40_raw_google_ads.sql - the Google Ads raw schema, pre-created in the exact shape
-- dlt produces, so the staging models can build BEFORE the first real load.
--
-- Why pre-create at all, when dlt creates its own tables: the developer token was
-- still at "test accounts only" when this was written (2026-09-14), so no row could
-- land yet, and a dbt project that references a table which does not exist fails to
-- build. Column types below were read off a dlt run of pipeline/ads_pipeline/source.py
-- against a synthetic row, so dlt finds the columns it expects and adds nothing.
-- Idempotent. Run as platform_rw (the dlt role) so ownership matches what dlt would
-- have created. app_read never sees raw_* (CLAUDE.md rule 6).
--
-- The primary key is the whole point of this file. A campaign id is unique within
-- Google, but the warehouse must not depend on that: `account_id` (the CHILD customer
-- id the row was read from) is part of the key, so the same campaign id under two
-- accounts can never collide and every row says where it came from.

CREATE SCHEMA IF NOT EXISTS raw_google_ads;
GRANT ALL ON SCHEMA raw_google_ads TO platform_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE platform_rw IN SCHEMA raw_google_ads
  GRANT ALL ON TABLES TO platform_rw;
REVOKE ALL ON SCHEMA raw_google_ads FROM app_read;

-- The manager's account tree, one row per account, manager included (level 0).
CREATE TABLE IF NOT EXISTS raw_google_ads.accounts (
    platform          varchar NOT NULL,
    account_id        varchar NOT NULL,
    account_name      varchar,
    is_manager        boolean,
    level             bigint,
    status            varchar,
    currency_code     varchar,
    time_zone         varchar,
    is_test_account   boolean,
    manager_id        varchar,
    _extracted_at     timestamp with time zone,
    _dlt_load_id      varchar NOT NULL,
    _dlt_id           varchar NOT NULL
);

-- One row per (child account, campaign, account-local day).
CREATE TABLE IF NOT EXISTS raw_google_ads.campaign_daily (
    platform                      varchar NOT NULL,
    account_id                    varchar NOT NULL,
    account_name                  varchar,
    currency                      varchar,
    account_time_zone             varchar,
    date                          date NOT NULL,
    campaign_id                   varchar NOT NULL,
    campaign_name                 varchar,
    campaign_status               varchar,
    advertising_channel_type      varchar,
    advertising_channel_sub_type  varchar,
    bidding_strategy_type         varchar,
    cost_micros                   bigint,        -- cost x 1,000,000, as Google sends it
    impressions                   bigint,
    clicks                        bigint,
    conversions                   double precision,
    conversions_value             double precision,
    all_conversions               double precision,
    _payload                      jsonb,         -- the whole API row
    _extracted_at                 timestamp with time zone,
    _dlt_load_id                  varchar NOT NULL,
    _dlt_id                       varchar NOT NULL
);

CREATE INDEX IF NOT EXISTS campaign_daily_key_idx
    ON raw_google_ads.campaign_daily (platform, account_id, campaign_id, date);

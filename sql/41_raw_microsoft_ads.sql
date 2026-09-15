-- 41_raw_microsoft_ads.sql - the Microsoft Advertising (Bing Ads) raw schema,
-- pre-created in the exact shape dlt produces so staging builds before the first
-- load. Same reasoning and same key as 40_raw_google_ads.sql: `account_id` (the ad
-- account the row was read from) is part of the PK, so a campaign id can never be
-- ambiguous and every row says where it came from. Idempotent; run as platform_rw.
--
-- `spend` and `conversions_value` are TEXT on purpose: Microsoft sends decimal
-- strings, and staging casts them to numeric (CLAUDE.md "Money") - no float ever.

CREATE SCHEMA IF NOT EXISTS raw_microsoft_ads;
GRANT ALL ON SCHEMA raw_microsoft_ads TO platform_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE platform_rw IN SCHEMA raw_microsoft_ads
  GRANT ALL ON TABLES TO platform_rw;
REVOKE ALL ON SCHEMA raw_microsoft_ads FROM app_read;

-- Every ad account the authorised user can see, one row per account.
CREATE TABLE IF NOT EXISTS raw_microsoft_ads.accounts (
    platform          varchar NOT NULL,
    account_id        varchar NOT NULL,
    account_number    varchar,
    account_name      varchar,
    status            varchar,
    currency_code     varchar,
    time_zone         varchar,
    customer_id       varchar,
    _extracted_at     timestamp with time zone,
    _dlt_load_id      varchar NOT NULL,
    _dlt_id           varchar NOT NULL
);

-- One row per (ad account, campaign, account-local day).
CREATE TABLE IF NOT EXISTS raw_microsoft_ads.campaign_daily (
    platform            varchar NOT NULL,
    account_id          varchar NOT NULL,
    account_name        varchar,
    account_number      varchar,
    currency            varchar,
    date                date NOT NULL,
    campaign_id         varchar NOT NULL,
    campaign_name       varchar,
    campaign_status     varchar,
    campaign_type       varchar,
    spend               varchar,        -- decimal string as Microsoft sends it
    impressions         bigint,
    clicks              bigint,
    conversions         double precision,
    conversions_value   varchar,        -- Revenue, decimal string
    all_conversions     double precision,
    _payload            jsonb,          -- the whole report row
    _extracted_at       timestamp with time zone,
    _dlt_load_id        varchar NOT NULL,
    _dlt_id             varchar NOT NULL
);

CREATE INDEX IF NOT EXISTS ms_campaign_daily_key_idx
    ON raw_microsoft_ads.campaign_daily (platform, account_id, campaign_id, date);

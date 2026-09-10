-- Meridian Freight warehouse schema (authoritative).
-- Shipped exactly as created at image build time: two fact tables, no
-- secondary indexes, no constraints beyond the primary keys and NOT NULLs.

CREATE TABLE events (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer NOT NULL,
    region      text    NOT NULL,
    kind        text    NOT NULL,
    occurred_at timestamp NOT NULL,
    amount      numeric(14,2) NOT NULL,
    note        text    NOT NULL DEFAULT ''
);

CREATE TABLE journeys (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer NOT NULL,
    region      text    NOT NULL,
    kind        text    NOT NULL,
    occurred_at timestamp NOT NULL,
    distance_km numeric(10,2) NOT NULL,
    note        text    NOT NULL DEFAULT ''
);
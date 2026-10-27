DROP MATERIALIZED VIEW IF EXISTS word_counts;
DROP TABLE IF EXISTS words;
DROP TABLE IF EXISTS locales;

-- one row per supported locale, with the parameters that differ between countries
CREATE TABLE locales (
    code             text PRIMARY KEY,
    name             text NOT NULL,
    height_male_cm   numeric NOT NULL,
    height_female_cm numeric NOT NULL,
    height_sd_cm     numeric NOT NULL
);

-- every lookup list (names, streets, formats, ...) lives in this one table;
-- a new locale or a new list is just new rows, no new tables
CREATE TABLE words (
    locale   text NOT NULL REFERENCES locales (code),
    category text NOT NULL,
    idx      int NOT NULL,
    value    text NOT NULL,
    weight   numeric NOT NULL DEFAULT 1,
    -- running total of weight inside the list, filled after loading; used for weighted picks
    cum_weight numeric,
    PRIMARY KEY (locale, category, idx)
);

CREATE INDEX ON words (locale, category, cum_weight);

-- list sizes and total weights, so a random pick needs no aggregation on every call
CREATE MATERIALIZED VIEW word_counts AS
SELECT locale, category, count(*)::int AS n, sum(weight) AS total_weight
FROM words
GROUP BY locale, category;

CREATE UNIQUE INDEX ON word_counts (locale, category);

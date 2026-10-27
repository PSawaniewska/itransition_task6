-- random numbers

-- uniform number in [0, 1) that depends only on the key and the stream name;
-- the first 52 bits of an md5 hash fit exactly into a double
CREATE OR REPLACE FUNCTION faker_random(p_key text, p_stream text)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT ('x' || substr(md5(p_key || '|' || p_stream), 1, 13))::bit(52)::bigint / 4503599627370496.0
$$;

-- integer between p_min and p_max (both included)
CREATE OR REPLACE FUNCTION faker_random_int(p_key text, p_stream text, p_min int, p_max int)
RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT p_min + floor(faker_random(p_key, p_stream) * (p_max - p_min + 1))::int
$$;

-- normally distributed number (Box-Muller transform)
CREATE OR REPLACE FUNCTION faker_normal(p_key text, p_stream text, p_mean double precision, p_sd double precision)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    -- 1 - u keeps the value in (0, 1], so ln() never gets 0
    SELECT p_mean + p_sd
        * sqrt(-2 * ln(1 - faker_random(p_key, p_stream || '.1')))
        * cos(2 * pi() * faker_random(p_key, p_stream || '.2'))
$$;


-- lookups and formatting

-- random value from a list, every value equally likely
CREATE OR REPLACE FUNCTION faker_pick(p_locale text, p_category text, p_u double precision)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT w.value
    FROM word_counts c
    JOIN words w ON w.locale = c.locale AND w.category = c.category AND w.idx = floor(p_u * c.n)::int
    WHERE c.locale = p_locale AND c.category = p_category
$$;

-- random value from a list, using the weight column
CREATE OR REPLACE FUNCTION faker_pick_weighted(p_locale text, p_category text, p_u double precision)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT w.value
    FROM word_counts c
    JOIN words w ON w.locale = c.locale AND w.category = c.category
    WHERE c.locale = p_locale AND c.category = p_category
      AND w.cum_weight > p_u * c.total_weight
    ORDER BY w.cum_weight
    LIMIT 1
$$;

-- fills a pattern: '#' becomes a digit 0-9, '%' a digit 1-9, other characters stay
CREATE OR REPLACE FUNCTION faker_digits(p_key text, p_stream text, p_pattern text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT string_agg(
        CASE ch
            WHEN '#' THEN faker_random_int(p_key, p_stream || i, 0, 9)::text
            WHEN '%' THEN faker_random_int(p_key, p_stream || i, 1, 9)::text
            ELSE ch
        END, '' ORDER BY i)
    FROM unnest(string_to_array(p_pattern, NULL)) WITH ORDINALITY AS t(ch, i)
$$;

-- lowercase ASCII version of a name, for e-mail addresses
CREATE OR REPLACE FUNCTION faker_ascii(p_text text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT regexp_replace(
        replace(replace(replace(replace(lower(p_text), 'ä', 'ae'), 'ö', 'oe'), 'ü', 'ue'), 'ß', 'ss'),
        '[^a-z]', '', 'g')
$$;


-- parts of a user

CREATE OR REPLACE FUNCTION faker_person(p_locale text, p_key text)
RETURNS TABLE (gender text, first_name text, last_name text, full_name text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    WITH g AS (
        SELECT CASE WHEN faker_random(p_key, 'gender') < 0.5 THEN 'male' ELSE 'female' END AS gender
    ), p AS (
        SELECT g.gender,
               faker_pick(p_locale, 'first_name_' || g.gender, faker_random(p_key, 'first')) AS first_name,
               faker_pick(p_locale, 'first_name_' || g.gender, faker_random(p_key, 'middle')) AS middle_name,
               faker_pick(p_locale, 'last_name', faker_random(p_key, 'last')) AS last_name,
               faker_pick_weighted(p_locale, 'title_' || g.gender, faker_random(p_key, 'title')) AS title,
               faker_pick_weighted(p_locale, 'name_format', faker_random(p_key, 'name_format')) AS name_format
        FROM g
    )
    SELECT gender, first_name, last_name,
           replace(replace(replace(replace(replace(name_format,
               '{title}', title),
               '{first}', first_name),
               '{middle}', middle_name),
               '{m}', left(middle_name, 1)),
               '{last}', last_name)
    FROM p
$$;

CREATE OR REPLACE FUNCTION faker_street(p_locale text, p_key text)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT replace(replace(replace(replace(replace(
               faker_pick_weighted(p_locale, 'street_format', faker_random(p_key, 'street_format')),
               '{first}', faker_pick(p_locale, 'first_name_male', faker_random(p_key, 'street_first'))),
               '{last}', faker_pick(p_locale, 'last_name', faker_random(p_key, 'street_last'))),
               '{suffix}', coalesce(faker_pick(p_locale, 'street_suffix', faker_random(p_key, 'suffix')), '')),
               '{suffix_short}', coalesce(faker_pick(p_locale, 'street_suffix_short', faker_random(p_key, 'suffix')), '')),
               '{suffix_long}', coalesce(faker_pick(p_locale, 'street_suffix_long', faker_random(p_key, 'suffix')), ''))
$$;

CREATE OR REPLACE FUNCTION faker_city(p_locale text, p_key text)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT replace(replace(replace(replace(replace(
               faker_pick_weighted(p_locale, 'city_format', faker_random(p_key, 'city_format')),
               '{city}', coalesce(faker_pick(p_locale, 'city', faker_random(p_key, 'city')), '')),
               '{city_prefix}', coalesce(faker_pick(p_locale, 'city_prefix', faker_random(p_key, 'city_prefix')), '')),
               '{city_suffix}', coalesce(faker_pick(p_locale, 'city_suffix', faker_random(p_key, 'city_suffix')), '')),
               '{first}', faker_pick(p_locale, 'first_name_female', faker_random(p_key, 'city_first'))),
               '{last}', faker_pick(p_locale, 'last_name', faker_random(p_key, 'city_last')))
$$;

CREATE OR REPLACE FUNCTION faker_address(p_locale text, p_key text)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT replace(replace(replace(replace(replace(replace(
               faker_pick_weighted(p_locale, 'address_format', faker_random(p_key, 'address_format')),
               '{street}', faker_street(p_locale, p_key)),
               '{number}', faker_digits(p_key, 'number',
                   faker_pick_weighted(p_locale, 'building_format', faker_random(p_key, 'building_format')))),
               '{secondary}', coalesce(faker_digits(p_key, 'secondary',
                   faker_pick_weighted(p_locale, 'secondary_format', faker_random(p_key, 'secondary_format'))), '')),
               '{city}', faker_city(p_locale, p_key)),
               '{region}', faker_pick(p_locale, 'region', faker_random(p_key, 'region'))),
               '{zip}', faker_digits(p_key, 'zip',
                   faker_pick_weighted(p_locale, 'postcode_format', faker_random(p_key, 'postcode_format'))))
$$;

-- point uniformly distributed on a sphere:
-- longitude is uniform, but latitude is not, because circles near the poles are shorter;
-- asin(2u - 1) gives every band of the sphere a share equal to its area
CREATE OR REPLACE FUNCTION faker_geo(p_key text)
RETURNS TABLE (latitude double precision, longitude double precision)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT round(degrees(asin(2 * faker_random(p_key, 'lat') - 1))::numeric, 6)::double precision,
           round((360 * faker_random(p_key, 'lon') - 180)::numeric, 6)::double precision
$$;

-- height from a normal distribution, weight from a normal BMI, so the two stay realistic together
CREATE OR REPLACE FUNCTION faker_physical(p_locale text, p_key text, p_gender text)
RETURNS TABLE (height_cm numeric, weight_kg numeric, eye_color text)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    WITH h AS (
        SELECT faker_normal(p_key, 'height',
                   CASE p_gender WHEN 'male' THEN l.height_male_cm ELSE l.height_female_cm END,
                   l.height_sd_cm) AS height
        FROM locales l
        WHERE l.code = p_locale
    )
    SELECT round(height::numeric, 1),
           round((greatest(16, least(45, faker_normal(p_key, 'bmi', 25, 4))) * (height / 100) ^ 2)::numeric, 1),
           faker_pick_weighted(p_locale, 'eye_color', faker_random(p_key, 'eyes'))
    FROM h
$$;

CREATE OR REPLACE FUNCTION faker_phone(p_locale text, p_key text)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker_digits(p_key, 'phone',
        faker_pick_weighted(p_locale, 'phone_format', faker_random(p_key, 'phone_format')))
$$;

CREATE OR REPLACE FUNCTION faker_email(p_locale text, p_key text, p_first_name text, p_last_name text)
RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT faker_digits(p_key, 'email',
               replace(replace(replace(
                   faker_pick_weighted(p_locale, 'email_format', faker_random(p_key, 'email_format')),
                   '{first}', faker_ascii(p_first_name)),
                   '{last}', faker_ascii(p_last_name)),
                   '{f}', left(faker_ascii(p_first_name), 1)))
           || '@' || faker_pick(p_locale, 'email_domain', faker_random(p_key, 'email_domain'))
$$;


-- main entry point

-- one batch of users; the same locale, seed, batch and position always give the same user
CREATE OR REPLACE FUNCTION faker_users(p_locale text, p_seed bigint, p_batch int, p_batch_size int DEFAULT 10)
RETURNS TABLE (
    num int, full_name text, gender text, address text,
    latitude double precision, longitude double precision,
    height_cm numeric, weight_kg numeric, eye_color text,
    phone text, email text
)
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT p_batch * p_batch_size + i + 1,
           person.full_name, person.gender,
           faker_address(p_locale, k.key),
           geo.latitude, geo.longitude,
           body.height_cm, body.weight_kg, body.eye_color,
           faker_phone(p_locale, k.key),
           faker_email(p_locale, k.key, person.first_name, person.last_name)
    FROM generate_series(0, p_batch_size - 1) AS i
    CROSS JOIN LATERAL (SELECT concat_ws('|', p_locale, p_seed, p_batch, i) AS key) k
    CROSS JOIN LATERAL faker_person(p_locale, k.key) person
    CROSS JOIN LATERAL faker_geo(k.key) geo
    CROSS JOIN LATERAL faker_physical(p_locale, k.key, person.gender) body
    ORDER BY i
$$;

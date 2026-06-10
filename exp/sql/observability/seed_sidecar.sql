\if :{?hot_modulus}
\else
\set hot_modulus 64
\endif
\if :{?hot_remainder}
\else
\set hot_remainder 0
\endif

INSERT INTO movie_freshness (movie_id, epoch, hot_flag, freshness_score, last_touch_ts)
SELECT id,
       0,
       (id % :hot_modulus = :hot_remainder),
       CASE WHEN id % :hot_modulus = :hot_remainder THEN 10 ELSE 0 END,
       now()
FROM title
ON CONFLICT (movie_id) DO NOTHING;
GRANT SELECT, INSERT, UPDATE, DELETE ON movie_freshness TO bench;

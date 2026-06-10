\set hot_modulus :hot_modulus
\set hot_remainder :hot_remainder
\set batch_size :batch_size

WITH chosen AS (
    SELECT movie_id
    FROM movie_freshness
    WHERE movie_id % :hot_modulus = :hot_remainder
    ORDER BY last_touch_ts ASC, movie_id ASC
    LIMIT :batch_size
)
UPDATE movie_freshness mf
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
FROM chosen
WHERE mf.movie_id = chosen.movie_id;

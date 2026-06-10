CREATE TABLE IF NOT EXISTS movie_freshness (
    movie_id integer PRIMARY KEY REFERENCES title(id),
    epoch integer NOT NULL DEFAULT 0,
    hot_flag boolean NOT NULL DEFAULT false,
    freshness_score integer NOT NULL DEFAULT 0,
    last_touch_ts timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_movie_freshness_hot_epoch
    ON movie_freshness (hot_flag, epoch DESC, movie_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON movie_freshness TO bench;

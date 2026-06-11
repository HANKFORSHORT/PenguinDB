-- ============================================================
-- TMDB PostgreSQL Schema — Functions, Triggers & Procedures
-- ============================================================

-- ============================================================
-- SECTION 1: UTILITY FUNCTIONS
-- ============================================================

CREATE OR REPLACE FUNCTION fn_get_movie_vote_avg(p_movie_id INTEGER)
RETURNS NUMERIC(4,2)
LANGUAGE sql STABLE AS $$
    SELECT vote_average FROM Movie WHERE movie_id = p_movie_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_movie_runtime_fmt(p_movie_id INTEGER)
RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_runtime SMALLINT;
BEGIN
    SELECT runtime INTO v_runtime FROM Movie WHERE movie_id = p_movie_id;
    IF v_runtime IS NULL OR v_runtime <= 0 THEN RETURN NULL; END IF;
    RETURN (v_runtime / 60)::TEXT || 'h ' || (v_runtime % 60)::TEXT || 'm';
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_tv_runtime_fmt(p_series_id INTEGER)
RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_total INTEGER;
BEGIN
    SELECT COALESCE(SUM(runtime), 0)
    INTO   v_total
    FROM   TV_Episode
    WHERE  series_id = p_series_id AND runtime IS NOT NULL;

    IF v_total = 0 THEN RETURN NULL; END IF;
    RETURN (v_total / 60)::TEXT || 'h ' || (v_total % 60)::TEXT || 'm';
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_movie_cast_count(p_movie_id INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COUNT(*)::INTEGER FROM Movie_Cast WHERE movie_id = p_movie_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_movie_crew_count(p_movie_id INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COUNT(*)::INTEGER FROM Movie_Crew WHERE movie_id = p_movie_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_movie_review_count(p_movie_id INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COUNT(*)::INTEGER FROM User_Review WHERE movie_id = p_movie_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_movie_user_avg(p_movie_id INTEGER)
RETURNS NUMERIC(4,2)
LANGUAGE sql STABLE AS $$
    SELECT ROUND(AVG(rating)::NUMERIC, 2)
    FROM   User_Movie_Rating
    WHERE  movie_id = p_movie_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_person_movie_count(p_person_id INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COUNT(DISTINCT movie_id)::INTEGER
    FROM (
        SELECT movie_id FROM Movie_Cast WHERE person_id = p_person_id
        UNION
        SELECT movie_id FROM Movie_Crew WHERE person_id = p_person_id
    ) sub;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_collection_avg_score(p_collection_id INTEGER)
RETURNS NUMERIC(4,2)
LANGUAGE sql STABLE AS $$
    SELECT ROUND(AVG(vote_average)::NUMERIC, 2)
    FROM   Movie
    WHERE  collection_id = p_collection_id AND vote_count > 0;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_get_image_url(
    p_path VARCHAR,
    p_size VARCHAR DEFAULT 'original'
)
RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base TEXT;
BEGIN
    IF p_path IS NULL OR p_path = '' THEN RETURN NULL; END IF;
    SELECT config_value INTO v_base
    FROM   System_Config
    WHERE  config_key = 'tmdb_secure_base_url';
    RETURN COALESCE(v_base, 'https://image.tmdb.org/t/p/') || p_size || p_path;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_is_user_active(p_user_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT is_active FROM "User" WHERE user_id = p_user_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_has_role(p_user_id INTEGER, p_role_name VARCHAR)
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   User_Role ur
        JOIN   Role r ON r.role_id = ur.role_id
        WHERE  ur.user_id   = p_user_id
          AND  r.role_name  = p_role_name
          AND  (ur.expires_at IS NULL OR ur.expires_at > NOW())
    );
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_etl_needs_sync(
    p_synced_at TIMESTAMPTZ,
    p_interval  INTERVAL DEFAULT INTERVAL '7 days'
)
RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_synced_at IS NULL OR p_synced_at < NOW() - p_interval;
$$;

-- ============================================================
-- SECTION 2: TRIGGER FUNCTIONS
-- ============================================================

CREATE OR REPLACE FUNCTION fn_trg_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_trg_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_record_id  TEXT;
    v_old_data   JSONB;
    v_new_data   JSONB;
    v_user_id    INTEGER;
    v_pk_col     TEXT := COALESCE(TG_ARGV[0], 'id');
BEGIN
    -- Get current user from session variable (app layer sets: SET LOCAL app.current_user_id = ?)
    BEGIN
        v_user_id := current_setting('app.current_user_id', TRUE)::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    IF TG_OP = 'DELETE' THEN
        v_record_id := (row_to_json(OLD)::JSONB) ->> v_pk_col;
        v_old_data  := row_to_json(OLD)::JSONB;
        v_new_data  := NULL;
    ELSIF TG_OP = 'INSERT' THEN
        v_record_id := (row_to_json(NEW)::JSONB) ->> v_pk_col;
        v_old_data  := NULL;
        v_new_data  := row_to_json(NEW)::JSONB;
    ELSE -- UPDATE
        v_record_id := (row_to_json(NEW)::JSONB) ->> v_pk_col;
        v_old_data  := row_to_json(OLD)::JSONB;
        v_new_data  := row_to_json(NEW)::JSONB;
    END IF;

    -- Strip password_hash from User audit rows
    IF TG_TABLE_NAME = 'user' THEN
        v_old_data := v_old_data - 'password_hash';
        v_new_data := v_new_data - 'password_hash';
    END IF;

    INSERT INTO Audit_Log (table_name, record_id, action, changed_by,
                           old_data, new_data, session_info)
    VALUES (
        TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        v_user_id,
        v_old_data,
        v_new_data,
        jsonb_build_object(
            'app_user', current_user,
            'pid',      pg_backend_pid()
        )
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD;
    ELSE RETURN NEW;
    END IF;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_trg_episode_count_sync()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_season_id INTEGER;
BEGIN
    v_season_id := COALESCE(NEW.season_id, OLD.season_id);
    UPDATE TV_Season
    SET    episode_count = (
               SELECT COUNT(*) FROM TV_Episode WHERE season_id = v_season_id
           )
    WHERE  season_id = v_season_id;
    RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_trg_validate_review_rating()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.rating IS NOT NULL THEN
        IF NEW.rating < 0.5 OR NEW.rating > 10.0 THEN
            RAISE EXCEPTION 'Review rating (%) must be between 0.5 and 10.0.', NEW.rating;
        END IF;
        IF (NEW.rating * 2) <> FLOOR(NEW.rating * 2) THEN
            RAISE EXCEPTION 'Review rating (%) must be a multiple of 0.5.', NEW.rating;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_trg_soft_delete_user()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE "User"
    SET    is_active  = FALSE,
           updated_at = NOW()
    WHERE  user_id = OLD.user_id;
    RETURN NULL; -- NULL cancels the real DELETE, only the UPDATE above runs
END;
$$;

-- ============================================================
-- SECTION 3: TRIGGERS
-- ============================================================

-- updated_at triggers
CREATE OR REPLACE TRIGGER trg_set_updated_at_movie
    BEFORE UPDATE ON Movie
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_tv_series
    BEFORE UPDATE ON TV_Series
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_person
    BEFORE UPDATE ON Person
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_user
    BEFORE UPDATE ON "User"
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_user_review
    BEFORE UPDATE ON User_Review
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_movie_rating
    BEFORE UPDATE ON User_Movie_Rating
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_tv_rating
    BEFORE UPDATE ON User_TV_Rating
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_ep_rating
    BEFORE UPDATE ON User_Episode_Rating
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

CREATE OR REPLACE TRIGGER trg_set_updated_at_system_config
    BEFORE UPDATE ON System_Config
    FOR EACH ROW EXECUTE FUNCTION fn_trg_set_updated_at();

-- ---------------------------------------------------------------
-- Episode count sync
CREATE OR REPLACE TRIGGER trg_episode_count_sync
    AFTER INSERT OR DELETE ON TV_Episode
    FOR EACH ROW EXECUTE FUNCTION fn_trg_episode_count_sync();

-- ---------------------------------------------------------------
-- Review rating validation
CREATE OR REPLACE TRIGGER trg_validate_review_rating
    BEFORE INSERT OR UPDATE ON User_Review
    FOR EACH ROW EXECUTE FUNCTION fn_trg_validate_review_rating();

-- ---------------------------------------------------------------
-- Audit triggers
CREATE OR REPLACE TRIGGER trg_audit_movie
    AFTER INSERT OR UPDATE OR DELETE ON Movie
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('movie_id');

CREATE OR REPLACE TRIGGER trg_audit_person
    AFTER INSERT OR UPDATE OR DELETE ON Person
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('person_id');

CREATE OR REPLACE TRIGGER trg_audit_user
    AFTER UPDATE ON "User"
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('user_id');

CREATE OR REPLACE TRIGGER trg_audit_tv_series
    AFTER INSERT OR UPDATE OR DELETE ON TV_Series
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('series_id');

CREATE OR REPLACE TRIGGER trg_audit_company
    AFTER INSERT OR UPDATE OR DELETE ON Company
    FOR EACH ROW EXECUTE FUNCTION fn_trg_audit_log('company_id');

-- ---------------------------------------------------------------
-- Soft delete for User
CREATE OR REPLACE TRIGGER trg_soft_delete_user
    BEFORE DELETE ON "User"
    FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete_user();

-- ============================================================
-- SECTION 4: PROCEDURES — INSERT / UPSERT
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_InsertLanguage(
    p_iso_639_1    CHAR(2),
    p_english_name VARCHAR(100),
    p_native_name  VARCHAR(100) DEFAULT ''
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_iso_639_1 IS NULL OR LENGTH(TRIM(p_iso_639_1)) <> 2 THEN
        RAISE EXCEPTION 'iso_639_1 must be a CHAR(2) string: "%"', p_iso_639_1;
    END IF;
    INSERT INTO Language (iso_639_1, english_name, native_name)
    VALUES (LOWER(p_iso_639_1), p_english_name, COALESCE(p_native_name, ''))
    ON CONFLICT (iso_639_1) DO UPDATE
        SET english_name = EXCLUDED.english_name,
            native_name  = EXCLUDED.native_name;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_UpsertPerson(
    p_tmdb_person_id       INTEGER,
    p_name                 VARCHAR(200),
    p_original_name        VARCHAR(200)  DEFAULT NULL,
    p_biography            TEXT          DEFAULT NULL,
    p_birthday             DATE          DEFAULT NULL,
    p_deathday             DATE          DEFAULT NULL,
    p_gender               SMALLINT      DEFAULT 0,
    p_known_for_department VARCHAR(50)   DEFAULT NULL,
    p_place_of_birth       VARCHAR(200)  DEFAULT NULL,
    p_popularity           NUMERIC(8,3)  DEFAULT 0,
    p_profile_path         VARCHAR(300)  DEFAULT NULL,
    p_homepage             VARCHAR(500)  DEFAULT NULL,
    p_imdb_id              VARCHAR(20)   DEFAULT NULL,
    p_adult                BOOLEAN       DEFAULT FALSE
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_gender NOT IN (0, 1, 2, 3) THEN
        RAISE EXCEPTION 'Invalid gender: %. Only 0,1,2,3 accepted.', p_gender;
    END IF;
    INSERT INTO Person (
        person_id, tmdb_person_id, name, original_name, biography,
        birthday, deathday, gender, known_for_department, place_of_birth,
        popularity, profile_path, homepage, imdb_id, adult, etl_synced_at
    )
    VALUES (
        p_tmdb_person_id, p_tmdb_person_id, p_name, p_original_name, p_biography,
        p_birthday, p_deathday, p_gender, p_known_for_department, p_place_of_birth,
        p_popularity, p_profile_path, p_homepage, p_imdb_id, p_adult, NOW()
    )
    ON CONFLICT (tmdb_person_id) DO UPDATE
        SET name                 = EXCLUDED.name,
            original_name        = EXCLUDED.original_name,
            biography            = EXCLUDED.biography,
            birthday             = EXCLUDED.birthday,
            deathday             = EXCLUDED.deathday,
            gender               = EXCLUDED.gender,
            known_for_department = EXCLUDED.known_for_department,
            place_of_birth       = EXCLUDED.place_of_birth,
            popularity           = EXCLUDED.popularity,
            profile_path         = EXCLUDED.profile_path,
            homepage             = EXCLUDED.homepage,
            imdb_id              = EXCLUDED.imdb_id,
            adult                = EXCLUDED.adult,
            etl_synced_at        = NOW(),
            updated_at           = NOW();
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_InsertPersonAKA(
    p_person_id INTEGER,
    p_alias     VARCHAR(300)
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Person WHERE person_id = p_person_id) THEN
        RAISE EXCEPTION 'person_id=% does not exist.', p_person_id;
    END IF;
    INSERT INTO Person_AKA (person_id, alias)
    VALUES (p_person_id, p_alias)
    ON CONFLICT DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_UpsertCompany(
    p_tmdb_company_id INTEGER,
    p_name            VARCHAR(200),
    p_description     TEXT          DEFAULT NULL,
    p_headquarters    VARCHAR(200)  DEFAULT NULL,
    p_homepage        VARCHAR(500)  DEFAULT NULL,
    p_logo_path       VARCHAR(300)  DEFAULT NULL,
    p_origin_country  CHAR(2)       DEFAULT NULL,
    p_parent_id       INTEGER       DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_parent_id IS NOT NULL AND p_parent_id = p_tmdb_company_id THEN
        RAISE EXCEPTION 'A company cannot be its own parent (id=%).', p_tmdb_company_id;
    END IF;
    INSERT INTO Company (
        company_id, tmdb_company_id, name, description, headquarters,
        homepage, logo_path, origin_country, parent_company_id
    )
    VALUES (
        p_tmdb_company_id, p_tmdb_company_id, p_name, p_description, p_headquarters,
        p_homepage, p_logo_path, p_origin_country, p_parent_id
    )
    ON CONFLICT (tmdb_company_id) DO UPDATE
        SET name              = EXCLUDED.name,
            description       = EXCLUDED.description,
            headquarters      = EXCLUDED.headquarters,
            homepage          = EXCLUDED.homepage,
            logo_path         = EXCLUDED.logo_path,
            origin_country    = EXCLUDED.origin_country,
            parent_company_id = EXCLUDED.parent_company_id,
            etl_synced_at     = NOW();
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_UpsertCollection(
    p_tmdb_collection_id INTEGER,
    p_name               VARCHAR(300),
    p_original_name      VARCHAR(300)  DEFAULT NULL,
    p_original_language  CHAR(2)       DEFAULT NULL,
    p_overview           TEXT          DEFAULT NULL,
    p_poster_path        VARCHAR(300)  DEFAULT NULL,
    p_backdrop_path      VARCHAR(300)  DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Collection (
        collection_id, tmdb_collection_id, name, original_name,
        original_language, overview, poster_path, backdrop_path
    )
    VALUES (
        p_tmdb_collection_id, p_tmdb_collection_id, p_name, p_original_name,
        p_original_language, p_overview, p_poster_path, p_backdrop_path
    )
    ON CONFLICT (tmdb_collection_id) DO UPDATE
        SET name              = EXCLUDED.name,
            original_name     = EXCLUDED.original_name,
            original_language = EXCLUDED.original_language,
            overview          = EXCLUDED.overview,
            poster_path       = EXCLUDED.poster_path,
            backdrop_path     = EXCLUDED.backdrop_path;
END;
$$;

-- ---------------------------------------------------------------
-- sp_UpsertMovie — main ETL procedure wrapped in a transaction.
-- Accepts a JSONB payload with the full movie data from the TMDb API.
--
-- Example JSONB structure:
-- {
--   "tmdb_movie_id":550, "title":"Fight Club", "original_title":"Fight Club",
--   "original_language":"en", "overview":"...", "release_date":"1999-10-15",
--   "status":"Released", "revenue":100853753, "budget":63000000, "runtime":139,
--   "popularity":35.011, "vote_average":8.433, "vote_count":26280,
--   "adult":false, "collection_id":null, "imdb_id":"tt0137523",
--   "tagline":"...", "homepage":"...", "poster_path":"/...", "backdrop_path":"/...",
--   "genres":[{"id":18,"name":"Drama"}],
--   "keywords":[{"id":825,"name":"support group"}],
--   "spoken_languages":[{"iso_639_1":"en","name":"English"}],
--   "production_countries":[{"iso_3166_1":"US","name":"United States"}],
--   "production_companies":[{"id":508,"name":"Regency Enterprises"}],
--   "certifications":[{"cert_std_id":1}],
--   "watch_providers":[{"provider_id":8,"iso_3166_1":"US","availability_type":"flatrate","display_priority":1}],
--   "cast":[{"person_id":287,"cast_order":1,"character_name":"Tyler Durden","credit_id":"52fe4250c3a36847f8014a11"}],
--   "crew":[{"person_id":7467,"department_id":1,"job_id":1,"credit_id":"52fe4250c3a36847f8014a15"}]
-- }

CREATE OR REPLACE PROCEDURE sp_UpsertMovie(p_data JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_movie_id      INTEGER;
    v_tmdb_id       INTEGER;
    v_collection_id INTEGER;
    v_item          JSONB;
BEGIN
    v_tmdb_id := (p_data->>'tmdb_movie_id')::INTEGER;
    IF v_tmdb_id IS NULL THEN
        RAISE EXCEPTION 'tmdb_movie_id is required in the JSONB payload.';
    END IF;

    -- Upsert Collection first if present
    IF p_data->'collection' IS NOT NULL AND p_data->'collection' != 'null' THEN
        v_collection_id := (p_data->'collection'->>'id')::INTEGER;
        CALL sp_UpsertCollection(
            v_collection_id,
            p_data->'collection'->>'name',
            p_data->'collection'->>'original_name',
            NULL, NULL,
            p_data->'collection'->>'poster_path',
            p_data->'collection'->>'backdrop_path'
        );
    ELSE
        v_collection_id := NULL;
    END IF;

    -- Upsert Movie
    INSERT INTO Movie (
        movie_id, tmdb_movie_id, imdb_id,
        title, original_title, original_language,
        overview, tagline, release_date, status,
        revenue, budget, runtime,
        popularity, vote_average, vote_count,
        poster_path, backdrop_path, homepage,
        adult, collection_id, etl_synced_at
    )
    VALUES (
        v_tmdb_id,
        v_tmdb_id,
        p_data->>'imdb_id',
        p_data->>'title',
        p_data->>'original_title',
        p_data->>'original_language',
        p_data->>'overview',
        p_data->>'tagline',
        NULLIF(p_data->>'release_date','')::DATE,
        p_data->>'status',
        COALESCE((p_data->>'revenue')::BIGINT, 0),
        COALESCE((p_data->>'budget')::BIGINT, 0),
        NULLIF(p_data->>'runtime','')::SMALLINT,
        COALESCE((p_data->>'popularity')::NUMERIC, 0),
        COALESCE((p_data->>'vote_average')::NUMERIC, 0),
        COALESCE((p_data->>'vote_count')::INTEGER, 0),
        p_data->>'poster_path',
        p_data->>'backdrop_path',
        p_data->>'homepage',
        COALESCE((p_data->>'adult')::BOOLEAN, FALSE),
        v_collection_id,
        NOW()
    )
    ON CONFLICT (tmdb_movie_id) DO UPDATE
        SET imdb_id           = EXCLUDED.imdb_id,
            title             = EXCLUDED.title,
            original_title    = EXCLUDED.original_title,
            original_language = EXCLUDED.original_language,
            overview          = EXCLUDED.overview,
            tagline           = EXCLUDED.tagline,
            release_date      = EXCLUDED.release_date,
            status            = EXCLUDED.status,
            revenue           = EXCLUDED.revenue,
            budget            = EXCLUDED.budget,
            runtime           = EXCLUDED.runtime,
            popularity        = EXCLUDED.popularity,
            vote_average      = EXCLUDED.vote_average,
            vote_count        = EXCLUDED.vote_count,
            poster_path       = EXCLUDED.poster_path,
            backdrop_path     = EXCLUDED.backdrop_path,
            homepage          = EXCLUDED.homepage,
            adult             = EXCLUDED.adult,
            collection_id     = EXCLUDED.collection_id,
            etl_synced_at     = NOW(),
            updated_at        = NOW()
    RETURNING movie_id INTO v_movie_id;

    -- Sync metadata (genres, keywords, companies, countries, languages)
    CALL sp_SyncMovieMetadata(v_movie_id, p_data);

    -- Sync Cast
    IF p_data->'cast' IS NOT NULL THEN
        CALL sp_SyncMovieCast(v_movie_id, p_data->'cast');
    END IF;

    -- Sync Crew
    IF p_data->'crew' IS NOT NULL THEN
        CALL sp_SyncMovieCrew(v_movie_id, p_data->'crew');
    END IF;

    -- Watch Providers
    IF p_data->'watch_providers' IS NOT NULL THEN
        DELETE FROM Movie_Watch_Provider WHERE movie_id = v_movie_id;
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_data->'watch_providers') LOOP
            CALL sp_InsertMovieWatchProvider(
                v_movie_id,
                (v_item->>'provider_id')::INTEGER,
                v_item->>'iso_3166_1',
                v_item->>'availability_type',
                (v_item->>'display_priority')::SMALLINT
            );
        END LOOP;
    END IF;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_InsertMovieCast(
    p_movie_id       INTEGER,
    p_person_id      INTEGER,
    p_cast_order     SMALLINT,
    p_character_name VARCHAR(300) DEFAULT '',
    p_credit_id      VARCHAR(50)  DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_cast_order <= 0 THEN
        RAISE EXCEPTION 'cast_order must be > 0, got: %', p_cast_order;
    END IF;
    INSERT INTO Movie_Cast (movie_id, person_id, cast_order, character_name, credit_id)
    VALUES (p_movie_id, p_person_id, p_cast_order, COALESCE(p_character_name,''), p_credit_id)
    ON CONFLICT (movie_id, person_id, cast_order) DO UPDATE
        SET character_name = EXCLUDED.character_name,
            credit_id      = EXCLUDED.credit_id;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_SyncMovieCast(p_movie_id INTEGER, p_cast JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_item    JSONB;
    v_new_ids TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT c->>'credit_id' FROM jsonb_array_elements(p_cast) c
        WHERE c->>'credit_id' IS NOT NULL
    ) INTO v_new_ids;

    DELETE FROM Movie_Cast
    WHERE movie_id  = p_movie_id
      AND credit_id IS NOT NULL
      AND credit_id != ALL(v_new_ids);

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_cast) LOOP
        CALL sp_InsertMovieCast(
            p_movie_id,
            (v_item->>'person_id')::INTEGER,
            (v_item->>'cast_order')::SMALLINT,
            COALESCE(v_item->>'character_name', ''),
            v_item->>'credit_id'
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_SyncMovieCrew(p_movie_id INTEGER, p_crew JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_item    JSONB;
    v_new_ids TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT c->>'credit_id' FROM jsonb_array_elements(p_crew) c
        WHERE c->>'credit_id' IS NOT NULL
    ) INTO v_new_ids;

    DELETE FROM Movie_Crew
    WHERE movie_id  = p_movie_id
      AND credit_id IS NOT NULL
      AND credit_id != ALL(v_new_ids);

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_crew) LOOP
        CALL sp_InsertMovieCrew(
            p_movie_id,
            (v_item->>'person_id')::INTEGER,
            (v_item->>'department_id')::SMALLINT,
            (v_item->>'job_id')::SMALLINT,
            v_item->>'credit_id'
        );
    END LOOP;
END;
$$;

-- ============================================================
-- SECTION 4B: Movie × Metadata Procedures
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_InsertMovieGenre(p_movie_id INTEGER, p_genre_id INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Genre WHERE genre_id = p_genre_id AND media_type = 'movie') THEN
        RAISE EXCEPTION 'genre_id=% does not exist with media_type=''movie''.', p_genre_id;
    END IF;
    INSERT INTO Movie_Genre (movie_id, genre_id) VALUES (p_movie_id, p_genre_id)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertMovieKeyword(
    p_movie_id     INTEGER,
    p_keyword_id   INTEGER,
    p_keyword_name VARCHAR(200) DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_keyword_name IS NOT NULL THEN
        INSERT INTO Keyword (keyword_id, name) VALUES (p_keyword_id, p_keyword_name)
        ON CONFLICT (keyword_id) DO NOTHING;
    END IF;
    INSERT INTO Movie_Keyword (movie_id, keyword_id) VALUES (p_movie_id, p_keyword_id)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertMovieLanguage(
    p_movie_id      INTEGER,
    p_iso_639_1     CHAR(2),
    p_language_type VARCHAR(10)
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_language_type NOT IN ('spoken','original') THEN
        RAISE EXCEPTION 'Invalid language_type: "%"', p_language_type;
    END IF;
    INSERT INTO Movie_Language (movie_id, iso_639_1, language_type)
    VALUES (p_movie_id, p_iso_639_1, p_language_type) ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertMovieCountry(p_movie_id INTEGER, p_iso_3166_1 CHAR(2))
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO Movie_Country (movie_id, iso_3166_1) VALUES (p_movie_id, p_iso_3166_1)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertMovieCompany(p_movie_id INTEGER, p_company_id INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Company WHERE company_id = p_company_id) THEN
        RAISE EXCEPTION 'company_id=% does not exist.', p_company_id;
    END IF;
    INSERT INTO Movie_Company (movie_id, company_id) VALUES (p_movie_id, p_company_id)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertMovieCertification(p_movie_id INTEGER, p_cert_std_id SMALLINT)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Certification_Standard WHERE cert_std_id = p_cert_std_id) THEN
        RAISE EXCEPTION 'cert_std_id=% does not exist.', p_cert_std_id;
    END IF;
    INSERT INTO Movie_Certification (movie_id, cert_std_id) VALUES (p_movie_id, p_cert_std_id)
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertMovieWatchProvider(
    p_movie_id          INTEGER,
    p_provider_id       INTEGER,
    p_iso_3166_1        CHAR(2),
    p_availability_type VARCHAR(10),
    p_display_priority  SMALLINT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_availability_type NOT IN ('flatrate','rent','buy','free','ads') THEN
        RAISE EXCEPTION 'Invalid availability_type: "%"', p_availability_type;
    END IF;
    INSERT INTO Movie_Watch_Provider (movie_id, provider_id, iso_3166_1, availability_type, display_priority)
    VALUES (p_movie_id, p_provider_id, p_iso_3166_1, p_availability_type, p_display_priority)
    ON CONFLICT (movie_id, provider_id, iso_3166_1, availability_type) DO UPDATE
        SET display_priority = EXCLUDED.display_priority;
END;
$$;

-- sp_SyncMovieMetadata — sync all movie metadata in one call
CREATE OR REPLACE PROCEDURE sp_SyncMovieMetadata(p_movie_id INTEGER, p_data JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_item JSONB;
BEGIN
    -- Genres
    DELETE FROM Movie_Genre WHERE movie_id = p_movie_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'genres', '[]'::JSONB)) LOOP
        CALL sp_InsertMovieGenre(p_movie_id, (v_item->>'id')::INTEGER);
    END LOOP;

    -- Keywords
    DELETE FROM Movie_Keyword WHERE movie_id = p_movie_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'keywords', '[]'::JSONB)) LOOP
        CALL sp_InsertMovieKeyword(p_movie_id, (v_item->>'id')::INTEGER, v_item->>'name');
    END LOOP;

    -- Spoken Languages
    DELETE FROM Movie_Language WHERE movie_id = p_movie_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'spoken_languages', '[]'::JSONB)) LOOP
        CALL sp_InsertMovieLanguage(p_movie_id, v_item->>'iso_639_1', 'spoken');
    END LOOP;

    -- Production Countries
    DELETE FROM Movie_Country WHERE movie_id = p_movie_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'production_countries', '[]'::JSONB)) LOOP
        CALL sp_InsertMovieCountry(p_movie_id, v_item->>'iso_3166_1');
    END LOOP;

    -- Production Companies
    DELETE FROM Movie_Company WHERE movie_id = p_movie_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'production_companies', '[]'::JSONB)) LOOP
        CALL sp_InsertMovieCompany(p_movie_id, (v_item->>'id')::INTEGER);
    END LOOP;

    -- Certifications
    DELETE FROM Movie_Certification WHERE movie_id = p_movie_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'certifications', '[]'::JSONB)) LOOP
        CALL sp_InsertMovieCertification(p_movie_id, (v_item->>'cert_std_id')::SMALLINT);
    END LOOP;
END;
$$;

-- ============================================================
-- SECTION 4C: TV Series × People Procedures
-- ============================================================

CREATE OR REPLACE PROCEDURE sp_InsertTVCast(
    p_series_id  INTEGER,
    p_person_id  INTEGER,
    p_cast_order SMALLINT,
    p_character  VARCHAR(300) DEFAULT '',
    p_credit_id  VARCHAR(50)  DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_cast_order <= 0 THEN RAISE EXCEPTION 'cast_order must be > 0'; END IF;
    INSERT INTO TV_Cast (series_id, person_id, cast_order, character_name, credit_id)
    VALUES (p_series_id, p_person_id, p_cast_order, COALESCE(p_character,''), p_credit_id)
    ON CONFLICT (series_id, person_id, cast_order) DO UPDATE
        SET character_name = EXCLUDED.character_name,
            credit_id      = EXCLUDED.credit_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertTVCrew(
    p_series_id     INTEGER,
    p_person_id     INTEGER,
    p_department_id SMALLINT,
    p_job_id        SMALLINT,
    p_credit_id     VARCHAR(50) DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO TV_Crew (series_id, person_id, department_id, job_id, credit_id)
    VALUES (p_series_id, p_person_id, p_department_id, p_job_id, p_credit_id)
    ON CONFLICT (series_id, person_id, department_id, job_id) DO UPDATE
        SET credit_id = EXCLUDED.credit_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_InsertTVCreator(
    p_series_id INTEGER,
    p_person_id INTEGER,
    p_credit_id VARCHAR(50) DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO TV_Creator (series_id, person_id, credit_id)
    VALUES (p_series_id, p_person_id, p_credit_id)
    ON CONFLICT (series_id, person_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_SyncTVCast(p_series_id INTEGER, p_cast JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_item JSONB;
    v_new_ids TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT c->>'credit_id' FROM jsonb_array_elements(p_cast) c
        WHERE c->>'credit_id' IS NOT NULL
    ) INTO v_new_ids;
    DELETE FROM TV_Cast
    WHERE series_id = p_series_id AND credit_id IS NOT NULL AND credit_id != ALL(v_new_ids);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_cast) LOOP
        CALL sp_InsertTVCast(
            p_series_id,
            (v_item->>'person_id')::INTEGER,
            (v_item->>'cast_order')::SMALLINT,
            COALESCE(v_item->>'character_name',''),
            v_item->>'credit_id'
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_SyncTVCrew(p_series_id INTEGER, p_crew JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_item JSONB;
    v_new_ids TEXT[];
BEGIN
    SELECT ARRAY(
        SELECT c->>'credit_id' FROM jsonb_array_elements(p_crew) c
        WHERE c->>'credit_id' IS NOT NULL
    ) INTO v_new_ids;
    DELETE FROM TV_Crew
    WHERE series_id = p_series_id AND credit_id IS NOT NULL AND credit_id != ALL(v_new_ids);
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_crew) LOOP
        CALL sp_InsertTVCrew(
            p_series_id,
            (v_item->>'person_id')::INTEGER,
            (v_item->>'department_id')::SMALLINT,
            (v_item->>'job_id')::SMALLINT,
            v_item->>'credit_id'
        );
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_SyncTVCreators(p_series_id INTEGER, p_creators JSONB)
LANGUAGE plpgsql AS $$
DECLARE
    v_item JSONB;
BEGIN
    DELETE FROM TV_Creator WHERE series_id = p_series_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_creators) LOOP
        CALL sp_InsertTVCreator(
            p_series_id,
            (v_item->>'person_id')::INTEGER,
            v_item->>'credit_id'
        );
    END LOOP;
END;
$$;

-- ============================================================
-- SECTION 4D: User & Interaction Procedures
-- ============================================================

-- Note: Password hashing must be handled at the application layer.
-- This procedure accepts an already-hashed password (bcrypt/argon2).
CREATE OR REPLACE PROCEDURE sp_InsertUser(
    p_username      VARCHAR(100),
    p_email         VARCHAR(254),
    p_password_hash VARCHAR(255),
    p_name          VARCHAR(200) DEFAULT NULL,
    p_iso_639_1     CHAR(2)      DEFAULT NULL,
    p_iso_3166_1    CHAR(2)      DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_user_id         INTEGER;
    v_default_role_id SMALLINT;
BEGIN
    IF p_email !~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$' THEN
        RAISE EXCEPTION 'Invalid email: "%"', p_email;
    END IF;
    INSERT INTO "User" (username, email, password_hash, name, iso_639_1, iso_3166_1)
    VALUES (p_username, LOWER(p_email), p_password_hash, p_name, p_iso_639_1, p_iso_3166_1)
    RETURNING user_id INTO v_user_id;

    -- Assign default 'user' role
    SELECT role_id INTO v_default_role_id FROM Role WHERE role_name = 'user';
    IF v_default_role_id IS NOT NULL THEN
        INSERT INTO User_Role (user_id, role_id) VALUES (v_user_id, v_default_role_id)
        ON CONFLICT DO NOTHING;
    END IF;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_InsertUserReview(
    p_user_id        INTEGER,
    p_media_type     VARCHAR(10),
    p_movie_id       INTEGER      DEFAULT NULL,
    p_series_id      INTEGER      DEFAULT NULL,
    p_content        TEXT         DEFAULT '',
    p_rating         NUMERIC(3,1) DEFAULT NULL,
    p_tmdb_review_id VARCHAR(50)  DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT fn_is_user_active(p_user_id) THEN
        RAISE EXCEPTION 'User user_id=% is not active.', p_user_id;
    END IF;
    IF p_movie_id IS NULL AND p_series_id IS NULL THEN
        RAISE EXCEPTION 'Either movie_id or series_id must be provided.';
    END IF;
    IF p_rating IS NOT NULL AND (
        p_rating < 0.5 OR p_rating > 10.0 OR (p_rating*2) <> FLOOR(p_rating*2)
    ) THEN
        RAISE EXCEPTION 'rating (%) is invalid — must be a multiple of 0.5 in [0.5..10].', p_rating;
    END IF;
    INSERT INTO User_Review (tmdb_review_id, user_id, media_type, movie_id, series_id, content, rating)
    VALUES (p_tmdb_review_id, p_user_id, p_media_type, p_movie_id, p_series_id, p_content, p_rating)
    ON CONFLICT (tmdb_review_id) DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_ToggleMovieFavorite(p_user_id INTEGER, p_movie_id INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM User_Movie_Favorite WHERE user_id = p_user_id AND movie_id = p_movie_id) THEN
        DELETE FROM User_Movie_Favorite WHERE user_id = p_user_id AND movie_id = p_movie_id;
    ELSE
        INSERT INTO User_Movie_Favorite (user_id, movie_id) VALUES (p_user_id, p_movie_id);
    END IF;
END;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_ToggleMovieWatchlist(p_user_id INTEGER, p_movie_id INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM User_Movie_Watchlist WHERE user_id = p_user_id AND movie_id = p_movie_id) THEN
        DELETE FROM User_Movie_Watchlist WHERE user_id = p_user_id AND movie_id = p_movie_id;
    ELSE
        INSERT INTO User_Movie_Watchlist (user_id, movie_id) VALUES (p_user_id, p_movie_id);
    END IF;
END;
$$;

-- ============================================================
-- SECTION 5: PROCEDURES — GET / OUTPUT
-- ============================================================

CREATE OR REPLACE FUNCTION sp_GetMovieDetail(p_movie_id INTEGER)
RETURNS TABLE (
    movie_id          INTEGER,
    tmdb_movie_id     INTEGER,
    imdb_id           VARCHAR,
    title             VARCHAR,
    original_title    VARCHAR,
    original_language CHAR(2),
    overview          TEXT,
    tagline           VARCHAR,
    release_date      DATE,
    status            VARCHAR,
    revenue           BIGINT,
    budget            BIGINT,
    runtime           SMALLINT,
    runtime_fmt       TEXT,
    popularity        NUMERIC,
    vote_average      NUMERIC,
    vote_count        INTEGER,
    user_avg_rating   NUMERIC,
    user_review_count INTEGER,
    poster_path       VARCHAR,
    backdrop_path     VARCHAR,
    homepage          VARCHAR,
    adult             BOOLEAN,
    collection_id     INTEGER,
    collection_name   VARCHAR
)
LANGUAGE sql STABLE AS $$
    SELECT
        m.movie_id,
        m.tmdb_movie_id,
        m.imdb_id,
        m.title,
        m.original_title,
        m.original_language,
        m.overview,
        m.tagline,
        m.release_date,
        m.status,
        m.revenue,
        m.budget,
        m.runtime,
        fn_get_movie_runtime_fmt(m.movie_id),
        m.popularity,
        m.vote_average,
        m.vote_count,
        fn_get_movie_user_avg(m.movie_id),
        fn_get_movie_review_count(m.movie_id),
        m.poster_path,
        m.backdrop_path,
        m.homepage,
        m.adult,
        m.collection_id,
        c.name
    FROM  Movie m
    LEFT JOIN Collection c ON c.collection_id = m.collection_id
    WHERE m.movie_id = p_movie_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetMoviesByGenre(
    p_genre_id  INTEGER,
    p_page      INTEGER DEFAULT 1,
    p_page_size INTEGER DEFAULT 20
)
RETURNS TABLE (
    movie_id     INTEGER,
    title        VARCHAR,
    release_date DATE,
    popularity   NUMERIC,
    vote_average NUMERIC,
    poster_path  VARCHAR
)
LANGUAGE sql STABLE AS $$
    SELECT
        m.movie_id,
        m.title,
        m.release_date,
        m.popularity,
        m.vote_average,
        m.poster_path
    FROM  Movie_Genre mg
    JOIN  Movie m ON m.movie_id = mg.movie_id
    WHERE mg.genre_id = p_genre_id
    ORDER BY m.popularity DESC
    LIMIT  p_page_size
    OFFSET (p_page - 1) * p_page_size;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetTVSeriesDetail(p_series_id INTEGER)
RETURNS TABLE (
    series_id         INTEGER,
    tmdb_series_id    INTEGER,
    name              VARCHAR,
    original_name     VARCHAR,
    original_language CHAR(2),
    overview          TEXT,
    tagline           VARCHAR,
    first_air_date    DATE,
    last_air_date     DATE,
    status            VARCHAR,
    type              VARCHAR,
    in_production     BOOLEAN,
    homepage          VARCHAR,
    popularity        NUMERIC,
    vote_average      NUMERIC,
    vote_count        INTEGER,
    poster_path       VARCHAR,
    backdrop_path     VARCHAR,
    adult             BOOLEAN
)
LANGUAGE sql STABLE AS $$
    SELECT
        series_id, tmdb_series_id, name, original_name, original_language,
        overview, tagline, first_air_date, last_air_date, status, type,
        in_production, homepage, popularity, vote_average, vote_count,
        poster_path, backdrop_path, adult
    FROM  TV_Series
    WHERE series_id = p_series_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetPersonDetail(p_person_id INTEGER)
RETURNS TABLE (
    person_id            INTEGER,
    tmdb_person_id       INTEGER,
    name                 VARCHAR,
    original_name        VARCHAR,
    biography            TEXT,
    birthday             DATE,
    deathday             DATE,
    gender               SMALLINT,
    known_for_department VARCHAR,
    place_of_birth       VARCHAR,
    popularity           NUMERIC,
    profile_path         VARCHAR,
    homepage             VARCHAR,
    imdb_id              VARCHAR,
    adult                BOOLEAN,
    movie_count          INTEGER
)
LANGUAGE sql STABLE AS $$
    SELECT
        p.person_id, p.tmdb_person_id, p.name, p.original_name, p.biography,
        p.birthday, p.deathday, p.gender, p.known_for_department, p.place_of_birth,
        p.popularity, p.profile_path, p.homepage, p.imdb_id, p.adult,
        fn_get_person_movie_count(p.person_id)
    FROM  Person p
    WHERE p.person_id = p_person_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetUserProfile(p_user_id INTEGER)
RETURNS TABLE (
    user_id       INTEGER,
    username      VARCHAR,
    name          VARCHAR,
    email         VARCHAR,
    iso_639_1     CHAR(2),
    iso_3166_1    CHAR(2),
    is_active     BOOLEAN,
    created_at    TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
    SELECT user_id, username, name, email, iso_639_1, iso_3166_1,
           is_active, created_at, last_login_at
    FROM   "User"
    WHERE  user_id = p_user_id;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetUserMovieFavorites(
    p_user_id   INTEGER,
    p_page      INTEGER DEFAULT 1,
    p_page_size INTEGER DEFAULT 20
)
RETURNS TABLE (
    movie_id    INTEGER,
    title       VARCHAR,
    poster_path VARCHAR,
    added_at    TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
    SELECT m.movie_id, m.title, m.poster_path, f.created_at
    FROM   User_Movie_Favorite f
    JOIN   Movie m ON m.movie_id = f.movie_id
    WHERE  f.user_id = p_user_id
    ORDER  BY f.created_at DESC
    LIMIT  p_page_size OFFSET (p_page-1)*p_page_size;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetUserTVFavorites(
    p_user_id   INTEGER,
    p_page      INTEGER DEFAULT 1,
    p_page_size INTEGER DEFAULT 20
)
RETURNS TABLE (
    series_id   INTEGER,
    name        VARCHAR,
    poster_path VARCHAR,
    added_at    TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
    SELECT s.series_id, s.name, s.poster_path, f.created_at
    FROM   User_TV_Favorite f
    JOIN   TV_Series s ON s.series_id = f.series_id
    WHERE  f.user_id = p_user_id
    ORDER  BY f.created_at DESC
    LIMIT  p_page_size OFFSET (p_page-1)*p_page_size;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetUserReviews(
    p_user_id   INTEGER,
    p_page      INTEGER DEFAULT 1,
    p_page_size INTEGER DEFAULT 10
)
RETURNS TABLE (
    review_id  INTEGER,
    media_type VARCHAR,
    title      TEXT,
    content    TEXT,
    rating     NUMERIC,
    created_at TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
    SELECT
        r.review_id,
        r.media_type,
        COALESCE(m.title, s.name)::TEXT,
        r.content,
        r.rating,
        r.created_at
    FROM   User_Review r
    LEFT JOIN Movie     m ON m.movie_id  = r.movie_id
    LEFT JOIN TV_Series s ON s.series_id = r.series_id
    WHERE  r.user_id = p_user_id
    ORDER  BY r.created_at DESC
    LIMIT  p_page_size OFFSET (p_page-1)*p_page_size;
$$;

-- ============================================================
-- SECTION 5B: Admin / Audit Queries
-- ============================================================

CREATE OR REPLACE FUNCTION sp_GetAuditLog(
    p_table_name VARCHAR(100) DEFAULT NULL,
    p_from_ts    TIMESTAMPTZ  DEFAULT NOW() - INTERVAL '7 days',
    p_to_ts      TIMESTAMPTZ  DEFAULT NOW(),
    p_page       INTEGER      DEFAULT 1,
    p_page_size  INTEGER      DEFAULT 50
)
RETURNS TABLE (
    audit_id   BIGINT,
    table_name VARCHAR,
    record_id  TEXT,
    action     VARCHAR,
    changed_by INTEGER,
    username   VARCHAR,
    changed_at TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
    SELECT
        al.audit_id, al.table_name, al.record_id, al.action,
        al.changed_by, u.username, al.changed_at
    FROM   Audit_Log al
    LEFT JOIN "User" u ON u.user_id = al.changed_by
    WHERE (p_table_name IS NULL OR al.table_name = p_table_name)
      AND  al.changed_at BETWEEN p_from_ts AND p_to_ts
    ORDER  BY al.changed_at DESC
    LIMIT  p_page_size OFFSET (p_page-1)*p_page_size;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetETLLog(
    p_status    VARCHAR(20) DEFAULT NULL,
    p_page      INTEGER     DEFAULT 1,
    p_page_size INTEGER     DEFAULT 50
)
RETURNS TABLE (
    log_id            BIGINT,
    endpoint          VARCHAR,
    tmdb_id           INTEGER,
    media_type        VARCHAR,
    status            VARCHAR,
    records_processed INTEGER,
    error_message     TEXT,
    started_at        TIMESTAMPTZ,
    finished_at       TIMESTAMPTZ,
    duration_seconds  NUMERIC
)
LANGUAGE sql STABLE AS $$
    SELECT
        log_id, endpoint, tmdb_id, media_type, status,
        records_processed, error_message, started_at, finished_at,
        ROUND(EXTRACT(EPOCH FROM (finished_at - started_at))::NUMERIC, 2)
    FROM   ETL_Log
    WHERE (p_status IS NULL OR status = p_status)
    ORDER  BY started_at DESC
    LIMIT  p_page_size OFFSET (p_page-1)*p_page_size;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetSystemConfig(p_key VARCHAR(100) DEFAULT NULL)
RETURNS TABLE (
    config_key   VARCHAR,
    config_value TEXT,
    description  TEXT,
    updated_at   TIMESTAMPTZ
)
LANGUAGE sql STABLE AS $$
    SELECT config_key, config_value, description, updated_at
    FROM   System_Config
    WHERE  p_key IS NULL OR config_key = p_key
    ORDER  BY config_key;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetMoviesNeedingETLSync(
    p_interval INTERVAL DEFAULT INTERVAL '7 days',
    p_limit    INTEGER  DEFAULT 100
)
RETURNS TABLE (movie_id INTEGER, tmdb_movie_id INTEGER, etl_synced_at TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
    SELECT movie_id, tmdb_movie_id, etl_synced_at
    FROM   Movie
    WHERE  fn_etl_needs_sync(etl_synced_at, p_interval)
    ORDER  BY etl_synced_at NULLS FIRST
    LIMIT  p_limit;
$$;

-- ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION sp_GetTVSeriesNeedingETLSync(
    p_interval INTERVAL DEFAULT INTERVAL '7 days',
    p_limit    INTEGER  DEFAULT 100
)
RETURNS TABLE (series_id INTEGER, tmdb_series_id INTEGER, etl_synced_at TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
    SELECT series_id, tmdb_series_id, etl_synced_at
    FROM   TV_Series
    WHERE  fn_etl_needs_sync(etl_synced_at, p_interval)
    ORDER  BY etl_synced_at NULLS FIRST
    LIMIT  p_limit;
$$;

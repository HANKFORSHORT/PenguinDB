-- ============================================================
-- TMDB PostgreSQL Schema — Table Definitions
-- ============================================================

-- ── D0: Reference / Lookup ───────────────────────────────────

CREATE TABLE Language (
    iso_639_1    CHAR(2)      PRIMARY KEY NOT NULL,
    english_name VARCHAR(100) NOT NULL,
    native_name  VARCHAR(100) NOT NULL DEFAULT '',
    CONSTRAINT uq_language_name UNIQUE (english_name)
);

-- ---------------------------------------------------------------

CREATE TABLE Country (
    iso_3166_1   CHAR(2)      PRIMARY KEY NOT NULL,
    english_name VARCHAR(150) NOT NULL,
    native_name  VARCHAR(150) NOT NULL DEFAULT '',
    CONSTRAINT uq_country_name UNIQUE (english_name)
);

-- ---------------------------------------------------------------

CREATE TABLE Genre (
    genre_id   INTEGER      PRIMARY KEY NOT NULL,
    name       VARCHAR(100) NOT NULL,
    media_type VARCHAR(10)  NOT NULL,
    CONSTRAINT chk_genre_media_type CHECK (media_type IN ('movie', 'tv')),
    CONSTRAINT uq_genre_media       UNIQUE (genre_id, media_type)
);

-- ---------------------------------------------------------------

CREATE TABLE Keyword (
    keyword_id INTEGER      PRIMARY KEY NOT NULL,
    name       VARCHAR(200) NOT NULL,
    CONSTRAINT uq_keyword_name UNIQUE (name)
);

-- ---------------------------------------------------------------

CREATE TABLE Department (
    department_id   SMALLSERIAL  PRIMARY KEY NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    CONSTRAINT uq_dept_name UNIQUE (department_name)
);

-- ---------------------------------------------------------------

CREATE TABLE Job (
    job_id        SMALLSERIAL  PRIMARY KEY NOT NULL,
    department_id SMALLINT     NOT NULL REFERENCES Department (department_id),
    job_name      VARCHAR(150) NOT NULL,
    CONSTRAINT uq_job_per_dept UNIQUE (department_id, job_name)
);

-- ---------------------------------------------------------------

CREATE TABLE Certification_Standard (
    cert_std_id   SMALLSERIAL PRIMARY KEY NOT NULL,
    iso_3166_1    CHAR(2)     NOT NULL REFERENCES Country (iso_3166_1),
    certification VARCHAR(20) NOT NULL,
    meaning       TEXT,
    cert_order    SMALLINT    NOT NULL,
    media_type    VARCHAR(10) NOT NULL,
    CONSTRAINT chk_cert_order_positive CHECK (cert_order > 0),
    CONSTRAINT chk_cert_media_type     CHECK (media_type IN ('movie', 'tv')),
    CONSTRAINT uq_cert_per_country     UNIQUE (iso_3166_1, certification, media_type)
);

-- ── D1: Core Entities ────────────────────────────────────────

CREATE TABLE Person (
    person_id            INTEGER       PRIMARY KEY NOT NULL,
    tmdb_person_id       INTEGER       NOT NULL,
    name                 VARCHAR(200)  NOT NULL,
    original_name        VARCHAR(200),
    biography            TEXT,
    birthday             DATE,
    deathday             DATE,
    gender               SMALLINT,
    known_for_department VARCHAR(50),
    place_of_birth       VARCHAR(200),
    popularity           NUMERIC(8, 3) NOT NULL DEFAULT 0,
    profile_path         VARCHAR(300),
    homepage             VARCHAR(500),
    imdb_id              VARCHAR(20),
    adult                BOOLEAN       NOT NULL DEFAULT FALSE,
    etl_synced_at        TIMESTAMPTZ,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_person_tmdb_id     UNIQUE (tmdb_person_id),
    CONSTRAINT uq_person_imdb_id     UNIQUE (imdb_id),
    CONSTRAINT chk_person_gender     CHECK (gender IN (0, 1, 2, 3)),
    CONSTRAINT chk_person_popularity CHECK (popularity >= 0),
    CONSTRAINT chk_person_birthday   CHECK (birthday IS NULL OR birthday <= CURRENT_DATE),
    CONSTRAINT chk_person_deathday   CHECK (
        deathday IS NULL OR (birthday IS NULL OR deathday > birthday)
    )
);

-- ---------------------------------------------------------------

CREATE TABLE Person_AKA (
    aka_id    SERIAL       PRIMARY KEY NOT NULL,
    person_id INTEGER      NOT NULL REFERENCES Person (person_id) ON DELETE CASCADE,
    alias     VARCHAR(300) NOT NULL
);

-- ---------------------------------------------------------------

CREATE TABLE Company (
    company_id        INTEGER      PRIMARY KEY NOT NULL,
    tmdb_company_id   INTEGER      NOT NULL,
    name              VARCHAR(200) NOT NULL,
    description       TEXT,
    headquarters      VARCHAR(200),
    homepage          VARCHAR(500),
    logo_path         VARCHAR(300),
    origin_country    CHAR(2)      REFERENCES Country (iso_3166_1),
    parent_company_id INTEGER      REFERENCES Company (company_id),
    etl_synced_at     TIMESTAMPTZ,
    CONSTRAINT uq_company_tmdb_id        UNIQUE (tmdb_company_id),
    CONSTRAINT uq_company_name           UNIQUE (name),
    CONSTRAINT chk_company_no_self_parent CHECK (
        parent_company_id IS NULL OR parent_company_id != company_id
    )
);

-- ── D1: Media Core ───────────────────────────────────────────

CREATE TABLE Collection (
    collection_id       INTEGER      PRIMARY KEY NOT NULL,
    tmdb_collection_id  INTEGER      NOT NULL,
    name                VARCHAR(300) NOT NULL,
    original_name       VARCHAR(300),
    original_language   CHAR(2)      REFERENCES Language (iso_639_1),
    overview            TEXT,
    poster_path         VARCHAR(300),
    backdrop_path       VARCHAR(300),
    CONSTRAINT uq_collection_tmdb_id UNIQUE (tmdb_collection_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Collection_Translation (
    collection_id INTEGER      NOT NULL REFERENCES Collection (collection_id) ON DELETE CASCADE,
    iso_3166_1    CHAR(2)      NOT NULL REFERENCES Country (iso_3166_1),
    iso_639_1     CHAR(2)      NOT NULL REFERENCES Language (iso_639_1),
    title         VARCHAR(300),
    overview      TEXT,
    homepage      VARCHAR(500),
    PRIMARY KEY (collection_id, iso_3166_1, iso_639_1)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie (
    movie_id          INTEGER       PRIMARY KEY NOT NULL,
    tmdb_movie_id     INTEGER       NOT NULL,
    imdb_id           VARCHAR(20),
    title             VARCHAR(500)  NOT NULL,
    original_title    VARCHAR(500)  NOT NULL,
    original_language CHAR(2)       NOT NULL REFERENCES Language (iso_639_1),
    overview          TEXT,
    tagline           VARCHAR(500),
    release_date      DATE,
    status            VARCHAR(50),
    revenue           BIGINT        NOT NULL DEFAULT 0,
    budget            BIGINT        NOT NULL DEFAULT 0,
    runtime           SMALLINT,
    popularity        NUMERIC(8, 3) NOT NULL DEFAULT 0,
    vote_average      NUMERIC(4, 2) NOT NULL DEFAULT 0,
    vote_count        INTEGER       NOT NULL DEFAULT 0,
    poster_path       VARCHAR(300),
    backdrop_path     VARCHAR(300),
    homepage          VARCHAR(500),
    adult             BOOLEAN       NOT NULL DEFAULT FALSE,
    collection_id     INTEGER       REFERENCES Collection (collection_id),
    etl_synced_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_movie_tmdb_id        UNIQUE (tmdb_movie_id),
    CONSTRAINT uq_movie_imdb_id        UNIQUE (imdb_id),
    CONSTRAINT chk_movie_status        CHECK (status IN (
        'Rumored', 'Planned', 'In Production',
        'Post Production', 'Released', 'Canceled'
    )),
    CONSTRAINT chk_movie_vote_average  CHECK (vote_average BETWEEN 0 AND 10),
    CONSTRAINT chk_movie_vote_count    CHECK (vote_count >= 0),
    CONSTRAINT chk_movie_popularity    CHECK (popularity >= 0),
    CONSTRAINT chk_movie_budget        CHECK (budget >= 0),
    CONSTRAINT chk_movie_revenue       CHECK (revenue >= 0),
    CONSTRAINT chk_movie_runtime       CHECK (runtime IS NULL OR runtime > 0),
    CONSTRAINT chk_movie_release_date  CHECK (
        release_date IS NULL OR release_date >= '1888-01-01'
    )
);

-- ---------------------------------------------------------------

CREATE TABLE Watch_Provider (
    provider_id       INTEGER      PRIMARY KEY NOT NULL,
    tmdb_provider_id  INTEGER      NOT NULL,
    provider_name     VARCHAR(200) NOT NULL,
    logo_path         VARCHAR(300),
    CONSTRAINT uq_watch_provider_tmdb_id UNIQUE (tmdb_provider_id)
);

-- ── D1: TV ───────────────────────────────────────────────────

CREATE TABLE TV_Series (
    series_id         INTEGER       PRIMARY KEY NOT NULL,
    tmdb_series_id    INTEGER       NOT NULL,
    name              VARCHAR(500)  NOT NULL,
    original_name     VARCHAR(500)  NOT NULL,
    original_language CHAR(2)       NOT NULL REFERENCES Language (iso_639_1),
    overview          TEXT,
    tagline           VARCHAR(500),
    first_air_date    DATE,
    last_air_date     DATE,
    status            VARCHAR(50),
    type              VARCHAR(50),
    in_production     BOOLEAN       NOT NULL DEFAULT FALSE,
    homepage          VARCHAR(500),
    popularity        NUMERIC(8, 3) NOT NULL DEFAULT 0,
    vote_average      NUMERIC(4, 2) NOT NULL DEFAULT 0,
    vote_count        INTEGER       NOT NULL DEFAULT 0,
    poster_path       VARCHAR(300),
    backdrop_path     VARCHAR(300),
    adult             BOOLEAN       NOT NULL DEFAULT FALSE,
    etl_synced_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_tv_tmdb_id       UNIQUE (tmdb_series_id),
    CONSTRAINT chk_tv_status       CHECK (status IN (
        'Returning Series', 'Ended', 'Canceled',
        'In Production', 'Planned', 'Pilot'
    )),
    CONSTRAINT chk_tv_vote_average CHECK (vote_average BETWEEN 0 AND 10),
    CONSTRAINT chk_tv_vote_count   CHECK (vote_count >= 0),
    CONSTRAINT chk_tv_popularity   CHECK (popularity >= 0)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Season (
    season_id      INTEGER      PRIMARY KEY NOT NULL,
    tmdb_season_id INTEGER,
    series_id      INTEGER      NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    season_number  SMALLINT     NOT NULL,
    name           VARCHAR(300),
    overview       TEXT,
    air_date       DATE,
    poster_path    VARCHAR(300),
    vote_average   NUMERIC(4, 2),
    episode_count  SMALLINT,
    CONSTRAINT uq_season_tmdb_id    UNIQUE (tmdb_season_id),
    CONSTRAINT uq_season_per_series UNIQUE (series_id, season_number),
    CONSTRAINT chk_season_number    CHECK (season_number >= 0),
    CONSTRAINT chk_season_vote      CHECK (
        vote_average IS NULL OR vote_average BETWEEN 0 AND 10
    )
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Episode (
    episode_id      INTEGER      PRIMARY KEY NOT NULL,
    tmdb_episode_id INTEGER,
    season_id       INTEGER      NOT NULL REFERENCES TV_Season (season_id) ON DELETE CASCADE,
    series_id       INTEGER      NOT NULL REFERENCES TV_Series (series_id),
    episode_number  SMALLINT     NOT NULL,
    episode_type    VARCHAR(50),
    name            VARCHAR(300) NOT NULL,
    overview        TEXT,
    air_date        DATE,
    runtime         SMALLINT,
    production_code VARCHAR(100),
    still_path      VARCHAR(300),
    vote_average    NUMERIC(4, 2),
    vote_count      INTEGER      NOT NULL DEFAULT 0,
    CONSTRAINT uq_episode_tmdb_id    UNIQUE (tmdb_episode_id),
    CONSTRAINT uq_episode_per_season UNIQUE (season_id, episode_number),
    CONSTRAINT chk_episode_number    CHECK (episode_number > 0),
    CONSTRAINT chk_episode_runtime   CHECK (runtime IS NULL OR runtime > 0),
    CONSTRAINT chk_episode_vote      CHECK (
        vote_average IS NULL OR vote_average BETWEEN 0 AND 10
    ),
    CONSTRAINT chk_episode_vote_count CHECK (vote_count >= 0)
);

-- ── D2: Movie × People ───────────────────────────────────────

CREATE TABLE Movie_Cast (
    movie_id       INTEGER      NOT NULL REFERENCES Movie (movie_id)   ON DELETE CASCADE,
    person_id      INTEGER      NOT NULL REFERENCES Person (person_id)  ON DELETE CASCADE,
    cast_order     SMALLINT     NOT NULL,
    character_name VARCHAR(300) NOT NULL DEFAULT '',
    credit_id      VARCHAR(50),
    PRIMARY KEY (movie_id, person_id, cast_order),
    CONSTRAINT chk_movie_cast_order CHECK (cast_order > 0),
    CONSTRAINT uq_movie_cast_credit UNIQUE (credit_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Crew (
    movie_id      INTEGER  NOT NULL REFERENCES Movie (movie_id)       ON DELETE CASCADE,
    person_id     INTEGER  NOT NULL REFERENCES Person (person_id)      ON DELETE CASCADE,
    department_id SMALLINT NOT NULL REFERENCES Department (department_id),
    job_id        SMALLINT NOT NULL REFERENCES Job (job_id),
    credit_id     VARCHAR(50),
    PRIMARY KEY (movie_id, person_id, department_id, job_id),
    CONSTRAINT uq_movie_crew_credit UNIQUE (credit_id)
);

-- ── D2: Movie × Metadata ─────────────────────────────────────

CREATE TABLE Movie_Genre (
    movie_id INTEGER NOT NULL REFERENCES Movie (movie_id)  ON DELETE CASCADE,
    genre_id INTEGER NOT NULL REFERENCES Genre (genre_id),
    PRIMARY KEY (movie_id, genre_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Keyword (
    movie_id   INTEGER NOT NULL REFERENCES Movie (movie_id)    ON DELETE CASCADE,
    keyword_id INTEGER NOT NULL REFERENCES Keyword (keyword_id),
    PRIMARY KEY (movie_id, keyword_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Language (
    movie_id      INTEGER     NOT NULL REFERENCES Movie (movie_id)      ON DELETE CASCADE,
    iso_639_1     CHAR(2)     NOT NULL REFERENCES Language (iso_639_1),
    language_type VARCHAR(10) NOT NULL,
    PRIMARY KEY (movie_id, iso_639_1, language_type),
    CONSTRAINT chk_movie_language_type CHECK (language_type IN ('spoken', 'original'))
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Country (
    movie_id   INTEGER NOT NULL REFERENCES Movie (movie_id)    ON DELETE CASCADE,
    iso_3166_1 CHAR(2) NOT NULL REFERENCES Country (iso_3166_1),
    PRIMARY KEY (movie_id, iso_3166_1)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Company (
    movie_id   INTEGER NOT NULL REFERENCES Movie (movie_id)    ON DELETE CASCADE,
    company_id INTEGER NOT NULL REFERENCES Company (company_id),
    PRIMARY KEY (movie_id, company_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Certification (
    movie_id    INTEGER  NOT NULL REFERENCES Movie (movie_id)                    ON DELETE CASCADE,
    cert_std_id SMALLINT NOT NULL REFERENCES Certification_Standard (cert_std_id),
    PRIMARY KEY (movie_id, cert_std_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Movie_Watch_Provider (
    movie_id          INTEGER     NOT NULL REFERENCES Movie (movie_id)          ON DELETE CASCADE,
    provider_id       INTEGER     NOT NULL REFERENCES Watch_Provider (provider_id),
    iso_3166_1        CHAR(2)     NOT NULL REFERENCES Country (iso_3166_1),
    availability_type VARCHAR(10) NOT NULL,
    display_priority  SMALLINT    NOT NULL,
    PRIMARY KEY (movie_id, provider_id, iso_3166_1, availability_type),
    CONSTRAINT chk_watch_avail_movie CHECK (
        availability_type IN ('flatrate', 'rent', 'buy', 'free', 'ads')
    )
);

-- ── D2: TV × People ──────────────────────────────────────────

CREATE TABLE TV_Cast (
    series_id      INTEGER      NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    person_id      INTEGER      NOT NULL REFERENCES Person (person_id)     ON DELETE CASCADE,
    cast_order     SMALLINT     NOT NULL,
    character_name VARCHAR(300) NOT NULL DEFAULT '',
    credit_id      VARCHAR(50),
    PRIMARY KEY (series_id, person_id, cast_order),
    CONSTRAINT chk_tv_cast_order CHECK (cast_order > 0),
    CONSTRAINT uq_tv_cast_credit UNIQUE (credit_id)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Crew (
    series_id     INTEGER  NOT NULL REFERENCES TV_Series (series_id)    ON DELETE CASCADE,
    person_id     INTEGER  NOT NULL REFERENCES Person (person_id)         ON DELETE CASCADE,
    department_id SMALLINT NOT NULL REFERENCES Department (department_id),
    job_id        SMALLINT NOT NULL REFERENCES Job (job_id),
    credit_id     VARCHAR(50),
    PRIMARY KEY (series_id, person_id, department_id, job_id),
    CONSTRAINT uq_tv_crew_credit UNIQUE (credit_id)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Creator (
    series_id INTEGER     NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    person_id INTEGER     NOT NULL REFERENCES Person (person_id)     ON DELETE CASCADE,
    credit_id VARCHAR(50),
    PRIMARY KEY (series_id, person_id),
    CONSTRAINT uq_tv_creator_credit UNIQUE (credit_id)
);

-- ── D2: TV × Metadata ────────────────────────────────────────

CREATE TABLE TV_Genre (
    series_id INTEGER NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    genre_id  INTEGER NOT NULL REFERENCES Genre (genre_id),
    PRIMARY KEY (series_id, genre_id)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Keyword (
    series_id  INTEGER NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    keyword_id INTEGER NOT NULL REFERENCES Keyword (keyword_id),
    PRIMARY KEY (series_id, keyword_id)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Language (
    series_id INTEGER NOT NULL REFERENCES TV_Series (series_id)  ON DELETE CASCADE,
    iso_639_1 CHAR(2) NOT NULL REFERENCES Language (iso_639_1),
    PRIMARY KEY (series_id, iso_639_1)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Country (
    series_id  INTEGER NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    iso_3166_1 CHAR(2) NOT NULL REFERENCES Country (iso_3166_1),
    PRIMARY KEY (series_id, iso_3166_1)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Company (
    series_id  INTEGER NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    company_id INTEGER NOT NULL REFERENCES Company (company_id),
    PRIMARY KEY (series_id, company_id)
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Certification (
    series_id   INTEGER    NOT NULL REFERENCES TV_Series (series_id) ON DELETE CASCADE,
    iso_3166_1  CHAR(2)    NOT NULL REFERENCES Country (iso_3166_1),
    rating      VARCHAR(20) NOT NULL,
    descriptors TEXT[],
    PRIMARY KEY (series_id, iso_3166_1),
    CONSTRAINT chk_tv_cert_rating_nonempty CHECK (rating <> '')
);

-- ---------------------------------------------------------------

CREATE TABLE TV_Watch_Provider (
    series_id         INTEGER     NOT NULL REFERENCES TV_Series (series_id)     ON DELETE CASCADE,
    provider_id       INTEGER     NOT NULL REFERENCES Watch_Provider (provider_id),
    iso_3166_1        CHAR(2)     NOT NULL REFERENCES Country (iso_3166_1),
    availability_type VARCHAR(10) NOT NULL,
    display_priority  SMALLINT    NOT NULL,
    PRIMARY KEY (series_id, provider_id, iso_3166_1, availability_type),
    CONSTRAINT chk_watch_avail_tv CHECK (
        availability_type IN ('flatrate', 'rent', 'buy', 'free', 'ads')
    )
);

-- ── D2: Episode × People ─────────────────────────────────────

CREATE TABLE Episode_Cast (
    episode_id     INTEGER      NOT NULL REFERENCES TV_Episode (episode_id) ON DELETE CASCADE,
    person_id      INTEGER      NOT NULL REFERENCES Person (person_id)       ON DELETE CASCADE,
    cast_order     SMALLINT     NOT NULL,
    character_name VARCHAR(300) NOT NULL DEFAULT '',
    credit_id      VARCHAR(50),
    is_guest       BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY (episode_id, person_id, cast_order),
    CONSTRAINT chk_episode_cast_order CHECK (cast_order > 0),
    CONSTRAINT uq_episode_cast_credit UNIQUE (credit_id)
);

-- ---------------------------------------------------------------

CREATE TABLE Episode_Crew (
    episode_id    INTEGER  NOT NULL REFERENCES TV_Episode (episode_id)  ON DELETE CASCADE,
    person_id     INTEGER  NOT NULL REFERENCES Person (person_id)         ON DELETE CASCADE,
    department_id SMALLINT NOT NULL REFERENCES Department (department_id),
    job_id        SMALLINT NOT NULL REFERENCES Job (job_id),
    credit_id     VARCHAR(50),
    PRIMARY KEY (episode_id, person_id, department_id, job_id),
    CONSTRAINT uq_episode_crew_credit UNIQUE (credit_id)
);

-- ── D3: User & Auth ──────────────────────────────────────────

CREATE TABLE "User" (
    user_id              SERIAL       PRIMARY KEY NOT NULL,
    tmdb_account_id      INTEGER,
    username             VARCHAR(100) NOT NULL,
    email                VARCHAR(254) NOT NULL,
    password_hash        VARCHAR(255) NOT NULL,
    name                 VARCHAR(200),
    iso_639_1            CHAR(2)      REFERENCES Language (iso_639_1),
    iso_3166_1           CHAR(2)      REFERENCES Country (iso_3166_1),
    avatar_gravatar_hash VARCHAR(64),
    avatar_tmdb_path     VARCHAR(300),
    include_adult        BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active            BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_login_at        TIMESTAMPTZ,
    CONSTRAINT uq_user_username      UNIQUE (username),
    CONSTRAINT uq_user_email         UNIQUE (email),
    CONSTRAINT uq_user_tmdb_account  UNIQUE (tmdb_account_id),
    CONSTRAINT chk_user_email_format CHECK (
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    )
);

-- ---------------------------------------------------------------

CREATE TABLE Role (
    role_id           SMALLSERIAL PRIMARY KEY NOT NULL,
    role_name         VARCHAR(50) NOT NULL,
    description       TEXT,
    can_manage_movies BOOLEAN     NOT NULL DEFAULT FALSE,
    can_manage_users  BOOLEAN     NOT NULL DEFAULT FALSE,
    can_view_audit    BOOLEAN     NOT NULL DEFAULT FALSE,
    can_run_etl       BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_role_name UNIQUE (role_name)
);

-- ---------------------------------------------------------------

CREATE TABLE User_Role (
    user_id     INTEGER     NOT NULL REFERENCES "User" (user_id) ON DELETE CASCADE,
    role_id     SMALLINT    NOT NULL REFERENCES Role (role_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by INTEGER     REFERENCES "User" (user_id),
    expires_at  TIMESTAMPTZ,
    PRIMARY KEY (user_id, role_id)
);

-- ── D3: User Interactions ────────────────────────────────────

CREATE TABLE User_Review (
    review_id      SERIAL        PRIMARY KEY NOT NULL,
    tmdb_review_id VARCHAR(50),
    user_id        INTEGER       NOT NULL REFERENCES "User" (user_id) ON DELETE CASCADE,
    media_type     VARCHAR(10)   NOT NULL,
    movie_id       INTEGER       REFERENCES Movie (movie_id),
    series_id      INTEGER       REFERENCES TV_Series (series_id),
    content        TEXT          NOT NULL,
    rating         NUMERIC(3, 1),
    tmdb_url       VARCHAR(500),
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_review_tmdb_id     UNIQUE (tmdb_review_id),
    CONSTRAINT chk_review_media_type CHECK (media_type IN ('movie', 'tv')),
    CONSTRAINT chk_review_has_media  CHECK (
        movie_id IS NOT NULL OR series_id IS NOT NULL
    ),
    CONSTRAINT chk_review_rating     CHECK (
        rating IS NULL
        OR (rating BETWEEN 0.5 AND 10.0 AND (rating * 2) = FLOOR(rating * 2))
    )
);

-- ---------------------------------------------------------------

CREATE TABLE User_Movie_Rating (
    user_id    INTEGER       NOT NULL REFERENCES "User" (user_id)  ON DELETE CASCADE,
    movie_id   INTEGER       NOT NULL REFERENCES Movie (movie_id)  ON DELETE CASCADE,
    rating     NUMERIC(3, 1) NOT NULL,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, movie_id),
    CONSTRAINT chk_user_movie_rating CHECK (rating BETWEEN 0.5 AND 10.0)
);

-- ---------------------------------------------------------------

CREATE TABLE User_TV_Rating (
    user_id    INTEGER       NOT NULL REFERENCES "User" (user_id)       ON DELETE CASCADE,
    series_id  INTEGER       NOT NULL REFERENCES TV_Series (series_id)  ON DELETE CASCADE,
    rating     NUMERIC(3, 1) NOT NULL,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, series_id),
    CONSTRAINT chk_user_tv_rating CHECK (rating BETWEEN 0.5 AND 10.0)
);

-- ---------------------------------------------------------------

CREATE TABLE User_Episode_Rating (
    user_id    INTEGER       NOT NULL REFERENCES "User" (user_id)        ON DELETE CASCADE,
    episode_id INTEGER       NOT NULL REFERENCES TV_Episode (episode_id) ON DELETE CASCADE,
    rating     NUMERIC(3, 1) NOT NULL,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, episode_id),
    CONSTRAINT chk_user_ep_rating CHECK (rating BETWEEN 0.5 AND 10.0)
);

-- ---------------------------------------------------------------

CREATE TABLE User_Movie_Favorite (
    user_id    INTEGER     NOT NULL REFERENCES "User" (user_id) ON DELETE CASCADE,
    movie_id   INTEGER     NOT NULL REFERENCES Movie (movie_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, movie_id)
);

-- ---------------------------------------------------------------

CREATE TABLE User_TV_Favorite (
    user_id    INTEGER     NOT NULL REFERENCES "User" (user_id)       ON DELETE CASCADE,
    series_id  INTEGER     NOT NULL REFERENCES TV_Series (series_id)  ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, series_id)
);

-- ---------------------------------------------------------------

CREATE TABLE User_Movie_Watchlist (
    user_id    INTEGER     NOT NULL REFERENCES "User" (user_id) ON DELETE CASCADE,
    movie_id   INTEGER     NOT NULL REFERENCES Movie (movie_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, movie_id)
);

-- ---------------------------------------------------------------

CREATE TABLE User_TV_Watchlist (
    user_id    INTEGER     NOT NULL REFERENCES "User" (user_id)       ON DELETE CASCADE,
    series_id  INTEGER     NOT NULL REFERENCES TV_Series (series_id)  ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, series_id)
);

-- ── D4: System ───────────────────────────────────────────────

CREATE TABLE ETL_Log (
    log_id            BIGSERIAL    PRIMARY KEY NOT NULL,
    endpoint          VARCHAR(200) NOT NULL,
    tmdb_id           INTEGER,
    media_type        VARCHAR(20),
    status            VARCHAR(20)  NOT NULL,
    records_processed INTEGER      NOT NULL DEFAULT 0,
    error_message     TEXT,
    started_at        TIMESTAMPTZ  NOT NULL,
    finished_at       TIMESTAMPTZ,
    CONSTRAINT chk_etl_status CHECK (status IN ('success', 'failed', 'partial'))
);

-- ---------------------------------------------------------------

CREATE TABLE Audit_Log (
    audit_id     BIGSERIAL    PRIMARY KEY NOT NULL,
    table_name   VARCHAR(100) NOT NULL,
    record_id    TEXT         NOT NULL,
    action       VARCHAR(10)  NOT NULL,
    changed_by   INTEGER      REFERENCES "User" (user_id),
    changed_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    old_data     JSONB,
    new_data     JSONB,
    session_info JSONB,
    CONSTRAINT chk_audit_action CHECK (action IN ('INSERT', 'UPDATE', 'DELETE'))
);

-- ---------------------------------------------------------------

CREATE TABLE System_Config (
    config_key   VARCHAR(100) PRIMARY KEY NOT NULL,
    config_value TEXT         NOT NULL,
    description  TEXT,
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

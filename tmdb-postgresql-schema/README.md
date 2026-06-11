# TMDB PostgreSQL Schema

A PostgreSQL database schema for a TMDB-based (The Movie Database) movie and TV tracking application. Includes full table definitions, utility functions, triggers, and stored procedures for ETL, user interactions, and admin auditing.

---

## Repository Structure

```
tmdb-postgresql-schema/
├── README.md
├── sql/
│   ├── 01_create_tables.sql
│   └── 02_functions_triggers_procedures.sql
├── create_table_postgreSQL.docx
└── function_trigger_procedure_-_cutdown.docx
```

| File | Description |
|------|-------------|
| `sql/01_create_tables.sql` | All `CREATE TABLE` statements |
| `sql/02_functions_triggers_procedures.sql` | Functions, triggers, and stored procedures |
| `*.docx` | Original source documents |

---

## Schema Overview

The schema is organized into 4 layers:

**D0 — Reference / Lookup**
`Language`, `Country`, `Genre`, `Keyword`, `Department`, `Job`, `Certification_Standard`

**D1 — Core Entities**
`Person`, `Person_AKA`, `Company`, `Collection`, `Collection_Translation`, `Movie`, `Watch_Provider`, `TV_Series`, `TV_Season`, `TV_Episode`

**D2 — Junction / Metadata**
Movie × People: `Movie_Cast`, `Movie_Crew`
Movie × Metadata: `Movie_Genre`, `Movie_Keyword`, `Movie_Language`, `Movie_Country`, `Movie_Company`, `Movie_Certification`, `Movie_Watch_Provider`
TV × People: `TV_Cast`, `TV_Crew`, `TV_Creator`
TV × Metadata: `TV_Genre`, `TV_Keyword`, `TV_Language`, `TV_Country`, `TV_Company`, `TV_Certification`, `TV_Watch_Provider`
Episode × People: `Episode_Cast`, `Episode_Crew`

**D3 — User & Auth**
`User`, `Role`, `User_Role`, `User_Review`, `User_Movie_Rating`, `User_TV_Rating`, `User_Episode_Rating`, `User_Movie_Favorite`, `User_TV_Favorite`, `User_Movie_Watchlist`, `User_TV_Watchlist`

**D4 — System**
`ETL_Log`, `Audit_Log`, `System_Config`

---

## Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `fn_get_movie_vote_avg(movie_id)` | `NUMERIC(4,2)` | TMDB vote average for a movie |
| `fn_get_movie_runtime_fmt(movie_id)` | `TEXT` | Runtime formatted as `2h 19m` |
| `fn_get_tv_runtime_fmt(series_id)` | `TEXT` | Total TV series runtime formatted |
| `fn_get_movie_cast_count(movie_id)` | `INTEGER` | Number of cast members |
| `fn_get_movie_crew_count(movie_id)` | `INTEGER` | Number of crew members |
| `fn_get_movie_review_count(movie_id)` | `INTEGER` | Number of user reviews |
| `fn_get_movie_user_avg(movie_id)` | `NUMERIC(4,2)` | Average user rating |
| `fn_get_person_movie_count(person_id)` | `INTEGER` | Movies a person is credited in |
| `fn_get_collection_avg_score(collection_id)` | `NUMERIC(4,2)` | Average vote score across a collection |
| `fn_get_image_url(path, size)` | `TEXT` | Full TMDB image URL |
| `fn_is_user_active(user_id)` | `BOOLEAN` | Check if a user account is active |
| `fn_has_role(user_id, role_name)` | `BOOLEAN` | Check if user holds a role |
| `fn_etl_needs_sync(synced_at, interval)` | `BOOLEAN` | Whether a record is due for re-sync |

---

## Triggers

| Trigger | Table | Event | Action |
|---------|-------|-------|--------|
| `trg_set_updated_at_*` | Various | `BEFORE UPDATE` | Auto-set `updated_at = NOW()` |
| `trg_episode_count_sync` | `TV_Episode` | `AFTER INSERT/DELETE` | Sync `episode_count` on parent `TV_Season` |
| `trg_validate_review_rating` | `User_Review` | `BEFORE INSERT/UPDATE` | Enforce 0.5-step rating in [0.5..10] |
| `trg_audit_*` | Movie, Person, User, TV_Series, Company | `AFTER INSERT/UPDATE/DELETE` | Write to `Audit_Log` |
| `trg_soft_delete_user` | `User` | `BEFORE DELETE` | Convert DELETE to soft-delete (`is_active = FALSE`) |

---

## Stored Procedures

### Upsert / Insert

| Procedure | Description |
|-----------|-------------|
| `sp_InsertLanguage` | Insert or update a language record |
| `sp_UpsertPerson` | ETL upsert for a person |
| `sp_InsertPersonAKA` | Add an alias for a person |
| `sp_UpsertCompany` | ETL upsert for a production company |
| `sp_UpsertCollection` | ETL upsert for a movie collection |
| `sp_UpsertMovie(jsonb)` | Main ETL entry point — upserts movie + all related metadata, cast, crew, and watch providers from a single JSONB payload |
| `sp_SyncMovieMetadata` | Sync genres, keywords, languages, countries, companies, certifications for a movie |
| `sp_SyncMovieCast` | Diff-sync cast for a movie |
| `sp_SyncMovieCrew` | Diff-sync crew for a movie |
| `sp_InsertTVCast/Crew/Creator` | Insert individual TV credits |
| `sp_SyncTVCast/Crew/Creators` | Diff-sync TV credits |
| `sp_InsertUser` | Register a new user (assigns default role) |
| `sp_InsertUserReview` | Add a user review with validation |
| `sp_ToggleMovieFavorite` | Add/remove a movie from favorites |
| `sp_ToggleMovieWatchlist` | Add/remove a movie from watchlist |

### Query / Output

| Function | Description |
|----------|-------------|
| `sp_GetMovieDetail(movie_id)` | Full movie detail including runtime, user ratings, collection |
| `sp_GetMoviesByGenre(genre_id, page, page_size)` | Paginated movies by genre, sorted by popularity |
| `sp_GetTVSeriesDetail(series_id)` | Full TV series detail |
| `sp_GetPersonDetail(person_id)` | Person detail with movie count |
| `sp_GetUserProfile(user_id)` | User profile (no password) |
| `sp_GetUserMovieFavorites(user_id, page, page_size)` | Paginated movie favorites |
| `sp_GetUserTVFavorites(user_id, page, page_size)` | Paginated TV favorites |
| `sp_GetUserReviews(user_id, page, page_size)` | All reviews by a user |
| `sp_GetAuditLog(table, from, to, page, page_size)` | Paginated audit log |
| `sp_GetETLLog(status, page, page_size)` | ETL run history with duration |
| `sp_GetSystemConfig(key)` | Read system configuration |
| `sp_GetMoviesNeedingETLSync(interval, limit)` | Movies overdue for re-sync |
| `sp_GetTVSeriesNeedingETLSync(interval, limit)` | TV series overdue for re-sync |

---

## Usage

Run files in order against your PostgreSQL database:

```bash
psql -U <user> -d <database> -f sql/01_create_tables.sql
psql -U <user> -d <database> -f sql/02_functions_triggers_procedures.sql
```

**Requirements:** PostgreSQL 13+

---

## Notes

- Password hashing must be done at the application layer. `sp_InsertUser` accepts a pre-hashed value only.
- Soft deletes are implemented on the `User` table via `trg_soft_delete_user`. A `DELETE` statement will set `is_active = FALSE` instead of removing the row.
- `sp_UpsertMovie` uses `tmdb_movie_id` as the natural key for idempotent ETL runs.
- The audit trigger reads `app.current_user_id` from the session-level setting. Set it via `SET LOCAL app.current_user_id = <id>` in the application layer.

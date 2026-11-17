-- Extensões da busca por relevância (equivalente à migration 006). O banco é
-- criado pelo ETL, não pelo Alembic, então sem isto a API cai no modo ILIKE
-- (ordem alfabética e sensível a acento). Os índices GIN ficam a cargo da 006,
-- porque as tabelas ainda não existem quando este script roda.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE OR REPLACE FUNCTION f_unaccent(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$;

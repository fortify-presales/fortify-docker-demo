#!/bin/sh
set -eu

PGPASSWORD=$(cat /run/secrets/postgres-admin-password)
IQ_DATABASE_PASSWORD=$(cat /run/secrets/database-password)
[ -n "$PGPASSWORD" ] && [ -n "$IQ_DATABASE_PASSWORD" ] || {
    echo 'PostgreSQL administrator and IQ database secrets must be non-empty.' >&2
    exit 1
}
export PGPASSWORD IQ_DATABASE_PASSWORD

psql -h postgres -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
\getenv iq_password IQ_DATABASE_PASSWORD
SELECT format('CREATE ROLE iq LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L', :'iq_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'iq')
\gexec
SELECT 1 / CASE WHEN rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls
    THEN 1 ELSE 0 END AS iq_role_permissions_valid FROM pg_roles WHERE rolname = 'iq';
SELECT 'CREATE DATABASE iqserver OWNER iq'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'iqserver')
\gexec
SELECT 1 / CASE WHEN pg_get_userbyid(datdba) = 'iq' THEN 1 ELSE 0 END AS iq_database_owner_valid
FROM pg_database WHERE datname = 'iqserver';
SQL

PGPASSWORD=$IQ_DATABASE_PASSWORD psql -h postgres -U iq -d iqserver -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
printf 'IQ database and runtime role are ready. Existing data was preserved.\n'
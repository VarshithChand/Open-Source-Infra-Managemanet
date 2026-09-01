#!/bin/bash
# Runs once, on first container start, to create one database + owning role
# per entry in POSTGRES_MULTIPLE_DATABASES ("db:user:password,db:user:password").
# Lets Forgejo and SonarQube share one Postgres instance without sharing a
# login, instead of running a separate database container per service.
set -euo pipefail

create_database() {
	local db="$1" user="$2" password="$3"
	echo "Creating database '$db' and role '$user'"
	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
		CREATE ROLE "$user" WITH LOGIN PASSWORD '$password';
		CREATE DATABASE "$db" OWNER "$user";
		GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$user";
	EOSQL
}

if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
	IFS=',' read -ra ENTRIES <<< "$(echo "$POSTGRES_MULTIPLE_DATABASES" | tr -d '[:space:]')"
	for entry in "${ENTRIES[@]}"; do
		IFS=':' read -r db user password <<< "$entry"
		create_database "$db" "$user" "$password"
	done
	echo "Multiple databases created"
fi

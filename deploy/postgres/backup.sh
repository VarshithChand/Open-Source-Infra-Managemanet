#!/bin/sh
# Dumps every database on the shared Postgres instance and uploads each dump
# to a MinIO bucket, then repeats on an interval. Runs once immediately on
# start (so a fresh deploy gets an instant backup, not a 24h wait) rather
# than waiting for the first interval to elapse.
set -eu

MC_BIN=/usr/local/bin/mc
if [ ! -x "$MC_BIN" ]; then
	echo "Installing mc client..."
	wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O "$MC_BIN"
	chmod +x "$MC_BIN"
fi

mc alias set backupminio "http://minio:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb -p backupminio/db-backups >/dev/null 2>&1 || true
mc version enable backupminio/db-backups >/dev/null 2>&1 || true

DATABASES="forgejo sonarqube"

run_backup() {
	timestamp="$(date +%Y%m%d-%H%M%S)"
	for db in $DATABASES; do
		dump_file="/tmp/${db}-${timestamp}.dump"
		echo "$(date -Iseconds) backing up database '$db'..."
		if pg_dump -Fc "$db" >"$dump_file"; then
			mc cp "$dump_file" "backupminio/db-backups/${db}/${db}-${timestamp}.dump"
			echo "$(date -Iseconds) uploaded ${db}-${timestamp}.dump"
		else
			echo "$(date -Iseconds) ERROR: pg_dump failed for '$db'" >&2
		fi
		rm -f "$dump_file"
	done
}

while true; do
	run_backup
	echo "$(date -Iseconds) next backup in ${BACKUP_INTERVAL_SECONDS}s"
	sleep "$BACKUP_INTERVAL_SECONDS"
done

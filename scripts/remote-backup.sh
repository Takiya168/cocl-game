#!/usr/bin/env bash
set -uo pipefail

# Runs on the remote server. Creates a backup of the cocl-game project,
# its MySQL databases and Redis data inside $1.
OUT="${1:?usage: remote-backup.sh OUT_DIR}"
mkdir -p "$OUT/mysql" "$OUT/redis" "$OUT/files" "$OUT/metadata"

echo "backup-start: $(date -Iseconds)"

# Locate the deployed project. Prefer the release layout with
# frontend/game.html + backend/server.js, fall back to a single-folder app.
PROJECT_DIR=""
for base in /root /home /www /var/www /opt /srv /usr/share/nginx; do
  while IFS= read -r f; do
    d="$(dirname "$f")"
    release_root="$(dirname "$d")"
    if [ -f "$release_root/frontend/game.html" ] && [ -f "$release_root/backend/server.js" ]; then
      PROJECT_DIR="$release_root"
      break 2
    fi
    if [ -f "$d/api/server.js" ]; then
      PROJECT_DIR="$d"
      break 2
    fi
  done < <(find -L "$base" -maxdepth 7 -type f -name game.html 2>/dev/null)
done

if [ -z "$PROJECT_DIR" ]; then
  echo "ERROR: could not find remote project (game.html + api/server.js)" >&2
  exit 1
fi

echo "project-dir: $PROJECT_DIR"
echo "$PROJECT_DIR" > "$OUT/metadata/remote-project-dir.txt"

# ---------- metadata ----------
{
  echo "=== date ==="; date -Iseconds
  echo "=== hostname ==="; hostname
  echo "=== uname ==="; uname -a
  echo "=== pm2 list ==="; pm2 list 2>&1 || true
  echo "=== systemd units ==="; systemctl list-units --type=service --state=running 2>&1 | head -50 || true
  echo "=== crontab ==="; crontab -l 2>&1 || true
  echo "=== nginx -T ==="; nginx -T 2>&1 || true
  echo "=== node ==="; node -v 2>&1 || true
  echo "=== npm ==="; npm -v 2>&1 || true
  echo "=== mysql ==="; mysql --version 2>&1 || true
  echo "=== redis ==="; redis-cli --version 2>&1 || true
  echo "=== listening ports ==="; ss -lntp 2>&1 || true
  echo "=== memory ==="; free -m 2>&1 || true
  echo "=== disk ==="; df -h 2>&1 || true
  echo "=== node processes ==="; ps aux 2>&1 | grep -E 'node|pm2|redis|mysql' | grep -v grep || true
} > "$OUT/metadata/server-info.txt" 2>&1 || true

# ---------- MySQL ----------
MYSQL_DUMP="$OUT/mysql/all-databases.sql"
MYSQL_ARGS=()
if mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then
  MYSQL_ARGS=(-uroot)
elif mysql -uroot -p1 -e 'SELECT 1' >/dev/null 2>&1; then
  MYSQL_ARGS=(-uroot -p1)
else
  SERVER_PWD="$(sed -n "s/.*password: *'\([^']*\)'.*/\1/p" "$PROJECT_DIR/api/server.js" | head -1)"
  if [ -n "$SERVER_PWD" ] && mysql -uroot -p"$SERVER_PWD" -e 'SELECT 1' >/dev/null 2>&1; then
    MYSQL_ARGS=(-uroot -p"$SERVER_PWD")
  fi
fi

if [ "${#MYSQL_ARGS[@]}" -gt 0 ]; then
  mysqldump "${MYSQL_ARGS[@]}" \
    --all-databases --single-transaction --routines --triggers --events \
    --skip-lock-tables --result-file="$MYSQL_DUMP" 2> "$OUT/metadata/mysqldump-errors.txt" \
    && echo "mysql-dump: ok" || echo "mysql-dump: failed (see metadata/mysqldump-errors.txt)"
  mysql "${MYSQL_ARGS[@]}" -e 'SHOW DATABASES' 2>/dev/null > "$OUT/metadata/mysql-databases.txt" || true
else
  echo "mysql-dump: skipped (no working root auth)" > "$OUT/metadata/mysqldump-errors.txt"
fi

# ---------- Redis ----------
REDIS_RDB="$OUT/redis/dump.rdb"
if redis-cli --rdb "$REDIS_RDB" > "$OUT/metadata/redis-rdb.txt" 2>&1; then
  echo "redis-rdb: ok"
else
  if redis-cli SAVE >/dev/null 2>&1; then
    REDIS_DIR="$(redis-cli CONFIG GET dir 2>/dev/null | tail -1)"
    [ -n "$REDIS_DIR" ] && cp "$REDIS_DIR/dump.rdb" "$REDIS_RDB" 2>/dev/null || true
  fi
  echo "redis-rdb: fallback attempted"
fi
redis-cli INFO 2>/dev/null > "$OUT/metadata/redis-info.txt" || true
redis-cli --scan --pattern '*' 2>/dev/null | sort > "$OUT/metadata/redis-keys.txt" || true

# ---------- project files ----------
tar -C "$(dirname "$PROJECT_DIR")" -h \
  --exclude=node_modules --exclude='*/.git/*' \
  -czf "$OUT/files/project.tar.gz" "$(basename "$PROJECT_DIR")" \
  && echo "project-tar: ok"

find -L "$PROJECT_DIR" -type f \
  -not -path '*/node_modules/*' -not -path '*/.git/*' \
  | sort > "$OUT/files/remote-file-list.txt"

du -sh "$OUT" > "$OUT/metadata/backup-size.txt" 2>&1 || true
echo "backup-end: $(date -Iseconds)"

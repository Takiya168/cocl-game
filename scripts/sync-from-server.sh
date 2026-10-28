#!/usr/bin/env bash
set -euo pipefail

# Downloads a fresh server backup into server-backup/<timestamp> and writes a
# local/remote diff report. Requires sshpass and outbound SSH access.
#
# Optional env: SERVER_HOST, SERVER_USER, SERVER_PASS, SSH_PORT

SERVER_HOST="${SERVER_HOST:-47.109.207.98}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PASS="${SERVER_PASS:-Ulyh051002U!}"
SSH_PORT="${SSH_PORT:-22}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="$PROJECT_ROOT/server-backup"
STAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_TMP="/tmp/cocl-backup-$STAMP"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "ERROR: sshpass is required (brew install sshpass)." >&2
  exit 1
fi

SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20 -o LogLevel=ERROR)
SSH=(sshpass -p "$SERVER_PASS" ssh "${SSH_OPTS[@]}" "$SERVER_USER@$SERVER_HOST")
SCP=(sshpass -p "$SERVER_PASS" scp -P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20 -o LogLevel=ERROR)

mkdir -p "$BACKUP_ROOT"

echo ">> Uploading remote backup script"
"${SCP[@]}" "$PROJECT_ROOT/scripts/remote-backup.sh" "$SERVER_USER@$SERVER_HOST:/tmp/remote-backup.sh"

echo ">> Running backup on server"
"${SSH[@]}" "bash /tmp/remote-backup.sh '$REMOTE_TMP'"

echo ">> Downloading backup"
"${SCP[@]}" -r "$SERVER_USER@$SERVER_HOST:$REMOTE_TMP" "$BACKUP_ROOT/$STAMP"

echo ">> Cleaning remote temp files"
"${SSH[@]}" "rm -rf '$REMOTE_TMP' /tmp/remote-backup.sh" || true

echo ">> Extracting project snapshot for local browsing"
mkdir -p "$BACKUP_ROOT/$STAMP/files/remote-project"
tar -xzf "$BACKUP_ROOT/$STAMP/files/project.tar.gz" -C "$BACKUP_ROOT/$STAMP/files/remote-project"

REMOTE_PROJECT_DIR="$(cat "$BACKUP_ROOT/$STAMP/metadata/remote-project-dir.txt")"
REMOTE_FILE_LIST="$BACKUP_ROOT/$STAMP/files/remote-file-list.txt"
DIFF_REPORT="$BACKUP_ROOT/$STAMP/diff-report.txt"

{
  echo "Remote project dir: $REMOTE_PROJECT_DIR"
  echo "Backup created: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo ""
  echo "== Remote files missing locally =="
  while IFS= read -r abs; do
    rel="${abs#"$REMOTE_PROJECT_DIR"/}"
    if [ "$rel" = "$abs" ]; then
      continue
    fi
    if [ ! -e "$PROJECT_ROOT/$rel" ]; then
      echo "MISSING: $rel"
    fi
  done < "$REMOTE_FILE_LIST"
  echo ""
  echo "== Local files not seen in remote project (excluding backup/scripts) =="
  (cd "$PROJECT_ROOT" && find . -type f \
    -not -path './.git/*' -not -path './server-backup/*' -not -path './scripts/*' \
    -not -name '.DS_Store' -not -name '.gitignore' | sed 's|^\./||') |
  while IFS= read -r rel; do
    if ! grep -q "^$REMOTE_PROJECT_DIR/$rel$" "$REMOTE_FILE_LIST"; then
      echo "LOCAL_ONLY: $rel"
    fi
  done
} > "$DIFF_REPORT"

ln -sfn "$STAMP" "$BACKUP_ROOT/latest"
echo ""
echo "Done. Backup stored in:"
echo "  $BACKUP_ROOT/$STAMP"
echo "Diff report:"
echo "  $DIFF_REPORT"

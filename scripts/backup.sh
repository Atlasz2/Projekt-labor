#!/usr/bin/env bash
# ============================================================
# Firestore + Storage napi backup
# Futtatás: bash scripts/backup.sh
# Előfeltétel: gcloud CLI telepítve és autorizálva
# ============================================================
set -euo pipefail

PROJECT_ID="projekt-labor-a4b1c"
BACKUP_BUCKET="gs://${PROJECT_ID}-backups"
DATE=$(date +%Y%m%d_%H%M)

echo "[backup] Firestore export kezdése..."
gcloud firestore export "${BACKUP_BUCKET}/firestore/${DATE}" \
  --project="${PROJECT_ID}" \
  --async

echo "[backup] Storage sync kezdése..."
gsutil -m rsync -r \
  "gs://${PROJECT_ID}.appspot.com" \
  "${BACKUP_BUCKET}/storage/${DATE}"

echo "[backup] Kész: ${DATE}"

# Régi backupok törlése (90 napnál régebbi)
CUTOFF=$(date -d "90 days ago" +%Y%m%d 2>/dev/null || date -v -90d +%Y%m%d)
echo "[backup] Régi backupok takarítása (előtte: ${CUTOFF})..."
gsutil ls "${BACKUP_BUCKET}/firestore/" | while read -r entry; do
  ENTRY_DATE=$(basename "$entry" | cut -c1-8)
  if [[ "$ENTRY_DATE" =~ ^[0-9]{8}$ ]] && [[ "$ENTRY_DATE" -lt "$CUTOFF" ]]; then
    gsutil -m rm -r "$entry"
    echo "[backup] Törölve: $entry"
  fi
done

echo "[backup] Backup folyamat befejezve."
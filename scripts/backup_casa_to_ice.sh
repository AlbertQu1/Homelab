#!/bin/bash
# Monta la SD "postgres_backup" (lector interno del Mac mini), hace un pg_dump
# completo de la base "casa", rota respaldos viejos (conserva los ultimos 4)
# y desmonta. Corre como root via systemd (backup-casa.service), necesita
# root para mount/umount; el pg_dump en si corre como albertqu via runuser
# para que la autenticacion peer de Postgres funcione igual que en modo manual.
set -euo pipefail

DISK_UUID="f074bd67-d06a-40ed-9cb8-3035d7d5c4d7"
MOUNT_POINT="/mnt/sdbackup"
BACKUP_DIR="$MOUNT_POINT/backups_casa"
RETENCION=4
ARCHIVO="backup_casa_$(date +%Y-%m-%d).sql"

mkdir -p "$MOUNT_POINT"
mount UUID="$DISK_UUID" "$MOUNT_POINT"

trap 'umount "$MOUNT_POINT"' EXIT

mkdir -p "$BACKUP_DIR"
chown albertqu:albertqu "$BACKUP_DIR"
runuser -u albertqu -- pg_dump -U albertqu -d casa -f "$BACKUP_DIR/$ARCHIVO"

ls -t "$BACKUP_DIR"/backup_casa_*.sql 2>/dev/null | tail -n +$((RETENCION + 1)) | while read -r viejo; do
  echo "Borrando respaldo viejo: $viejo"
  rm -f -- "$viejo"
done

echo "Respaldo completado: $BACKUP_DIR/$ARCHIVO"

#!/bin/bash
# monitor_mac.sh - version Linux

sleep 15

# --- Recolectar metricas ---
SENSORS=$(sensors)
TEMP_DIE=$(echo "$SENSORS" | grep 'Package id 0' | grep -oP '\+\K[0-9]+\.[0-9]+' | head -1)
TEMP_PROXIMITY=$(echo "$SENSORS" | grep '^TC0P' | grep -oP '\+\K[0-9]+\.[0-9]+' | head -1)
FAN=$(echo "$SENSORS" | grep 'Exhaust' | grep -oP '[0-9]+' | head -1)
CPU_USO=$(top -bn1 | grep '%Cpu' | awk '{print 100 - $8}')
RAM_LIBRE_MB=$(free -m | awk '/^Mem:/ {print $7}')
DISCO_LIBRE=$(df -h / | tail -1 | awk '{print $4}')
UPTIME=$(uptime | sed 's/^ *//')
PROCESO_TOP=$(ps -eo %cpu,comm --sort=-%cpu | sed -n '2p' | awk '{print $2}')

# --- Insertar en Postgres ---
psql -U albertqu -d casa -c "
INSERT INTO mac_metrics.metricas (temperatura_die_c, temperatura_proximity_c, fan_rpm, cpu_uso_pct, ram_libre_mb, disco_libre, uptime, proceso_top)
VALUES ('$TEMP_DIE', '$TEMP_PROXIMITY', '$FAN', '$CPU_USO', '$RAM_LIBRE_MB', '$DISCO_LIBRE', '$UPTIME', '$PROCESO_TOP');
"

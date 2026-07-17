#!/bin/bash
# monitor_mac.sh

# --- Recolectar mtricas ---
PM_OUTPUT=$(/usr/bin/sudo /usr/bin/powermetrics --samplers smc -i1 -n1 2>/dev/null)
TEMP_DIE=$(echo "$PM_OUTPUT" | grep "CPU die temperature" | awk '{print $4}')
FAN=$(echo "$PM_OUTPUT" | grep "Fan:" | awk '{print $2}')

TEMP_PROXIMITY=$(/usr/local/bin/osx-cpu-temp | sed -E 's/[^0-9.]//g')

CPU_USO=$(/usr/bin/top -l 1 | grep "CPU usage" | awk '{print 100-$7}')

RAM_LIBRE_PAGINAS=$(/usr/bin/vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
RAM_LIBRE_MB=$(( RAM_LIBRE_PAGINAS * 4096 / 1024 / 1024 ))

DISCO_LIBRE=$(/bin/df -h / | tail -1 | awk '{print $4}')

UPTIME=$(/usr/bin/uptime | sed 's/^ *//')

PROCESO_TOP=$(/bin/ps -Ao %cpu,comm -r | sed -n '2p' | awk '{print $2}')

# --- Insertar en Postgres ---
/usr/local/bin/psql -U albertqu -d casa -c "
INSERT INTO mac_metrics.metricas (temperatura_die_c, temperatura_proximity_c, fan_rpm, cpu_uso_pct, ram_libre_mb, disco_libre, uptime, proceso_top)
VALUES ('$TEMP_DIE', '$TEMP_PROXIMITY', '$FAN', '$CPU_USO', '$RAM_LIBRE_MB', '$DISCO_LIBRE', '$UPTIME', '$PROCESO_TOP');
"

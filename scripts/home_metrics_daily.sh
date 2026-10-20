#!/bin/bash
# home_metrics_daily.sh - resumen diario (1 promedio/dia) de sensores Home Assistant -> casa.home_assistant.daily_summary
# Estancias/entidades actuales: cocina (Cleargrass sg_blt_1_108g127t14000, reemplazo del Xiaomi 703e desde 2026-08-12), cuarto (SwitchBot Hub 2 d1a4)

psql -U albertqu -d casa -v ON_ERROR_STOP=1 << 'EOF'
WITH mapeo(entity_id, estancia, metrica, unidad) AS (
  VALUES
    ('sensor.cleargras_sg_blt_1_108g127t14000_dk1_temperature_p_2_1',       'cocina', 'temperature', 'C'),
    ('sensor.cleargras_sg_blt_1_108g127t14000_dk1_relative_humidity_p_2_2', 'cocina', 'humidity',    '%'),
    ('sensor.hub_2_d1a4_temperature',                                      'cuarto', 'temperature', 'C'),
    ('sensor.hub_2_d1a4_humidity',                                         'cuarto', 'humidity',    '%')
),
lecturas AS (
  SELECT m.estancia, m.metrica, m.unidad, s.state::numeric AS valor
  FROM home_assistant.states s
  JOIN home_assistant.states_meta sm ON sm.metadata_id = s.metadata_id
  JOIN mapeo m ON m.entity_id = sm.entity_id
  WHERE s.state ~ '^-?[0-9]+(\.[0-9]+)?$'
    AND (to_timestamp(s.last_updated_ts) AT TIME ZONE 'America/Mexico_City')::date
        = (now() AT TIME ZONE 'America/Mexico_City')::date
)
INSERT INTO home_assistant.daily_summary (fecha, estancia, metrica, promedio, minimo, maximo, unidad, muestras)
SELECT (now() AT TIME ZONE 'America/Mexico_City')::date, estancia, metrica,
       ROUND(AVG(valor), 2), MIN(valor), MAX(valor), unidad, COUNT(*)
FROM lecturas
GROUP BY estancia, metrica, unidad
ON CONFLICT (fecha, estancia, metrica) DO UPDATE SET
  promedio = EXCLUDED.promedio,
  minimo   = EXCLUDED.minimo,
  maximo   = EXCLUDED.maximo,
  unidad   = EXCLUDED.unidad,
  muestras = EXCLUDED.muestras;
EOF

# Aperturas por hora (ventanas, cortinas) -> home_assistant.aperturas_horarias.
# Recalcula los ultimos 9 dias en cada corrida (HA purga states a los 10).
psql -U albertqu -d casa -v ON_ERROR_STOP=1 -q -f /home/albertqu/scripts/aperturas_horarias.sql

# Recarga la integracion Xiaomi Home si algun sensor lumi (ventanas, movimiento)
# quedo "unavailable": tras el reinicio semanal no siempre reconecta sola.
# No detiene el resto del script si HA no responde.
set -a; . /home/albertqu/scripts/home_assistant.env; set +a
caidos=$(curl -sf -m 20 -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/states" | python3 -c '
import json, sys
print(sum(1 for x in json.load(sys.stdin)
          if x["entity_id"].startswith("binary_sensor.lumi_sg_") and x["state"] == "unavailable"))
' 2>/dev/null)
if [ -n "$caidos" ] && [ "$caidos" -gt 0 ]; then
  entry=$(curl -sf -m 20 -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/config/config_entries/entry?domain=xiaomi_home" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)[0]["entry_id"])' 2>/dev/null)
  if [ -n "$entry" ] && curl -sf -m 60 -X POST -H "Authorization: Bearer $HA_TOKEN" \
       "$HA_URL/api/config/config_entries/entry/$entry/reload" > /dev/null; then
    echo "xiaomi_home recargada ($caidos sensores lumi unavailable)"
  else
    echo "xiaomi_home: fallo la recarga ($caidos sensores lumi unavailable)" >&2
  fi
fi

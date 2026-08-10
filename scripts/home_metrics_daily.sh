#!/bin/bash
# home_metrics_daily.sh - resumen diario (1 promedio/dia) de sensores Home Assistant -> casa.home_assistant.daily_summary
# Estancias/entidades actuales: cocina (Xiaomi 703e), cuarto (SwitchBot Hub 2 d1a4)

psql -U albertqu -d casa -v ON_ERROR_STOP=1 << 'EOF'
WITH mapeo(entity_id, estancia, metrica, unidad) AS (
  VALUES
    ('sensor.temperature_humidity_sensor_703e_temperature', 'cocina', 'temperature', 'C'),
    ('sensor.temperature_humidity_sensor_703e_humidity',    'cocina', 'humidity',    '%'),
    ('sensor.hub_2_d1a4_temperature',                       'cuarto', 'temperature', 'C'),
    ('sensor.hub_2_d1a4_humidity',                          'cuarto', 'humidity',    '%')
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

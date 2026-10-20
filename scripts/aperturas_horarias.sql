-- aperturas_horarias.sql - % de tiempo abierto por hora de ventanas, puerta y cortinas
-- (HA states -> casa.home_assistant.aperturas_horarias). Recalcula los ultimos 9 dias en
-- cada corrida (HA purga states a los 10), asi que perder una corrida no deja huecos.
-- Idempotente: upsert por (hora, entity_id). Solo calcula horas ya cerradas.

WITH params AS (
  SELECT date_trunc('hour', (now() AT TIME ZONE 'America/Mexico_City') - interval '9 days') AS desde,
         date_trunc('hour', now() AT TIME ZONE 'America/Mexico_City') AS hasta
),
crudos AS (
  SELECT e.entity_id, e.tipo,
         to_timestamp(s.last_updated_ts) AT TIME ZONE 'America/Mexico_City' AS t,
         s.state,
         (a.shared_attrs::json ->> 'current_position')::numeric AS posicion
  FROM home_assistant.states s
  JOIN home_assistant.states_meta sm ON sm.metadata_id = s.metadata_id
  JOIN home_assistant.aperturas_elementos e ON e.entity_id = sm.entity_id
  LEFT JOIN home_assistant.state_attributes a ON a.attributes_id = s.attributes_id
),
-- Valor numerico de cada estado: 0-100 de apertura, NULL si no hay dato
estados AS (
  SELECT entity_id, tipo, t, state,
         CASE
           WHEN state IN ('unavailable', 'unknown') THEN NULL
           WHEN tipo = 'cortina' THEN posicion
           WHEN state = 'on' THEN 100
           WHEN state = 'off' THEN 0
         END AS valor,
         lead(t) OVER (PARTITION BY entity_id ORDER BY t) AS t_fin
  FROM crudos
),
-- Cada estado dura hasta el siguiente cambio (el ultimo, hasta ahora)
intervalos AS (
  SELECT e.entity_id, e.tipo, e.state, e.valor, e.t AS ini,
         coalesce(e.t_fin, p.hasta) AS fin
  FROM estados e CROSS JOIN params p
),
horas AS (
  SELECT ae.entity_id, h AS hora
  FROM home_assistant.aperturas_elementos ae
  CROSS JOIN params p
  CROSS JOIN generate_series(p.desde, p.hasta - interval '1 hour', interval '1 hour') h
),
-- Recorte de cada intervalo a cada hora que toca
tramos AS (
  SELECT h.entity_id, h.hora, i.valor, i.state, i.ini,
         extract(epoch FROM least(i.fin, h.hora + interval '1 hour') - greatest(i.ini, h.hora)) / 60.0 AS minutos
  FROM horas h
  JOIN intervalos i ON i.entity_id = h.entity_id
   AND i.ini < h.hora + interval '1 hour' AND i.fin > h.hora
),
resumen AS (
  SELECT h.hora, h.entity_id,
         sum(t.minutos * t.valor) FILTER (WHERE t.valor IS NOT NULL)
           / nullif(sum(t.minutos) FILTER (WHERE t.valor IS NOT NULL), 0) AS pct_abierto,
         coalesce(sum(t.minutos) FILTER (WHERE t.valor > 0), 0) AS minutos_abierto,
         count(*) FILTER (WHERE t.ini >= h.hora AND t.state IN ('on', 'opening')) AS aperturas,
         60 - coalesce(sum(t.minutos) FILTER (WHERE t.valor IS NOT NULL), 0) AS minutos_sin_dato
  FROM horas h
  LEFT JOIN tramos t ON t.entity_id = h.entity_id AND t.hora = h.hora
  GROUP BY h.hora, h.entity_id
)
INSERT INTO home_assistant.aperturas_horarias
  (hora, entity_id, pct_abierto, minutos_abierto, aperturas, minutos_sin_dato)
SELECT hora, entity_id, round(pct_abierto, 1), round(minutos_abierto, 1), aperturas,
       round(greatest(minutos_sin_dato, 0), 1)
FROM resumen
ON CONFLICT (hora, entity_id) DO UPDATE SET
  pct_abierto      = EXCLUDED.pct_abierto,
  minutos_abierto  = EXCLUDED.minutos_abierto,
  aperturas        = EXCLUDED.aperturas,
  minutos_sin_dato = EXCLUDED.minutos_sin_dato;

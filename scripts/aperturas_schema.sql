\restrict zi651YWKSNujBD4ftQ77KRXB4LOCcjoDadkH4iLaeuxpho7KeT9gdb7Fg8XC1hN
CREATE TABLE home_assistant.aperturas_elementos (
    entity_id text NOT NULL,
    nombre text NOT NULL,
    tipo text NOT NULL,
    estancia text,
    CONSTRAINT aperturas_elementos_tipo_check CHECK ((tipo = ANY (ARRAY['ventana'::text, 'cortina'::text, 'puerta'::text])))
);
ALTER TABLE home_assistant.aperturas_elementos OWNER TO albertqu;
CREATE TABLE home_assistant.aperturas_horarias (
    hora timestamp without time zone NOT NULL,
    entity_id text NOT NULL,
    pct_abierto numeric(5,1),
    minutos_abierto numeric(5,1),
    aperturas integer DEFAULT 0 NOT NULL,
    minutos_sin_dato numeric(5,1) NOT NULL
);
ALTER TABLE home_assistant.aperturas_horarias OWNER TO albertqu;
ALTER TABLE ONLY home_assistant.aperturas_elementos
    ADD CONSTRAINT aperturas_elementos_pkey PRIMARY KEY (entity_id);
ALTER TABLE ONLY home_assistant.aperturas_horarias
    ADD CONSTRAINT aperturas_horarias_pkey PRIMARY KEY (hora, entity_id);
ALTER TABLE ONLY home_assistant.aperturas_horarias
    ADD CONSTRAINT aperturas_horarias_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES home_assistant.aperturas_elementos(entity_id);
\unrestrict zi651YWKSNujBD4ftQ77KRXB4LOCcjoDadkH4iLaeuxpho7KeT9gdb7Fg8XC1hN

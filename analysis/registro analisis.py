import os
import psycopg2
import pandas as pd
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "host": os.environ.get("POSTGRES_HOST"),
    "port": os.environ.get("POSTGRES_PORT"),
    "dbname": os.environ.get("POSTGRES_DB"),
    "user": os.environ.get("POSTGRES_USER"),
    "password": os.environ.get("POSTGRES_PASSWORD"),
}


def conectar():
    try:
        return psycopg2.connect(**DB_CONFIG)
    except psycopg2.OperationalError:
        return None


def ver_eventos_con_temperatura(minutos_ventana=20):
    conn = conectar()
    if conn is None:
        print("\n🔌 Servidor desconectado")
        return None

    df = pd.read_sql(
        f"""
        SELECT 
            p.descripcion,
            p.fecha,
            p.hora AS hora_evento,
            m.temperatura_die_c,
            m.temperatura_proximity_c,
            (m.temperatura_die_c - m.temperatura_proximity_c) AS diferencia,
            m.cpu_uso_pct,
            TO_CHAR(m.registro, 'HH24:MI:SS') AS hora_lectura
        FROM mac_metrics.pruebas p
        JOIN mac_metrics.metricas m 
            ON m.registro::date = p.fecha
            AND p.hora IS NOT NULL
            AND m.registro >= (p.fecha + p.hora::time)
            AND m.registro <= (p.fecha + p.hora::time + INTERVAL '{minutos_ventana} minutes')
        ORDER BY p.fecha, p.hora, m.registro;
        """,
        conn,
    )
    conn.close()
    return df


if __name__ == "__main__":
    df = ver_eventos_con_temperatura()
    if df is not None and not df.empty:
        print("\n--- Eventos cruzados con temperatura ---")
        print(df.to_string(index=False))
    elif df is not None:
        print("\nNo se encontraron eventos con lecturas asociadas.")
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


def ver_procesos_recientes(n=10):
    conn = conectar()
    if conn is None:
        print("\n🔌 Servidor desconectado")
        return

    df = pd.read_sql(
        f"""
        SELECT 
            id,
            temperatura_die_c,
            fan_rpm,
            cpu_uso_pct,
            proceso_top,
            TO_CHAR(registro, 'HH24:MI:SS') AS hora
        FROM mac_metrics.metricas
        ORDER BY registro DESC
        LIMIT {n};
        """,
        conn,
    )
    conn.close()

    print(f"\n--- Ultimas {n} lecturas: proceso top ---")
    print(df.to_string(index=False))


if __name__ == "__main__":
    ver_procesos_recientes()
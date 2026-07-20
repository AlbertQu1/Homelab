import os
import sys
import psycopg2
from dotenv import load_dotenv
from datetime import datetime

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


def registrar_evento(descripcion):
    conn = conectar()
    if conn is None:
        print("\n🔌 Servidor desconectado")
        return

    fecha = datetime.now().date()
    hora = datetime.now().time().strftime("%H:%M")

    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO mac_metrics.pruebas (fecha, hora, descripcion)
        VALUES (%s, %s, %s);
        """,
        (fecha, hora, descripcion),
    )
    conn.commit()
    conn.close()
    print(f"✅ Registrado: [{fecha} {hora}] {descripcion}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print('Uso: python registrar_escenario.py "descripcion del evento"')
        sys.exit(1)

    descripcion = sys.argv[1]
    registrar_evento(descripcion)
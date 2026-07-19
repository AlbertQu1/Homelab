import psycopg2
import os
import pandas as pd
import matplotlib.pyplot as plt

DB_CONFIG = {
    "host": os.environ.get("POSTGRES_HOST"),
    "port": os.environ.get("POSTGRES_PORT"),
    "database": os.environ.get("POSTGRES_DB"),
    "user": os.environ.get("POSTGRES_USER"),
    "password": os.environ.get("POSTGRES_PASSWORD"),
}

UMBRAL_ALERTA = 65  # °C


def conectar():
    return psycopg2.connect(**DB_CONFIG)


def ver_ultima_lectura():
    conn = conectar()
    cur = conn.cursor()
    cur.execute("""
        SELECT temperatura_die_c, temperatura_proximity_c, fan_rpm, cpu_uso_pct, registro
        FROM mac_metrics.metricas
        ORDER BY registro DESC
        LIMIT 1;
    """)
    row = cur.fetchone()
    conn.close()

    if row is None:
        print("No hay datos todavía.")
        return

    temp_die, temp_prox, fan, cpu, registro = row
    diferencia = (
        temp_die - temp_prox
        if (temp_die is not None and temp_prox is not None)
        else None
    )

    print(f"\n--- Última lectura: {registro} ---")
    print(f"Temp die:       {temp_die}°C")
    print(f"Temp proximity: {temp_prox}°C")
    if diferencia is not None:
        print(f"Diferencia:     {diferencia:.2f}°C")
    print(f"Fan:            {fan} RPM")
    print(f"CPU uso:        {cpu}%")

    if temp_die and temp_die > UMBRAL_ALERTA:
        print(f"⚠️  ALERTA: temperatura por encima de {UMBRAL_ALERTA}°C")


def ver_historial():
    conn = conectar()
    df = pd.read_sql(
        """
        SELECT temperatura_die_c, temperatura_proximity_c, fan_rpm, cpu_uso_pct, registro
        FROM mac_metrics.metricas
        ORDER BY registro ASC;
    """,
        conn,
    )
    conn.close()

    # --- Análisis en Python, no en SQL ---
    df["diferencia"] = df["temperatura_die_c"] - df["temperatura_proximity_c"]

    return df


def resumen_estadistico(df):
    print("\n--- Resumen estadístico ---")
    print(
        f"Temp die   -> min: {df['temperatura_die_c'].min()}°C | max: {df['temperatura_die_c'].max()}°C | promedio: {df['temperatura_die_c'].mean():.2f}°C"
    )
    print(
        f"Diferencia -> min: {df['diferencia'].min():.2f}°C | max: {df['diferencia'].max():.2f}°C | promedio: {df['diferencia'].mean():.2f}°C"
    )
    print(
        f"Fan RPM    -> min: {df['fan_rpm'].min()} | max: {df['fan_rpm'].max()} | promedio: {df['fan_rpm'].mean():.0f}"
    )


def graficar(df):
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

    # --- Gráfica 1: temperaturas ---
    ax1.plot(df["registro"], df["temperatura_die_c"], label="Die", marker="o")
    ax1.plot(
        df["registro"], df["temperatura_proximity_c"], label="Proximity", marker="o"
    )
    ax1.axhline(
        y=UMBRAL_ALERTA, color="r", linestyle="--", label=f"Umbral ({UMBRAL_ALERTA}°C)"
    )
    ax1.set_ylabel("Temperatura (°C)")
    ax1.set_title("Temperatura del Mac mini")
    ax1.legend()

    # --- Gráfica 2: diferencia entre sensores ---
    ax2.plot(
        df["registro"],
        df["diferencia"],
        label="Diferencia (die - proximity)",
        color="purple",
        marker="o",
    )
    ax2.set_ylabel("Diferencia (°C)")
    ax2.set_xlabel("Hora")
    ax2.legend()

    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    ver_ultima_lectura()
    df = ver_historial()
    print(f"\nTotal de lecturas registradas: {len(df)}")
    resumen_estadistico(df)
    graficar(df)

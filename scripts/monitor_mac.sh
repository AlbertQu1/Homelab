#!/bin/bash
# monitor_mac.sh - version Linux

# --- Niveles de alerta termica (temp_die en C) ---
NIVEL0_TEMP=50   # vigilancia
NIVEL1_TEMP=55   # alerta temprana
NIVEL2_TEMP=65   # reporte de top procesos + parar n8n
NIVEL3_TEMP=75   # contencion: parar Docker excepto homeassistant
NIVEL4_TEMP=80   # ultima instancia: apagado total (switch fisico)

# --- Lecturas consecutivas (~5 min c/u, ver monitor-mac.timer) requeridas
# antes de ejecutar cada accion. Evita reaccionar a picos de CPU de un solo
# ciclo: el 2026-08-08 y 2026-08-09 un pico de segundos (max visto: 78C)
# disparo el apagado fisico dos veces sin que hubiera sobrecalentamiento
# real. NIVEL4 ahora esta lo bastante arriba de ese pico (80C) que actua
# de inmediato, sin esperar varias lecturas. ---
SOSTENIDO_NIVEL2=3   # ~15 min sostenido
SOSTENIDO_NIVEL3=2   # ~10 min sostenido
SOSTENIDO_NIVEL4=1   # inmediato, una sola lectura

LOG_ALERTAS="/home/albertqu/scripts/temp_alert.log"
ESTADO_DIR="/home/albertqu/scripts/.nivel_state"
mkdir -p "$ESTADO_DIR"
source /home/albertqu/scripts/home_assistant.env
SWITCH_EMERGENCIA="switch.escritorio_failsafe"
CONTENEDOR_PROTEGIDO="homeassistant"

push() {
    local title="$1" message="$2"
    curl -s -o /dev/null -X POST \
        -H "Authorization: Bearer ${HA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"${title}\", \"message\": \"${message}\"}" \
        "${HA_URL}/api/services/notify/mobile_app_qu_phone"
}

notificar() {
    local nivel="$1" temp="$2"
    push "Alerta termica NIVEL ${nivel}" "temp_die=${temp}C top=${PROCESO_TOP}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [notificar] NIVEL $nivel - temp_die=${temp}C top=${PROCESO_TOP} (push enviado)" >> "$LOG_ALERTAS"
}

reporte_procesos() {
    local top5
    top5=$(ps -eo %cpu,%mem,comm --sort=-%cpu | head -6 | tail -5 | awk '{printf "%s(cpu:%s%%,mem:%s%%) ", $3, $1, $2}')
    echo "$(date '+%Y-%m-%d %H:%M:%S') [reporte_procesos] temp_die=${TEMP_DIE}C top5: $top5" >> "$LOG_ALERTAS"
}

# Cuenta cuantas de las ultimas $k lecturas en Postgres (incluyendo la de
# este ciclo, ya insertada abajo) tienen temperatura_die_c >= $umbral.
# Solo es cierto (exit 0) si las $k lecturas seguidas cumplen - es decir,
# esta realmente sostenido y no es un pico aislado de un ciclo. Con k=1
# equivale a evaluar solo la lectura actual (accion inmediata).
lecturas_sostenidas() {
    local k="$1" umbral="$2"
    local cuenta
    cuenta=$(psql -U albertqu -d casa -tA -c "
        SELECT count(*) FROM (
            SELECT temperatura_die_c
            FROM mac_metrics.metricas
            ORDER BY registro DESC
            LIMIT ${k}
        ) t
        WHERE temperatura_die_c >= ${umbral};
    ")
    [[ "$cuenta" =~ ^[0-9]+$ ]] && [ "$cuenta" -eq "$k" ]
}

# Ejecuta $accion_fn una sola vez por "episodio" sostenido: si ya se disparo
# y sigue sostenido, no repite (evita spam de push/API cada 5 min). Se
# rearma solo cuando la temperatura baja del umbral otra vez.
gestionar_nivel() {
    local flag="$1" k="$2" umbral="$3" accion_fn="$4"
    if lecturas_sostenidas "$k" "$umbral"; then
        if [ ! -f "$flag" ]; then
            touch "$flag"
            "$accion_fn"
        fi
    else
        rm -f "$flag"
    fi
}

parar_n8n() {
    if systemctl is-active --quiet n8n.service; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [parar_n8n] Parando n8n por temperatura sostenida (${TEMP_DIE}C, ${SOSTENIDO_NIVEL2} lecturas >= ${NIVEL2_TEMP}C)" >> "$LOG_ALERTAS"
        # Requiere regla NOPASSWD en sudoers para "systemctl stop n8n.service"
        sudo systemctl stop n8n.service
        push "NIVEL 2 sostenido - n8n detenido" "temp_die=${TEMP_DIE}C sostenido ${SOSTENIDO_NIVEL2} lecturas seguidas, n8n parado"
    fi
}

detener_docker_excepto_ha() {
    local contenedores
    contenedores=$(docker ps --format '{{.Names}}' | grep -v "^${CONTENEDOR_PROTEGIDO}$")
    if [ -n "$contenedores" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [detener_docker_excepto_ha] Parando: $(echo "$contenedores" | tr '\n' ' ')" >> "$LOG_ALERTAS"
        echo "$contenedores" | xargs -r docker stop
        push "NIVEL 3 sostenido - Docker detenido" "temp_die=${TEMP_DIE}C sostenido ${SOSTENIDO_NIVEL3} lecturas seguidas, contenedores detenidos (excepto ${CONTENEDOR_PROTEGIDO})"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [detener_docker_excepto_ha] No hay contenedores que parar aparte de ${CONTENEDOR_PROTEGIDO}" >> "$LOG_ALERTAS"
    fi
}

apagar_switch() {
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${HA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"entity_id\": \"${SWITCH_EMERGENCIA}\"}" \
        "${HA_URL}/api/services/switch/turn_off")
    echo "$(date '+%Y-%m-%d %H:%M:%S') [apagar_switch] NIVEL 4 - apagado total (${TEMP_DIE}C, accion inmediata) - turn_off ${SWITCH_EMERGENCIA} (HTTP $http_code)" >> "$LOG_ALERTAS"
    push "NIVEL 4 - apagado total" "temp_die=${TEMP_DIE}C, switch fisico apagado de inmediato"
}

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

# --- Evaluar nivel de alerta termica (lectura instantanea, solo para el aviso push) ---
if [ -n "$TEMP_DIE" ]; then
    if (( $(echo "$TEMP_DIE >= $NIVEL4_TEMP" | bc -l) )); then
        NIVEL=4
    elif (( $(echo "$TEMP_DIE >= $NIVEL3_TEMP" | bc -l) )); then
        NIVEL=3
    elif (( $(echo "$TEMP_DIE >= $NIVEL2_TEMP" | bc -l) )); then
        NIVEL=2
    elif (( $(echo "$TEMP_DIE >= $NIVEL1_TEMP" | bc -l) )); then
        NIVEL=1
    elif (( $(echo "$TEMP_DIE >= $NIVEL0_TEMP" | bc -l) )); then
        NIVEL=0
    else
        NIVEL=-1
    fi

    if [ "$NIVEL" -ge 0 ]; then
        notificar "$NIVEL" "$TEMP_DIE"
    fi
    if [ "$NIVEL" -ge 2 ]; then
        reporte_procesos
    fi

    # --- Acciones destructivas: solo si estan sostenidas por varias
    # lecturas seguidas (independiente del NIVEL de este ciclo). NIVEL4
    # usa k=1, o sea accion inmediata en la primera lectura que llegue. ---
    gestionar_nivel "$ESTADO_DIR/nivel2.flag" "$SOSTENIDO_NIVEL2" "$NIVEL2_TEMP" parar_n8n
    gestionar_nivel "$ESTADO_DIR/nivel3.flag" "$SOSTENIDO_NIVEL3" "$NIVEL3_TEMP" detener_docker_excepto_ha
    gestionar_nivel "$ESTADO_DIR/nivel4.flag" "$SOSTENIDO_NIVEL4" "$NIVEL4_TEMP" apagar_switch
fi

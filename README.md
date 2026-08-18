# Homelab — Servidor casero en Mac mini 2014 (Ubuntu Server)

Servidor personal self-hosted sobre un Mac mini 2014 (A1347, 8GB RAM soldada).
Originalmente montado sobre macOS, fue migrado a **Ubuntu Server** en julio 2026
para desbloquear Docker nativo y eliminar las limitaciones del hardware bajo macOS.
Sirve como capa de infraestructura para proyectos de análisis de datos del hogar
(café, métricas del sistema, y futuros).

Corre en **dual boot**: Ubuntu Server como sistema principal (headless, servidor)
y macOS en 80GB para uso ocasional (biblioteca de Fotos / iCloud).

## Stack actual

- **Ubuntu Server LTS** — sistema principal, headless, administrado vía SSH
- **PostgreSQL** — base de datos `casa`, instalada vía apt, accesible en red local,
  corriendo como servicio systemd
  - Esquemas: `coffee_analytics` (café), `mac_metrics` (métricas del servidor),
    `home_assistant` (recorder de HA, ver abajo), `boardgames_stats`/
    `boardgames_bgg` (Boardgames Assistant), `soda_stream` (Soda Stream
    Logger/Gasificador), `vacaciones` (Vacaciones app), `personal_wiki`
    (Personal Assistant), y el grafo de personas `red_social` (extensión
    Apache AGE, compartido entre varios de los proyectos de arriba — no
    acotado a uno solo)
- **n8n** — orquestador de automatizaciones, vía npm, corriendo como servicio systemd
  - Workflows activos (agosto 2026): **BG Stats** (ingesta de exports desde
    Google Drive → Postgres, Boardgames Assistant), **New Rules** (buzón de
    reglamentos de juegos, mismo proyecto), **Wiki Inbox** (ingesta de notas
    del vault, Personal Assistant), **Notificaciones Homelab → Slack**
    (webhook `/notificar-slack`, canal `todo-albert-qu` — usado por las
    alertas térmicas de `monitor_mac.sh` y disponible para cualquier otro
    proyecto). El workflow original de sincronización Google Sheets → café
    (`Coffee Analitics CSV`/`Coffee analitics`) ya **no está activo** — el
    pipeline de café se reconstruyó directo sobre Postgres (ver el repo
    `coffee-consumption-analytics`)
- **Docker** — nativo (sin capas de virtualización), disponible para contenedores
- **Home Assistant** — contenedor Docker (`ghcr.io/home-assistant/home-assistant:stable`,
  `--privileged`, `--network=host`, `restart: unless-stopped`), config en
  `~/homeassistant:/config`. Onboarding completado (dashboard, integración
  UPnP/IGD). Bluetooth (BLE) habilitado montando `/run/dbus:/run/dbus:ro` — sin
  ese mount, BlueZ no encuentra el servicio D-Bus del host aunque el contenedor
  ya sea `--privileged` + `--network=host`. Sensores agregados: Xiaomi
  **LYWSDCGQ/01ZM** (temperatura/humedad, Mijia redondo, cocina) por BLE pasivo
  sin bindkey, y un **SwitchBot Hub 2** (cuarto) con temperatura/humedad/luz
  - **Recorder en Postgres** — el historial de HA vive en el esquema
    `home_assistant` dentro de `casa` (mismo servidor, junto a `mac_metrics`/
    `coffee_analytics`), no en el SQLite por default. Una tabla propia
    `home_assistant.daily_summary` (+ vistas por estancia) se llena cada noche
    a las 23:55 vía `home-metrics-daily.timer`, pensada para alimentar el
    análisis de correlación clima-consumo de café más adelante
  - **Red separada para IoT** — el router principal tiene el WiFi apagado por
    seguridad, así que los dispositivos smart-home (Kasa, SwitchBot) viven en
    una red aislada del mesh Deco (`CASA_IoT`, `192.168.68.0/24`) que no ve la
    LAN del servidor. El WiFi interno del Mac mini no tiene driver Linux viable
    para esto — se resolvió con un adaptador USB TP-Link TL-WN422G v2
    (chipset Atheros, paquete `firmware-ath9k-htc`) conectado a `CASA_IoT`
  - **Switch de emergencia física** — un enchufe TP-Link Kasa HS103
    (`switch.escritorio_failsafe`) en la red IoT, cableado al sistema de
    protección térmica (ver abajo). Probado end-to-end (turn_off/turn_on vía
    API), pero **aún no conectado físicamente** a la línea de poder del Mac
    mini — pendiente de reacomodar cables
  - La app oficial de Home Assistant en el teléfono apunta a la IP de
    **Tailscale** (no la LAN) para que los push notification funcionen desde
    cualquier red
  - **HomeKit Bridge** — configurado en `configuration.yaml` con whitelist
    (`include_entities`) para exponer solo el sensor Xiaomi (temperatura +
    humedad) a Siri/Home. El switch de emergencia se excluye explícitamente
    a propósito (nunca debe poder apagarse por Siri/accidente). **Pendiente:**
    el pareo inicial desde el iPhone falla ("No se encontró el accesorio") —
    diagnosticado como pérdida de paquetes multicast (mDNS) en el adaptador
    USB WiFi viejo (802.11g) que conecta al Mac mini a la red del Deco donde
    vive el teléfono (ping de 60-100ms confirma señal mala; el Deco no tiene
    puerto Ethernet libre para cablear en su lugar). Opciones evaluadas y
    pausadas por ahora: comprar switch Ethernet, comprar adaptador WiFi más
    moderno, o simplemente reintentar el pareo varias veces acercando el
    teléfono al servidor
- **Monitoreo de sistema** — script bash que captura métricas de hardware vía
  `lm-sensors`, insertadas en Postgres cada 5 min vía systemd timer
- **Scripts de análisis (Python)** — corren en la máquina de trabajo (no en el
  servidor), leen de Postgres vía red local para generar estadísticas y gráficas
- **Tailscale** — acceso remoto seguro fuera de la red local, IP `100.101.5.90`.
  Windows y iPhone (vía Termius) unidos al mismo tailnet — SSH y acceso a apps
  web (ej. Coffee Logger) funcionan igual estando en casa o fuera
- **Cockpit** — interfaz de administración web, `cockpit.socket` activo
  (acceso roto tras el cambio de IP local a `192.168.68.129`, corregido
  agosto 2026)
- **File Browser** — visor web de archivos con preview real de imagen/video/
  PDF (`filebrowser.service`), reemplaza la idea original de Samba del
  roadmap — más simple para el caso de uso (solo Alberto, sin necesidad de
  compartir carpetas como unidad de red)

## Migración de macOS a Linux (julio 2026)

El servidor corrió inicialmente sobre macOS. Se migró a Ubuntu Server porque
macOS 12 no soporta el compilador que requiere QEMU, bloqueando Docker (y por
tanto Home Assistant). Sumado a las limitaciones generales del hardware bajo
macOS, se optó por migrar.

**Qué se hizo:**
- Respaldo completo (pg_dump de la base, carpeta `.n8n` con llave de cifrado,
  scripts y configuración) a disco externo antes de formatear
- Limpieza física y repaste térmico del equipo (11 años de uso)
- Instalación de Ubuntu Server en dual boot (macOS reducido a 80GB)
- Restauración de la base `casa` vía pg_dump/restore (SQL portable, sin cambios)
- Restauración de n8n (workflows + credenciales) desde el backup
- Reescritura del script de monitoreo: de `powermetrics`/`osx-cpu-temp` a `lm-sensors`
- Traducción de la automatización: de LaunchDaemons (`.plist`) a servicios systemd

**Equivalencias macOS → Linux aplicadas:**

| macOS | Linux |
|---|---|
| `brew install postgresql@15` | `apt install postgresql` |
| Homebrew | apt |
| LaunchDaemons (`.plist`) | servicios systemd (`.service` + `.timer`) |
| `powermetrics` / `osx-cpu-temp` | `lm-sensors` (`applesmc`) |
| Docker vía Colima/QEMU (bloqueado) | Docker nativo |
| Screen Sharing / VNC | SSH |

**Resultado térmico:** en reposo, el equipo pasó de picos de 85-93°C bajo macOS
(con `mediaanalysisd` activo) a ~42°C estables en Linux, con el ventilador en su
velocidad mínima.

## Acceso remoto

- **SSH** — autenticación solo por llave (`PasswordAuthentication no`). Llaves
  autorizadas en `~/.ssh/authorized_keys`:
  - `albertqu-windows` — laptop de trabajo
  - `iphone-termius` — generada en la app Termius (ED25519, con passphrase que
    cifra la llave privada en el teléfono; Termius la desbloquea vía Face ID/huella)
- **Termius** (iPhone) — dos hosts configurados: uno con la IP local
  (`192.168.68.129` — cambió en agosto 2026 al pasar el router a la IP
  general de la casa, antes era `192.168.0.57`; solo funciona en la red de
  casa) y otro con la IP de Tailscale (`100.101.5.90`, funciona en
  cualquier red)
- VS Code (Windows, desarrollo) se queda intencionalmente en la IP local — es
  solo para trabajo dentro de casa, no necesita la IP de Tailscale

## Sistema de protección térmica

`monitor_mac.sh` corre cada 5 min (`monitor-mac.timer`) y clasifica la
temperatura del die en 5 niveles (0-4). Los niveles 2-4 requieren varias
lecturas seguidas por encima del umbral antes de ejecutar su acción (excepto
el 4), para no reaccionar a picos de CPU de un solo ciclo — ver "Falsos
positivos" abajo:

| Nivel | Temp | Acción | Lecturas requeridas |
|---|---|---|---|
| 0 | ≥50°C | Push al teléfono vía `notify.mobile_app_qu_phone` (HA) | 1 (informativo) |
| 1 | ≥55°C | Push al teléfono | 1 (informativo) |
| 2 | ≥65°C | Log de top 5 procesos + `systemctl stop n8n.service` (NOPASSWD en sudoers) + push propio | 3 seguidas (~15 min sostenido) |
| 3 | ≥75°C | Para todo contenedor Docker excepto `homeassistant` + push propio | 2 seguidas (~10 min sostenido) |
| 4 | ≥80°C | Apaga el switch físico de emergencia (`switch.escritorio_failsafe`) + push propio | 1 (inmediato) |

Cada acción de nivel 2-4 se dispara una sola vez por "episodio" sostenido
(vía flags en `.nivel_state/`) y se rearma solo cuando la temperatura vuelve
a bajar del umbral, para no repetir la acción/push cada 5 min mientras se
mantiene caliente.

### Falsos positivos y fix del ventilador (2026-08-09)

El nivel 4 (apagado físico) se disparó dos veces por ráfagas de CPU de
segundos que no representaban sobrecalentamiento real: **65°C** (2026-08-08,
proceso al 100% CPU) y **78°C** (2026-08-09, `tesseract` al 160% CPU) — en
ambos casos la lectura siguiente (5 min después) ya había bajado a 50°C.

Investigando esto se encontró la causa raíz: el ventilador (`macfanctld`)
estaba efectivamente ciego a la temperatura real del CPU — ver
[`fan-control/README.md`](fan-control/README.md) para el diagnóstico
completo y el parche aplicado (agrega soporte para `coretemp`/`Package id
0`, que antes `macfanctld` no leía en absoluto). Los umbrales de
`monitor_mac.sh` se subieron (antes 50/55/60/65) y se les agregó el
requisito de lecturas sostenidas como segunda capa de defensa contra este
mismo tipo de falso positivo.

## Respaldo semanal de Postgres

`scripts/backup_casa_to_ice.sh` corre cada domingo 3:00am vía
`backup-casa.timer` (una hora antes de `weekly-reboot.timer`, para que
siempre termine antes del reinicio):

1. Monta la SD interna del Mac mini (label `postgres_backup`, identificada
   por UUID, no por `/dev/mmcblkX` — evita romperse si el orden de
   dispositivos cambia).
2. `pg_dump` completo de la base `casa` (vía `runuser -u albertqu`, para que
   la autenticación peer de Postgres funcione igual que corriéndolo a mano).
3. Rota respaldos viejos — conserva solo los últimos 4 (~1 mes de historial).
4. Desmonta la SD.

La base `casa` pesa ~57MB, así que una SD de 4GB sobra por años — se eligió
la SD (lector interno del Mac mini) en vez de un USB para no ocupar un
puerto, ya que ese USB se necesita para el proyecto de cámaras de
seguridad (en exploración, ver conversación de agosto 2026).

El disco USB "Ice" (60GB, exFAT) ya no se usa para este backup, pero sigue
conectado como respaldo aparte: contiene `pre_migracion/` (el respaldo
original de la migración macOS → Ubuntu de julio 2026) y respaldos puntuales
de `bgstats`/`bgg_data` (proyecto Boardgames Assistant) hechos antes de
cambios grandes en esos datos.

**Bugs encontrados y corregidos durante las corridas en vivo:**
- El paso de rotación hacía `cd` dentro del punto de montaje antes de
  desmontar, así que el propio proceso del script dejaba el mount "busy"
  (`umount: target is busy`). Se corrigió usando rutas absolutas en vez de
  `cd`.
- Al migrar de exFAT (Ice) a ext4 (SD): exFAT no tiene permisos reales, así
  que el mount con `uid=1000,gid=1000` forzaba todo a verse como `albertqu`
  sin importar quién creara los archivos. ext4 sí respeta permisos reales,
  y como el script corre como `root` vía systemd, la carpeta de backups
  quedaba creada por `root` — `pg_dump` (que corre como `albertqu`) no podía
  escribir ahí. Se corrigió con un `chown albertqu:albertqu` explícito
  después de crear la carpeta.

## Roadmap

- [x] Interfaz de administración web (Cockpit) + acceso a archivos (File
      Browser en vez de Samba — más simple para un solo usuario)
- [x] Configurar Home Assistant (onboarding, dashboard, Bluetooth, Postgres recorder)
- [x] Sensor de temperatura Xiaomi vía Bluetooth (BLE, LYWSDCGQ/01ZM agregado)
- [x] Sistema de protección térmica completo (5 niveles + lecturas
      sostenidas, switch físico probado)
- [x] Parchear `macfanctld` para que el ventilador reaccione a la
      temperatura real del CPU (`coretemp`), no solo a `applesmc`
- [ ] Cablear el switch de emergencia a la línea de poder real del Mac mini
- [ ] Resolver el pareo de HomeKit Bridge (falla por mDNS/adaptador WiFi flaky
      — ver detalle arriba; retomar con reintento, switch Ethernet, o adaptador nuevo)
- [ ] Meta de largo plazo: espejo completo de la casa en HA (Google Home +
      Alexa → HA) consumido solo vía HomeKit/Siri, para automatizaciones
      más avanzadas que las nativas de cada asistente
- [x] Sincronizar `scripts/monitor_mac.sh` del repo con la versión live del servidor
- [ ] Integrar clima real de HA (Postgres) en el análisis de café (reemplazar Open-Meteo)
- [ ] NAS para cámaras + respaldo de fotos
- [x] Configurar Tailscale para acceso remoto seguro
- [x] Backup automatizado de Postgres (`pg_dump`) — semanal, a disco USB local (no a la nube todavía)
- [x] Notificaciones por Slack — workflow n8n `Notificaciones Homelab -> Slack`
      (webhook, canal `todo-albert-qu`), usado por las alertas térmicas y
      disponible como canal genérico para cualquier proyecto

## Nota sobre las apps ("Loggers")

Las apps de captura/consulta (Coffee Logger, Soda Stream Logger, Vacaciones,
Boardgames Assistant, Personal Assistant) viven en repos de GitHub aparte
(públicos o privados según el caso), no en este repo de infraestructura —
por eso no se documentan aquí a detalle. Corren como servicios systemd sobre
el mismo Postgres `casa` de arriba, la mayoría detrás de Caddy como reverse
proxy (puertos internos 3010-3013, expuestos en 3000-3003). Dos capacidades
cross-proyecto vale la pena tener presentes desde aquí porque no son
específicas de un solo repo:
- **Diagramas Mermaid en el chat** — Personal Assistant y Boardgames
  Assistant generan diagramas de relaciones (`red_social`, grupos sociales)
  directo en sus respuestas de `/ask`, sin que Alberto escriba código.
- **Slack** — el mismo webhook de n8n de arriba queda disponible para que
  cualquier app mande notificaciones sin reinventar el workflow.

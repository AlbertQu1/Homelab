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
  - Esquemas: `coffee_analytics` (café), `mac_metrics` (métricas del servidor)
- **n8n** — orquestador de automatizaciones, vía npm, corriendo como servicio systemd
  - Workflow activo: sincronización Google Sheets → Postgres
- **Docker** — nativo (sin capas de virtualización), disponible para contenedores
- **Monitoreo de sistema** — script bash que captura métricas de hardware vía
  `lm-sensors`, insertadas en Postgres cada 5 min vía systemd timer
- **Scripts de análisis (Python)** — corren en la máquina de trabajo (no en el
  servidor), leen de Postgres vía red local para generar estadísticas y gráficas
- **Tailscale** — acceso remoto seguro fuera de la red local, IP `100.101.5.90`.
  Windows y iPhone (vía Termius) unidos al mismo tailnet — SSH y acceso a apps
  web (ej. Coffee Logger) funcionan igual estando en casa o fuera

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
  (`192.168.0.57`, solo funciona en la red de casa) y otro con la IP de
  Tailscale (`100.101.5.90`, funciona en cualquier red)
- VS Code (Windows, desarrollo) se queda intencionalmente en la IP local — es
  solo para trabajo dentro de casa, no necesita la IP de Tailscale

## Roadmap

- [ ] Interfaz de administración web (Cockpit) + acceso a archivos (Samba)
- [ ] Configurar Home Assistant (ya instalado vía Docker)
- [ ] Sensor de temperatura Xiaomi vía Bluetooth (BLE, hardware ya funcional)
- [ ] NAS para cámaras + respaldo de fotos
- [x] Configurar Tailscale para acceso remoto seguro
- [ ] Backup automatizado de Postgres (`pg_dump`) hacia la nube

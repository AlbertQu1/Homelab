# Homelab — Servidor casero en Mac mini 2014

Reconversión de un Mac mini 2014 (RAM soldada a 8GB, sin soporte para Docker 
Desktop) en un servidor personal self-hosted. Nace como capa de infraestructura 
para escalar un proyecto existente de análisis de datos 
([coffee-analytics](https://github.com/AlbertQu1/coffee-consumption-analytics)), con la idea de sumar más proyectos con el tiempo.

## Stack actual

- **n8n** — orquestador de automatizaciones, instalado nativo vía npm (Docker 
  Desktop no es compatible con este hardware)
  - Workflow activo: sincronización de Google Sheets → Postgres
- **PostgreSQL 15** — instalado nativo vía Homebrew, base de datos propia, 
  configurado para aceptar conexiones desde la red local.
- **DBeaver** — cliente gráfico para administrar la base de datos
- **Script de monitoreo de sistema** — captura métricas de hardware cada 15 
  min vía `launchd`, guardadas en Postgres
  - **Script de análisis (Python)** — corre en la máquina de trabajo (no en el 
  servidor), entorno de conda dedicado, lee de Postgres vía red local para 
  generar estadísticas y gráficas de las métricas capturadas

Eso es todo lo que corre hoy — el proyecto está en etapa temprana.

## Historial

**Decisión: Docker descartado, instalación nativa**
El Mac mini 2014 no cumple los requisitos de macOS que pide Docker Desktop. 
En vez de forzar el hardware, se optó por instalar n8n y Postgres nativos 
(npm y Homebrew respectivamente).

**Postgres levantado**
Base de datos creada y funcionando, con una tabla pequeña de prueba.

**Primera automatización en n8n**
Workflow que obtiene un CSV desde Google Sheets (vía endpoint `gviz/tq`) como 
primer paso hacia migrar datos del Sheet de café a Postgres. 
(La credencial de conexión se actualizó tras el renombrado de la base a 
`casa`; el nodo apunta al esquema `coffee_analytics` dentro de ella.)
([ver workflow](n8n-workflows/sync-google-sheets-coffee.json))

**Verificación de zona horaria**
Se confirmó que al correr n8n nativo (no en Docker), el proceso hereda 
automáticamente la hora del sistema operativo — no fue necesario configurar 
nada adicional, a diferencia de lo que suele pasar con n8n en contenedor.

**Acceso remoto activado**
Se activaron Screen Sharing y Remote Login (SSH) en macOS para poder 
administrar el servidor sin necesidad de teclado/monitor físico conectados 
de forma permanente (equipo headless). Para conectarse desde Windows fue 
necesario habilitar explícitamente "VNC viewers may control screen" en la 
configuración de Screen Sharing, ya que por default macOS solo acepta 
conexiones remotas desde otra Mac. Probado y funcionando con RealVNC Viewer.

**Script de monitoreo de temperatura**
Script bash que captura temperatura (die + proximity), RPM del ventilador, 
uso de CPU, RAM libre, espacio en disco, uptime y proceso top cada 15 
minutos, guardándolo en Postgres (base `casa`, esquema `mac_metrics`). 
Automatizado con `launchd`.
([ver script](https://github.com/AlbertQu1/Homelab/blob/main/scripts/com.albertqu.monitor-mac.plist))

**Postgres accesible desde la red local**
Configurado `listen_addresses` y `pg_hba.conf` para aceptar conexiones desde 
dispositivos dentro de la red local (antes solo aceptaba conexiones locales 
al Mac mini). Esto permite que proyectos de análisis de datos (ej. 
procesamiento en Python/pandas) corran en otra máquina de trabajo, mientras 
el servidor centraliza únicamente los datos. Acceso restringido al rango de la red local (`192.168.0.0/24`) vía 
`pg_hba.conf`, no expuesto a internet.

**Renombrado de base de datos a `casa`**
La base originalmente creada como `coffee_analytics` se renombró a `casa`, 
reorganizando el contenido de café bajo un esquema propio 
(`coffee_analytics`) dentro de ella. La idea es centralizar en una sola 
base de datos distintos proyectos del hogar (café, métricas del servidor, 
y futuros: clima, automatización) que eventualmente podrían cruzarse en 
una misma consulta — separados por esquema, no por base de datos.

**Script de análisis en Python (motor de análisis)**
Script en Python (`analysis/monitor.py`), corriendo en un entorno de conda 
separado (`mac-metrics`) desde la máquina de trabajo, no en el servidor. 
Se conecta a Postgres vía red local, calcula la diferencia entre los dos 
sensores de temperatura (die y proximity) como indicador de confiabilidad 
de la lectura, genera resumen estadístico y grafica la tendencia. 
Las credenciales se manejan vía variables de entorno, nunca hardcodeadas 
en el código.
([ver script](analysis/monitor.py))

**Migracion de Postgres y script de monitoreo a LaunchDaemons**
Postgres y el script de monitoreo de temperatura se movieron de LaunchAgents 
(dependientes de sesion de usuario) a LaunchDaemons (nivel de sistema), para 
que arranquen automaticamente al iniciar el Mac mini sin necesitar conexion 
por SSH o sesion grafica. n8n se deja pendiente de este cambio, ya que se 
esta evaluando migrarlo a Colima/contenedores antes de automatizar su arranque.

**Bitacora de escenarios de prueba**
Se creo la tabla `mac_metrics.pruebas` para registrar manualmente el contexto 
de cada prueba de temperatura (que app se abrio, a que hora). Se agrego 
`analysis/registro.py`, que permite insertar un evento nuevo desde la 
maquina de trabajo (Windows) con un solo comando, sin necesitar conectarse 
por SSH.
([ver script](analysis/registro.py))

**Scripts de analisis ampliados**
Se agrego a `analysis/temp monitor.py` resumen de metricas agrupado por dia 
(en vez de un promedio global que mezcla dias distintos), manejo de error 
si el servidor esta desconectado, y un interruptor para activar/desactivar 
las graficas. Se agregaron dos scripts adicionales: `analysis/procesos 
recientes.py` (muestra el proceso con mayor uso de CPU en las ultimas 
lecturas) y `analysis/registro analisis.py` (cruza los eventos de la 
bitacora de pruebas con las lecturas de temperatura correspondientes).
([ver script](analysis/temp%20monitor.py))

**Hallazgo: mediaanalysisd como fuente de carga termica**
Se identifico que `mediaanalysisd` (proceso de macOS que indexa/analiza la 
biblioteca de Fotos) genera picos sostenidos de temperatura (85-93°C) de 
forma independiente a n8n. El proceso se reactiva en ciclos de 15-30 
minutos mientras tiene contenido pendiente de analizar, y en sesiones 
largas (2+ horas) el sistema dejo de enfriarse por completo entre ciclos. 
Pendiente: confirmar el impacto de n8n de forma aislada (la prueba original 
quedo invalidada por esta variable no controlada) y evaluar como limitar 
el analisis de `mediaanalysisd` antes de retomar el respaldo de fotos/videos.

## Roadmap

- [ ] Configurar OAuth para conectar Google Calendar directo a n8n (en vez de 
  depender de links `.ics` de suscripción)
- [ ] Levantar Home Assistant en este mismo servidor
- [ ] Configurar Tailscale para acceso remoto seguro (Screen Sharing/SSH desde 
  fuera de la red local, sin exponer puertos directos a internet)
- [ ] Reinicio semanal programado (apagado lunes 4am, encendido automático 
  6am vía `pmset`) como mantenimiento preventivo
- [ ] Respaldo de fotos: disco duro externo + HDD interno Mac mini + OneDrive 
  (3 copias), organización por año/subcarpetas + enriquecimiento de metadata 
  con exiftool
- [ ] Respaldo de biblioteca musical de iTunes: disco duro externo + HDD 
  interno Mac mini (2 copias, sin nube)
- [ ] Backup automatizado de Postgres (`pg_dump`) hacia OneDrive
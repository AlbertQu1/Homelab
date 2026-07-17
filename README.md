# Homelab — Servidor casero en Mac mini 2014

Reconversión de un Mac mini 2014 (RAM soldada a 8GB, sin soporte para Docker 
Desktop) en un servidor personal self-hosted. Nace como capa de infraestructura 
para escalar un proyecto existente de análisis de datos 
([coffee-analytics](link-aquí)), con la idea de sumar más proyectos con el tiempo.

## Stack actual

- **n8n** — orquestador de automatizaciones, instalado nativo vía npm (Docker 
  Desktop no es compatible con este hardware)
- **PostgreSQL 15** — instalado nativo vía Homebrew, base de datos propia
- **DBeaver** — cliente gráfico para administrar la base de datos

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

## Roadmap

- [ ] Configurar OAuth para conectar Google Calendar directo a n8n (en vez de 
  depender de links `.ics` de suscripción)
- [ ] Levantar Home Assistant en este mismo servidor
- [ ] Configurar Tailscale para acceso remoto seguro (Screen Sharing/SSH desde 
  fuera de la red local, sin exponer puertos directos a internet)
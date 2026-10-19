# Fan control (`macfanctld`) — parche para leer `coretemp`

## El problema (2026-08-09)

El Mac mini corre `macfanctld` (paquete Ubuntu `0.6+repack1-2build1`) para
controlar el ventilador vía el chip SMC (`applesmc`). El fan casi nunca se
movía de su piso (~2000 RPM), incluso con picos de die de 65-78°C.

Causa raíz: `macfanctld` está compilado para leer **solo** el hwmon de
`applesmc` (busca el device por nombre en `find_applesmc()`, hardcodeado).
La temperatura real del CPU (`Package id 0`, sensor digital embebido en el
silicio) vive en un chip hwmon completamente distinto — `coretemp` — al que
`applesmc` no tiene ninguna visibilidad. El daemon solo veía `TC0P`, un
sensor de proximidad físico mucho más lento/frío que el die real, y un
`temp_avg` roto (promediaba ~60 sensores de `applesmc`, varios de ellos
sensores fantasma que reportan `-127°C`, diluyendo cualquier señal real a
un valor sin sentido tipo `-1.1°C`).

Resultado: el control de fan era efectivamente ciego al calor real del CPU.

## El fix

Se parcheó el código fuente (GPLv3, upstream:
https://github.com/MikaelStrom/macfanctld) para agregar un tercer sensor
con umbral configurable, análogo a `TC0P`/`TG0P` mas apuntando al chip
`coretemp`:

- `control.c`: nueva función `find_coretemp()` (localiza el hwmon de
  `coretemp` y su sensor `"Package id 0"`), `read_coretemp()` (refresca el
  valor cada ciclo de 5s), y un tercer bloque en `calc_fan()` que compite
  por el control del fan igual que `TC0P`/`TG0P` (toma el máximo de los
  tres).
- `config.c`/`config.h`: nuevos parámetros `temp_CORE_floor` /
  `temp_CORE_ceiling` (default 45/55, ver `macfanctl.conf`).
- `macfanctl.c`: llama a `find_coretemp()` en el arranque, junto a
  `find_applesmc()`.

Validado en seco (usuario no-root, sin escribir a sysfs) antes de instalar:
con die=53°C el bloque CORE tomaba el control y calculaba
`Speed: 3360` en vez del piso fijo de 2000.

## Instalación (ya hecha en el servidor, 2026-08-09)

```bash
cd src/
gcc -Wall macfanctl.c control.c config.c -o macfanctld

sudo systemctl stop macfanctld
sudo cp /usr/sbin/macfanctld /usr/sbin/macfanctld.orig   # backup del original
sudo cp macfanctld /usr/sbin/macfanctld
sudo chmod 755 /usr/sbin/macfanctld
sudo cp ../macfanctl.conf /etc/macfanctl.conf
sudo systemctl start macfanctld
sudo apt-mark hold macfanctld   # evita que un `apt upgrade` revierta el binario
```

Verificar en `/var/log/macfanctl.log` (o `macfanctld -f` en primer plano)
que aparezca `Found coretemp at ...` en el arranque.

**Rollback:** `sudo cp /usr/sbin/macfanctld.orig /usr/sbin/macfanctld &&
sudo apt-mark unhold macfanctld && sudo systemctl restart macfanctld`.

## Nota

No se usó `dpkg-buildpackage` (requiere `debhelper`, no instalado) — el
binario se compiló directo con `gcc`/`make` y se reemplazó a mano sobre
`/usr/sbin/macfanctld`, con `apt-mark hold` para evitar que se pierda en un
upgrade futuro. Si se reinstala el paquete oficial alguna vez, hay que
volver a aplicar este parche.

## Bug de la curva (2026-10-19)

El parche de agosto hizo que el daemon *viera* el die, pero el fan seguía
casi siempre en 2000 RPM. Causa: `calc_fan()` (código upstream, aplica a los
4 sensores) calculaba la velocidad como `normalized_temp * fan_window`
**sin sumar `fan_min`**. Con `fan_min` 2000 y `fan_max` 4800 la velocidad
calculada solo superaba el piso a partir del 71% de la ventana: con CORE
45/55 el fan no se movía hasta ~52°C y luego saltaba de 2000 a 4800 entre
52 y 55°C (on/off en vez de curva). Fix: `fan_min + normalized_temp * fan_window`.

Con la fórmula corregida y CORE 46/55: 48°C → ~2600 RPM, 50°C → ~3250,
52°C → ~3850, 55°C → 4800. Queda igual o más agresiva que antes en todo el
rango.

**Prueba A/B** (`prueba_fan.sh`: reposo 60s, `while :` en 2 núcleos,
enfriamiento; aborta a 70°C). Resultados en [`pruebas/`](pruebas/):

| Corrida | Reposo die prom | Pico de carga | Tiempo al pico | RPM máx |
|---|---|---|---|---|
| Curva original | 46.0°C | 70°C | 10 s (52→68→70) | 6191 |
| Curva corregida (46/60) | 45.2°C | 70°C | 10 s (51→68→70) | 6021 |

Conclusión: la curva corregida no cambia el pico. El die sube ~18°C en
5-10 s con solo 2 núcleos, más rápido de lo que cualquier control de fan
puede reaccionar (ciclo de 5 s + spin-up). Eso apunta a mala transferencia
de calor (pasta térmica de 2014 seca), no al control del fan. La curva
corregida se mantiene (con techo 55 en vez de 60, porque 46/60 era menos
agresiva que la original arriba de ~53°C), pero el arreglo de fondo es
cambiar la pasta térmica.

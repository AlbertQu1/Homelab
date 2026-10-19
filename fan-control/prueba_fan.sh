#!/bin/bash
# Prueba A/B de la curva del ventilador: reposo 60s, carga en 2 nucleos 180s,
# enfriamiento 180s, una lectura cada 5s. Aborta la carga si el die llega a 70°C
# (lejos del nivel 4 de monitor_mac.sh, 80°C con una sola lectura).
# Uso: ./prueba_fan.sh <salida.csv>
OUT=${1:-prueba_fan.csv}
echo "t,fase,die,rpm" > "$OUT"
die() { sensors | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
rpm() { cat /sys/devices/platform/applesmc.768/fan1_input; }
PIDS=""; t=0
fase() {
  for ((i = 0; i < $2; i += 5)); do
    d=$(die); echo "$t,$1,$d,$(rpm)" >> "$OUT"
    if [ -n "$PIDS" ] && [ "$d" -ge 70 ]; then kill $PIDS 2>/dev/null; PIDS=""; echo "ABORTADO a ${d}°C (t=${t}s)"; fi
    sleep 5; t=$((t + 5))
  done
}
fase reposo 60
for n in 1 2; do (while :; do :; done) & PIDS="$PIDS $!"; done
fase carga 180
[ -n "$PIDS" ] && kill $PIDS 2>/dev/null; PIDS=""
fase enfriamiento 180
awk -F, 'NR>1{k=$2; n[k]++; s[k]+=$3; if($3>mx[k])mx[k]=$3; r[k]+=$4; if($4>mr[k])mr[k]=$4}
  END{for(k in n) printf "%-13s die prom %.1f máx %d | rpm prom %.0f máx %d\n",k,s[k]/n[k],mx[k],r[k]/n[k],mr[k]}' "$OUT"

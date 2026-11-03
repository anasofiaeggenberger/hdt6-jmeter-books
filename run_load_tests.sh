#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPORT_ROOT="${REPORT_ROOT:-$ROOT_DIR/../hdt6-jmeter-books-reportes}"
API_URL="${API_URL:-http://127.0.0.1:8000}"
PLAN="$ROOT_DIR/plan.jmx"

usage() {
  cat <<'EOF'
Uso:
  ./run_load_tests.sh [10 50 100 200 500]

Variables opcionales:
  REPORT_ROOT=/ruta/fuera/del/repositorio
  API_URL=http://127.0.0.1:8000
  MEASURE_CPU=1   toma muestras de CPU durante la corrida de 500 usuarios

Sin argumentos se ejecutan los cinco niveles del README.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Falta el comando '$1'. Consulte GUI.md y README.md para instalarlo." >&2
    exit 2
  fi
}

need_cmd curl
need_cmd jmeter
need_cmd uv
need_cmd python3

if [[ ! -f "$PLAN" || ! -f "$ROOT_DIR/books.csv" ]]; then
  echo "No se encuentran plan.jmx o books.csv en $ROOT_DIR" >&2
  exit 2
fi

if (($# == 0)); then
  LEVELS=(10 50 100 200 500)
else
  LEVELS=("$@")
fi

for users in "${LEVELS[@]}"; do
  case "$users" in
    10|50|100|200|500) ;;
    *) echo "Nivel no permitido: $users (use 10, 50, 100, 200 o 500)." >&2; exit 2 ;;
  esac
done

mkdir -p "$REPORT_ROOT"
API_PID=""

cleanup() {
  if [[ -n "$API_PID" ]] && kill -0 "$API_PID" 2>/dev/null; then
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if ! curl -fsS "$API_URL/health" >/dev/null 2>&1; then
  echo "API no disponible; iniciando uv run api.py..."
  (
    cd "$ROOT_DIR"
    exec uv run api.py >"$REPORT_ROOT/api.log" 2>&1
  ) &
  API_PID=$!
fi

ready=0
for _ in {1..60}; do
  if curl -fsS "$API_URL/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if ((ready == 0)); then
  echo "El API no respondió en $API_URL. Revise $REPORT_ROOT/api.log." >&2
  exit 1
fi

for users in "${LEVELS[@]}"; do
  RUN_ROOT="$REPORT_ROOT/$users"
  HTML_REPORT="$RUN_ROOT/html"
  JTL="$RUN_ROOT/results.jtl"
  JMETER_LOG="$RUN_ROOT/jmeter.log"
  RESULTS_DIR="$ROOT_DIR/resultados/$users"

  if [[ -e "$RUN_ROOT" ]]; then
    echo "Ya existe $RUN_ROOT; use otro REPORT_ROOT para no mezclar reportes." >&2
    exit 2
  fi
  mkdir -p "$RUN_ROOT"

  echo "Reiniciando API para $users usuarios..."
  curl -fsS -X POST "$API_URL/reset" >"$RUN_ROOT/reset.json"
  curl -fsS "$API_URL/health" >"$RUN_ROOT/health.json"

  JMETER_PID=""
  CPU_SAMPLER_PID=""
  CPU_CSV="$RUN_ROOT/cpu.csv"

  echo "Ejecutando $users usuarios (ramp-up 10 s, sostenido 60 s)..."
  jmeter -n \
    -t "$PLAN" \
    -Jusers="$users" \
    -Jramp_up=10 \
    -Jhold=60 \
    -Jcsv_file="$ROOT_DIR/books.csv" \
    -l "$JTL" \
    -j "$JMETER_LOG" \
    -e \
    -o "$HTML_REPORT" &
  JMETER_PID=$!
  if [[ "${MEASURE_CPU:-0}" == "1" && "$users" == "500" ]]; then
    need_cmd lsof
    API_CPU_PID="$(lsof -tiTCP:8000 -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
    if [[ -z "$API_CPU_PID" ]]; then
      echo "No se pudo identificar el proceso que escucha en el puerto 8000; no se tomará CPU." >&2
    fi
    printf 'epoch,api_pid,api_cpu_pct,jmeter_pid,jmeter_cpu_pct\n' >"$CPU_CSV"
    (
      while kill -0 "$JMETER_PID" 2>/dev/null; do
        now="$(date +%s)"
        api_cpu=""
        jmeter_cpu=""
        if [[ -n "$API_CPU_PID" ]]; then
          api_cpu="$(ps -p "$API_CPU_PID" -o %cpu= | awk '{print $1}')"
        fi
        jmeter_cpu="$(ps -p "$JMETER_PID" -o %cpu= | awk '{print $1}')"
        printf '%s,%s,%s,%s,%s\n' "$now" "${API_CPU_PID:-}" "${api_cpu:-}" "$JMETER_PID" "${jmeter_cpu:-}" >>"$CPU_CSV"
        sleep 1
      done
    ) &
    CPU_SAMPLER_PID=$!
  fi
  set +e
  wait "$JMETER_PID"
  JMETER_STATUS=$?
  set -e

  if [[ -n "$CPU_SAMPLER_PID" ]]; then
    wait "$CPU_SAMPLER_PID" 2>/dev/null || true
    if [[ -s "$CPU_CSV" ]]; then
      awk -F, '
        NR > 1 && $3 != "" { api_n++; api_sum += $3; if ($3 > api_max) api_max = $3 }
        NR > 1 && $5 != "" { j_n++; j_sum += $5; if ($5 > j_max) j_max = $5 }
        END {
          printf "API: muestras=%d promedio=%.2f%% máximo=%.2f%%\n", api_n, (api_n ? api_sum/api_n : 0), api_max
          printf "JMeter: muestras=%d promedio=%.2f%% máximo=%.2f%%\n", j_n, (j_n ? j_sum/j_n : 0), j_max
        }
      ' "$CPU_CSV" >"$RUN_ROOT/cpu_summary.txt"
      sysctl -n hw.ncpu >"$RUN_ROOT/cpu_cores.txt" 2>/dev/null || sysctl -n hw.logicalcpu >"$RUN_ROOT/cpu_cores.txt" 2>/dev/null || true
    fi
  fi

  if ((JMETER_STATUS != 0)); then
    echo "JMeter terminó con exit code $JMETER_STATUS; se conserva el diagnóstico en $RUN_ROOT." >&2
    exit "$JMETER_STATUS"
  fi
  if [[ ! -f "$HTML_REPORT/statistics.json" ]]; then
    echo "No se generó $HTML_REPORT/statistics.json." >&2
    exit 1
  fi

  mkdir -p "$RESULTS_DIR"
  cp "$HTML_REPORT/statistics.json" "$RESULTS_DIR/statistics.json"
  set +e
  python3 "$ROOT_DIR/gate.py" "$HTML_REPORT"
  GATE_STATUS=$?
  set -e
  printf '%s\n' "$GATE_STATUS" >"$RUN_ROOT/gate.exitcode"
  echo "statistics.json copiado a resultados/$users/; gate exit code: $GATE_STATUS"
done

echo "Corridas terminadas. Reportes completos: $REPORT_ROOT"

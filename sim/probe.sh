#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-qwen3:8b}"
HOST="${HOST:-http://localhost:11434}"
CONTAINER="${CONTAINER:-ollama-sim}"

command -v jq >/dev/null || { echo "jq is required"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

echo "==> Checking Ollama at $HOST"
curl -sf "$HOST/api/tags" >/dev/null || { echo "Ollama not reachable. Did you run 'docker compose up -d'?"; exit 1; }

if ! curl -s "$HOST/api/tags" | jq -e --arg m "$MODEL" '.models[] | select(.name == $m or .name == ($m + ":latest"))' >/dev/null; then
  echo "==> Pulling $MODEL (several minutes on first run)"
  curl -s "$HOST/api/pull" -d "{\"model\":\"$MODEL\"}" | jq -r 'select(.status) | .status' | tail -5
fi

MSG=$(cat <<'EOF'
Extraia tickets de desenvolvimento desta conversa de WhatsApp.
Devolva APENAS JSON no formato: {"tickets":[{"title":"...","screen":"...","category":"UX|bug|feature","description":"...","context":"..."}]}

[19/10/2026, 10:24:25] Jonathan Cardozo: Sobre aquela conversa de ontem, veja se seria possível:
[19/10/2026, 10:25:15] Jonathan Cardozo: 1. Na tela de planejamento, permitir duplo clique no dia do calendário e já abrir tela de agendamento com a data selecionada. (UX)
[19/10/2026, 10:27:18] Jonathan Cardozo: 2. Na tela de agendamento trazer o campo de OS com quatro dígitos mas apagar o "0000" ao clicar no campo (UX)

Hoje o usuário está precisando apagar os zeros do campo antes de digitar
EOF
)

run_test() {
  local label="$1"
  local prompt="$2"
  echo
  echo "============================================================"
  echo "  $label"
  echo "============================================================"

  local payload
  payload=$(jq -n --arg m "$MODEL" --arg p "$prompt" '{
    model: $m,
    prompt: $p,
    stream: false,
    format: "json",
    options: { temperature: 0.2 }
  }')

  local start_ms end_ms wall_ms
  start_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))')
  local response
  response=$(curl -s "$HOST/api/generate" -d "$payload")
  end_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time;print(int(time.time()*1000))')
  wall_ms=$((end_ms - start_ms))

  local eval_count prompt_eval_count eval_duration prompt_eval_duration total_duration tps
  eval_count=$(echo "$response" | jq -r '.eval_count // 0')
  prompt_eval_count=$(echo "$response" | jq -r '.prompt_eval_count // 0')
  eval_duration=$(echo "$response" | jq -r '.eval_duration // 0')
  prompt_eval_duration=$(echo "$response" | jq -r '.prompt_eval_duration // 0')
  total_duration=$(echo "$response" | jq -r '.total_duration // 0')

  if [ "$eval_duration" -gt 0 ]; then
    tps=$(awk "BEGIN { printf \"%.1f\", $eval_count / ($eval_duration / 1000000000) }")
  else
    tps="n/a"
  fi

  printf "  wall latency       : %s ms\n" "$wall_ms"
  printf "  total_duration     : %.2f s\n" "$(awk "BEGIN { printf \"%.2f\", $total_duration / 1000000000 }")"
  printf "  prompt tokens      : %s (%.2fs)\n" "$prompt_eval_count" "$(awk "BEGIN { printf \"%.2f\", $prompt_eval_duration / 1000000000 }")"
  printf "  generated tokens   : %s (%.2fs)\n" "$eval_count" "$(awk "BEGIN { printf \"%.2f\", $eval_duration / 1000000000 }")"
  printf "  generation tok/s   : %s\n" "$tps"
  echo "  --- model response ---"
  echo "$response" | jq -r '.response' | sed 's/^/  /'
}

run_test "no-think (fast extraction, estágios 1 e 2)" "$MSG /no_think"
run_test "think (full reasoning, estágio 3)"         "$MSG /think"

echo
echo "============================================================"
echo "  Container RAM usage"
echo "============================================================"
docker stats --no-stream "$CONTAINER" --format "  {{.Name}}: {{.MemUsage}}  ({{.MemPerc}})"

# sim — sandbox pra validar o modelo antes do resto

Sobe um Ollama isolado com os mesmos limites de RAM do VPS (8 GB) e roda a mensagem real do Jonathan por `qwen3:8b` com e sem thinking, pra medir latência, tokens/s e uso de RAM antes de qualquer código do projeto.

## O que isso simula

- VPS com **8 GB livres** pro Ollama (via `mem_limit: 8g`)
- Config do Ollama recomendada (`FLASH_ATTENTION`, `KV_CACHE_TYPE=q8_0`, 1 modelo quente)
- Sem GPU
- Chamada via `/api/generate` com `format: "json"` (structured output)

## Pré-requisitos

- Docker + Docker Compose
- `jq` e `curl` na máquina de teste

## Como rodar

```bash
cd sim
docker compose up -d
./probe.sh
```

A primeira execução baixa o modelo (~5 GB, demora alguns minutos). As seguintes são imediatas.

Pra testar outro modelo:

```bash
MODEL=gemma3n:e4b ./probe.sh
MODEL=qwen3:4b    ./probe.sh
```

## Como ler o resultado

Cada rodada imprime:

- **wall latency** — tempo total do request (o que o cliente sente)
- **generated tokens** — quantos tokens o modelo gerou
- **generation tok/s** — velocidade pura de geração
- **model response** — JSON extraído

E no final, o uso real de RAM do container.

**O que considerar bom pro caso de uso:**

- Estágios 1 e 2 (no-think) com `qwen3:8b`: esperado 4–8 tok/s, resposta em 10–30s pra mensagem desse tamanho. Se passar muito disso, o VPS está limitado em CPU.
- Estágio 3 (think) com `qwen3:8b`: pode gastar 1000–3000 tokens pensando. 1–5 min é normal. Se ficar bom nos tickets extraídos, troca pelo roadmap definitivo.
- RAM do container estável abaixo de 7 GB com 32k de contexto.

## Decisão

Depois de rodar os três modelos (qwen3:8b, qwen3:4b, gemma3n:e4b), compara:

1. Qualidade do JSON (todos os tickets saíram? categorias certas? contexto captado?)
2. Latência média
3. Pico de RAM

E escolhe antes de desenhar o schema do SQLite e os endpoints de verdade.

## Limpar tudo

```bash
docker compose down -v   # -v apaga o volume com os modelos baixados
```

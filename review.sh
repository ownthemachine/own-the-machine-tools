#!/usr/bin/env bash
# Generic adversarial review runner for the legislation pipeline.
# Usage: pipeline/review.sh <input.md> <output.md> <prompt.md>
# Env:   OPENROUTER_API_KEY (required; never committed)
#        REVIEW_MODEL (default google/gemini-3.7-flash; use a stronger tier
#        for gates 3 and 4, see pipeline/README.md)
set -euo pipefail
IN="${1:?usage: review.sh <input.md> <output.md> <prompt.md>}"
OUT="${2:?}"; PROMPT="${3:?}"
MODEL="${REVIEW_MODEL:-google/gemini-3.7-flash}"
[[ -f "$IN" && -f "$PROMPT" ]] || { echo "missing input or prompt" >&2; exit 1; }
[[ -n "${OPENROUTER_API_KEY:-}" ]] || { echo "OPENROUTER_API_KEY not set" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp)"; RESP="$(mktemp)"; CFG="$(mktemp)"; trap 'rm -f "$TMP" "$RESP" "$CFG"' EXIT
chmod 600 "$CFG"; printf 'header = "Authorization: Bearer %s"\n' "$OPENROUTER_API_KEY" > "$CFG"
python3 - "$PROMPT" "$IN" "$MODEL" > "$TMP" <<'PY'
import json, sys
prompt, doc, model = open(sys.argv[1]).read(), open(sys.argv[2]).read(), sys.argv[3]
print(json.dumps({"model": model,
    "messages": [{"role": "user", "content": prompt + "\n\n---\n\n" + doc}],
    "temperature": 0.3}))
PY
HTTP=$(curl -sS --max-time 600 -K "$CFG" -H "Content-Type: application/json" \
  -o "$RESP" -w '%{http_code}' -d @"$TMP" https://openrouter.ai/api/v1/chat/completions) || HTTP=000
if [[ "$HTTP" == "429" || "$HTTP" =~ ^5 || "$HTTP" == "000" ]]; then
  sleep 20
  HTTP=$(curl -sS --max-time 600 -K "$CFG" -H "Content-Type: application/json" \
    -o "$RESP" -w '%{http_code}' -d @"$TMP" https://openrouter.ai/api/v1/chat/completions) || HTTP=000
fi
[[ "$HTTP" == "200" ]] || { echo "OpenRouter HTTP $HTTP" >&2; head -c 400 "$RESP" >&2; exit 1; }
python3 - "$RESP" "$OUT" "$MODEL" "$PROMPT" <<'PY'
import json, sys, datetime
r = json.load(open(sys.argv[1])); txt = r["choices"][0]["message"]["content"]
u = r.get("usage", {})
hdr = (f"# Review\n\n> Reviewer: OpenRouter `{sys.argv[3]}` · "
       f"{datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')} · "
       f"tokens in={u.get('prompt_tokens','?')} out={u.get('completion_tokens','?')}\n"
       f"> Prompt: {sys.argv[4]} · Verbatim model output below — do not edit.\n\n")
open(sys.argv[2], "w").write(hdr + txt + "\n")
verdict = [l for l in txt.splitlines() if l.strip().startswith("VERDICT:")]
print(verdict[-1].strip() if verdict else "NO VERDICT LINE — treat as REVISE")
PY
echo "review written: $OUT"

#!/usr/bin/env bash
# Generic adversarial review runner for the legislation pipeline.
# Usage: review.sh <input.md> <output.md> <prompt.md>
#
# Routing. The gate runs on an EU-hosted, zero-retention endpoint by default.
# That is not a preference: a campaign about European ownership of automated
# capital should not send its own drafts through a jurisdiction it is arguing
# about, and a draft Regulation is unpublished legal text until it is filed.
#
# Env:
#   REQUESTY_API_KEY   (or REVIEW_API_KEY; OPENROUTER_API_KEY still works when
#                       REVIEW_BASE_URL is pointed back at OpenRouter)
#   REVIEW_BASE_URL    default https://router.eu.requesty.ai/v1
#   REVIEW_MODEL       default vertex/gemini-3.7-flash@eu
#   REVIEW_VERIFY      default 1. Read the router's own model metadata and
#                      refuse to run unless it satisfies the requirements
#                      below. 0 skips verification entirely, and the review
#                      record then claims nothing about jurisdiction.
#   REVIEW_REQUIRE_EU          default 1  geolocation must be eu
#   REVIEW_REQUIRE_ZDR         default 1  retention must be 0 days
#   REVIEW_REQUIRE_NO_TRAINING default 1  text must not be trained on
#                      Three separate switches so that relaxing one does not
#                      silently drop the other two. The provenance line always
#                      reports what the router said, so a relaxed run is
#                      visible in every verdict it produced.
# A .env beside this script is loaded if present, so the key stays out of the
# shell history and out of the repository (.env is gitignored).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$HERE/.env" ]] && set -a && . "$HERE/.env" && set +a

IN="${1:?usage: review.sh <input.md> <output.md> <prompt.md>}"
OUT="${2:?}"; PROMPT="${3:?}"
BASE="${REVIEW_BASE_URL:-https://router.eu.requesty.ai/v1}"
MODEL="${REVIEW_MODEL:-vertex/gemini-3.7-flash@eu}"
VERIFY="${REVIEW_VERIFY:-1}"
KEY="${REVIEW_API_KEY:-${REQUESTY_API_KEY:-${OPENROUTER_API_KEY:-}}}"
[[ -f "$IN" && -f "$PROMPT" ]] || { echo "missing input or prompt" >&2; exit 1; }
[[ -n "$KEY" ]] || { echo "no API key: set REQUESTY_API_KEY (see README)" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp)"; RESP="$(mktemp)"; CFG="$(mktemp)"; META="$(mktemp)"
trap 'rm -f "$TMP" "$RESP" "$CFG" "$META"' EXIT
chmod 600 "$CFG"; printf 'header = "Authorization: Bearer %s"\n' "$KEY" > "$CFG"

# ---- provenance, verified rather than asserted ----------------------
# The router publishes geolocation and retention per model. Read it, prove the
# claim before spending tokens, and carry what it said into the review record.
PROV="router $(printf '%s' "$BASE" | sed -E 's#https?://([^/]+).*#\1#')"
if [[ "$VERIFY" == "1" ]]; then
  curl -sS --max-time 120 -K "$CFG" -o "$META" "$BASE/models" || {
    echo "could not read $BASE/models to verify EU routing" >&2; exit 1; }
  PROV=$(python3 - "$META" "$MODEL" "$BASE" <<'PY'
import json, sys
meta, model, base = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
rows = meta.get('data', meta if isinstance(meta, list) else [])
m = next((r for r in rows if r.get('id') == model), None)
if m is None:
    sys.exit(f"model {model!r} is not offered by {base}. "
             "Pick one it lists, or set REVIEW_REQUIRE_EU=0 deliberately.")
geo = str(m.get('geolocation', '')).lower()
days = m.get('data_retention_days')
trained = m.get('data_used_for_training')
import os
want = lambda k: os.environ.get(k, '1') == '1'
# Three separable guarantees, so that relaxing one does not silently drop the
# others. Region is the thesis. Training use is the principle: a proposal about
# capital formed out of other people's inputs without their consent should not
# hand its own text over for training. Retention is hygiene, and this corpus is
# published anyway, so it is the one that can defensibly be relaxed.
bad = []
if want('REVIEW_REQUIRE_EU') and geo != 'eu':
    bad.append(f"geolocation={geo or 'unknown'}")
if want('REVIEW_REQUIRE_ZDR') and days not in (0, '0'):
    bad.append(f"retention_days={days}")
# unknown is not a pass: a router that does not say must not be taken to mean no
if want('REVIEW_REQUIRE_NO_TRAINING') and trained not in (False, 'false'):
    bad.append(f"trained_on={'unknown' if trained is None else trained}")
if bad:
    sys.exit("refusing to run: " + ", ".join(bad) + ". The review record would "
             "claim a guarantee this model does not offer. Relax the specific "
             "requirement deliberately (see README) rather than all of them.")
host = base.split('//')[-1].split('/')[0]
# The line reports what the router actually said, never what was required, so a
# relaxed run is visible in every verdict it produces.
print(f"router {host} · geolocation {geo} · retention {days}d · "
      f"trained-on {str(trained).lower()} · lab {m.get('model_lab', '?')}")
PY
  ) || exit 1
fi

build_body() {  # $1 = "with" | "without" temperature
  python3 - "$PROMPT" "$IN" "$MODEL" "${REVIEW_TEMPERATURE:-0.3}" "$1" > "$TMP" <<'PY'
import json, sys
prompt, doc, model, temp, mode = (open(sys.argv[1]).read(), open(sys.argv[2]).read(),
                                  sys.argv[3], sys.argv[4], sys.argv[5])
body = {"model": model,
        "messages": [{"role": "user", "content": prompt + "\n\n---\n\n" + doc}]}
# Reasoning-tier models reject temperature outright ("deprecated for this
# model"), so it is a parameter the runner must be able to drop.
if mode == "with" and temp not in ("off", ""):
    body["temperature"] = float(temp)
print(json.dumps(body))
PY
}
call() {
  curl -sS --max-time 600 -K "$CFG" -H "Content-Type: application/json" \
    -o "$RESP" -w '%{http_code}' -d @"$TMP" "$BASE/chat/completions" || echo 000
}
build_body with
HTTP=$(call)
if [[ "$HTTP" == "400" ]] && grep -qi 'temperature' "$RESP"; then
  echo "note: $MODEL rejects temperature; retrying without it" >&2
  build_body without
  HTTP=$(call)
fi
if [[ "$HTTP" == "429" || "$HTTP" =~ ^5 || "$HTTP" == "000" ]]; then
  sleep 20; HTTP=$(call)
fi
[[ "$HTTP" == "200" ]] || { echo "review HTTP $HTTP from $BASE" >&2; head -c 400 "$RESP" >&2; exit 1; }
python3 - "$RESP" "$OUT" "$MODEL" "$PROMPT" "$PROV" <<'PY'
import json, sys, os, datetime
r = json.load(open(sys.argv[1])); txt = r["choices"][0]["message"]["content"]
u = r.get("usage", {})
hdr = (f"# Review\n\n> Reviewer: `{sys.argv[3]}` · {sys.argv[5]}\n"
       f"> {datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')} · "
       f"tokens in={u.get('prompt_tokens','?')} out={u.get('completion_tokens','?')}\n"
       f"> Prompt: {os.path.basename(sys.argv[4])} · Verbatim model output below — do not edit.\n\n")
open(sys.argv[2], "w").write(hdr + txt + "\n")
verdict = [l for l in txt.splitlines() if l.strip().startswith("VERDICT:")]
print(verdict[-1].strip() if verdict else "NO VERDICT LINE — treat as REVISE")
PY
echo "review written: $OUT"

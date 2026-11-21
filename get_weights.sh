#!/usr/bin/env bash
# Download Kimodo's weights into your Hugging Face cache (~/.cache/huggingface). Run it yourself, once:
#
#   cd <AssetFurnace>/addons/kimodo
#   .venv/bin/hf auth login          # paste your own read token; the add-on never sees it
#   bash get_weights.sh
#
# Before that, on huggingface.co, open meta-llama/Meta-Llama-3-8B-Instruct and accept Meta's licence
# (the text encoder is built on it; access is granted per account, usually within hours).
# About 18 GB in total. Add --seed to also fetch the SEED model. Still waiting for Meta's approval? Add --mirror:
# the text encoder is then built on an open copy of the same Llama 3 weights (same licence).
set -euo pipefail
cd "$(dirname "$0")"
HF=.venv/bin/hf
[ -x "$HF" ] || { echo "Run setup.sh first (AssetFurnace does it when it installs the add-on)."; exit 1; }
unset HF_HUB_OFFLINE

if ! "$HF" auth whoami >/dev/null 2>&1; then
	echo "Not logged in to Hugging Face. Run: $HF auth login"
	exit 1
fi

get() { echo "== $1"; "$HF" download "$@" >/dev/null; }

MIRROR=0
SEED=0
for a in "$@"; do
	case "$a" in
		--mirror) MIRROR=1 ;;
		--seed) SEED=1 ;;
	esac
done

if [ "$MIRROR" = 1 ]; then
	# Meta's own repo is gated and approval can take days. Llama 3's licence allows redistribution with the
	# licence attached, so open copies exist; NousResearch's is the same weights. The text encoder then lives
	# in ./encoders (Kimodo reads it from TEXT_ENCODERS_DIR, run.sh sets it), pointed at that copy.
	ENC="$PWD/encoders"
	LLAMA="$ENC/llama3-8b-instruct"
	MNTP="$ENC/McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp"
	SUP="$ENC/McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
	get NousResearch/Meta-Llama-3-8B-Instruct --local-dir "$LLAMA" --exclude "original/*"
	get McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp --local-dir "$MNTP"
	get McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised --local-dir "$SUP"
	.venv/bin/python - "$LLAMA" "$MNTP" "$SUP" <<'PY'
import json, shutil, sys
from pathlib import Path
llama, mntp, sup = (Path(p) for p in sys.argv[1:4])
swap = {"meta-llama/Meta-Llama-3-8B-Instruct": str(llama),
        "McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp": str(mntp)}
for d in (mntp, sup):
    for name in ("adapter_config.json", "config.json"):
        f = d / name
        if not f.exists():
            continue
        cfg = json.loads(f.read_text())
        changed = False
        for key in ("base_model_name_or_path", "_name_or_path"):
            if cfg.get(key) in swap:
                cfg[key] = swap[cfg[key]]
                changed = True
        if changed:
            f.write_text(json.dumps(cfg, indent=2))
            print("pointed", f.relative_to(f.parents[2]), "at the local copy")
    for t in ("tokenizer.json", "tokenizer_config.json", "special_tokens_map.json"):
        if not (d / t).exists() and (llama / t).exists():
            shutil.copyfile(llama / t, d / t)
PY
else
	get meta-llama/Meta-Llama-3-8B-Instruct --exclude "original/*" || {
		echo "Could not download Meta-Llama-3-8B-Instruct. Accept its licence on huggingface.co first (it is gated),"
		echo "or run: bash get_weights.sh --mirror   (an open copy of the same weights, same licence)"
		exit 1
	}
	get McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp
	get McGill-NLP/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised
fi
get nvidia/Kimodo-SOMA-RP-v1.1
if [ "$SEED" = 1 ]; then
	get nvidia/Kimodo-SOMA-SEED-v1.1
fi
echo "Weights are in the Hugging Face cache. 'Make a move' works offline now."

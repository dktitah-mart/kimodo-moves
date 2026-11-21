#!/usr/bin/env bash
# AssetFurnace runs: bash run.sh {out} {prompt} {seconds} {seed} {model} {text_on_cpu}
set -euo pipefail
cd "$(dirname "$0")"
[ -x .venv/bin/python ] || { echo "Kimodo is not set up: reinstall the add-on (setup.sh)."; exit 1; }
export HF_HUB_OFFLINE=1          # weights come from the cache (get_weights.sh); nothing is downloaded here
export LOCAL_CACHE=true          # Kimodo: look in the cache, not online
export TEXT_ENCODER_MODE=local   # no text-encoder server; load LLM2Vec in this process
export PATH="$PWD/.venv/bin:$PATH"
# get_weights.sh --mirror keeps the text encoder here, pointed at an open copy of Llama 3
if [ -d encoders/McGill-NLP ]; then
	export TEXT_ENCODERS_DIR="$PWD/encoders"
fi
exec .venv/bin/python kimodo_move.py "$1" --prompt "$2" --seconds "$3" --seed "$4" --model "$5" --text-on-cpu "$6"

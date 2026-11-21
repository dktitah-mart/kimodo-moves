#!/usr/bin/env bash
# Install Kimodo into this add-on's own Python environment (.venv). Runs once, when AssetFurnace installs
# the add-on. It downloads Python packages (PyTorch, Kimodo at a pinned commit) but no model weights:
# those come from get_weights.sh, which you run yourself after logging in to Hugging Face.
set -euo pipefail
cd "$(dirname "$0")"

KIMODO_COMMIT=e1c219c99b4b94ba48be1fb6a1cbc64ecee4c954
TORCH_INDEX=${KIMODO_TORCH_INDEX:-https://download.pytorch.org/whl/cu124}

say() { printf '[kimodo setup] %s\n' "$*"; }

if ! command -v g++ >/dev/null 2>&1 && ! command -v c++ >/dev/null 2>&1; then
	say "No C++ compiler. Kimodo builds a small C++ part (foot clean-up). On Ubuntu/WSL: sudo apt install build-essential libeigen3-dev"
	exit 1
fi

if [ ! -x .venv/bin/python ]; then
	if command -v uv >/dev/null 2>&1; then
		say "making .venv with uv (Python 3.10)"
		uv venv --python 3.10 .venv
		PIP=(uv pip install --python .venv/bin/python)
	else
		PY=""
		for c in python3.10 python3.11 python3.12 python3; do
			if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
				PY=$c
				break
			fi
		done
		if [ -z "$PY" ]; then
			say "Need Python 3.10 or newer (or uv)."
			exit 1
		fi
		say "making .venv with $PY"
		"$PY" -m venv .venv || { say "venv failed. On Ubuntu/WSL: sudo apt install python3-venv"; exit 1; }
	fi
fi
if [ -z "${PIP+x}" ]; then
	if command -v uv >/dev/null 2>&1; then
		PIP=(uv pip install --python .venv/bin/python)
	else
		.venv/bin/python -m pip install --upgrade pip
		PIP=(.venv/bin/python -m pip install)
	fi
fi

if ! .venv/bin/python -c 'import os, sysconfig; raise SystemExit(0 if os.path.exists(os.path.join(sysconfig.get_paths()["include"], "Python.h")) else 1)'; then
	say "This Python has no headers (Python.h). On Ubuntu/WSL: sudo apt install python3-dev (or install uv and delete .venv)"
	exit 1
fi

say "PyTorch (CUDA build from $TORCH_INDEX)"
"${PIP[@]}" torch --index-url "$TORCH_INDEX"
say "build tools"
"${PIP[@]}" "cmake>=3.20" setuptools wheel
export PATH="$PWD/.venv/bin:$PATH"   # the cmake just installed, for the C++ build
say "Kimodo at $KIMODO_COMMIT"
# the C++ part uses Eigen: the system's (libeigen3-dev) if present, else CMake fetches it from gitlab.com
"${PIP[@]}" "kimodo @ git+https://github.com/nv-tlabs/kimodo.git@$KIMODO_COMMIT" || {
	say "Kimodo did not build. Usually a missing compiler or Eigen: sudo apt install build-essential libeigen3-dev, then reinstall the add-on."
	exit 1
}

.venv/bin/python - <<'EOF'
import numpy, torch
import kimodo  # noqa: F401
from kimodo.model.registry import resolve_model_name
assert resolve_model_name("Kimodo-SOMA-RP-v1.1", "Kimodo") == "kimodo-soma-rp-v1.1"
print("[kimodo setup] torch", torch.__version__, "CUDA" if torch.cuda.is_available() else "no CUDA (it will be very slow)")
EOF
say "done. Next: run get_weights.sh once (needs your Hugging Face login), then use 'Make a move'."

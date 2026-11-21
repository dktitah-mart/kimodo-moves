# Setting it up: what actually happened

These notes come from a real install: Windows 11 + WSL2 Ubuntu, an RTX 4090, and AssetFurnace 0.5.4 updated to
0.6.0, in November 2026. They cover the problems we hit and how we got past each one.

## 1. AssetFurnace 0.6.0 or newer

Add-ons arrived in 0.6.0. To update, run the installer again over your folder:

```bash
curl -fsSL https://raw.githubusercontent.com/Bingeljell/image-to-3dlab/main/install.sh | bash -s -- --dir ~/image-to-3dlab
```

**"Address already in use" at the end:** the old studio was still serving port 8777, so the new one could not start.
Stop it and start again:

```bash
pkill -f viewer/serve.py; sleep 2; cd ~/image-to-3dlab && ./lab
```

An agent's AssetFurnace MCP connector keeps reporting the old version until its process restarts. In the Claude
desktop app, that means restarting the app.

## 2. Installing the add-on

```bash
sudo apt install -y build-essential libeigen3-dev     # Kimodo builds a small C++ part
./lab addon add --unlisted <repo-url-or-path>@<40-character commit>
```

A local `git bundle` file works as the path. AssetFurnace labels the add-on "Unknown" because it is not in their
list; that is expected. `setup.sh` installs PyTorch (CUDA 12.4) and Kimodo at a pinned commit into the add-on's own
`.venv`, which takes a few minutes.

To check it, from the AssetFurnace folder:

```bash
addons/kimodo/.venv/bin/python -c "import torch, kimodo; print(torch.__version__, torch.cuda.is_available())"
```

## 3. Weights, and the Llama 3 gate

Kimodo's text encoder is LLM2Vec on Meta-Llama-3-8B-Instruct. Meta's repository on Hugging Face is gated, and our
request sat in review for more than a day. Llama 3's licence allows passing the weights on together with the
licence, so open copies exist; `get_weights.sh --mirror` uses `NousResearch/Meta-Llama-3-8B-Instruct`. It points
the LLM2Vec adapters at that copy (their `adapter_config.json` names `meta-llama/…`) and keeps everything in
`encoders/`. `run.sh` sets `TEXT_ENCODERS_DIR` so Kimodo reads from there.

```bash
cd addons/kimodo
.venv/bin/hf auth login          # your own read token
bash get_weights.sh --mirror     # or without --mirror once Meta approves you
```

The download is about 18 GB. Every run after that is offline (`HF_HUB_OFFLINE=1`).

## 4. Running it

- From the studio: Add-ons → Kimodo moves → Make a move.
- From an agent through AssetFurnace's MCP: `run_addon("kimodo", "move", {...})`. **Pass every input as a
  string**, including `"seconds": "3"` and `"text_on_cpu": "false"`. Passing real numbers and booleans failed with
  a bare "Error executing tool".
- Timing on an RTX 4090 with everything on the GPU: about 30 s per take of 2–5 s.
- Each run folder holds `<run>.glb` (SOMA skeleton plus a clay figure), `<run>.npz` (Kimodo's own file, for your
  engine), and `provenance.json` (prompt, seed, model, licences). Keep the provenance: it is how you regenerate a
  take or answer where a move came from.

## 5. Getting moves into Godot

Copy the `.npz` files into your project and use `godot/kimodo_retarget.gd` (see `retarget.md`). A naming scheme that
scales: `k_<clip>.npz` (`k_slash.npz`), with a role suffix for variants (`k_walk_elder.npz`), so the engine can pick
one from the clip name and the character's role.

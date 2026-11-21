# Kimodo moves — text to game animation, on your own GPU

Type what a body does, in English, and get a game-ready animation. This repository has three parts:

- **An [AssetFurnace](https://assetfurnace.com) add-on** that runs [NVIDIA Kimodo](https://github.com/nv-tlabs/kimodo)
  (text → 3D human motion) locally and writes an animated GLB plus Kimodo's motion file.
- **Godot 4 scripts** (`godot/`) that read Kimodo's `.npz` directly and retarget it onto your own `Skeleton3D`. They
  cut the clip into a loop, a one-shot action, a death, a ladder climb or a turn on the spot.
- **Notes from real use** (`docs/`): the retarget maths, prompts that work for game moves (with 32 tested ones for
  soldiers, workers and townsfolk), setup problems and their fixes, and licences.

Made by **Vladimir** ([@dktitah-mart](https://github.com/dktitah-mart)) — indie game developer. It grew out of
animating soldiers, workers and townsfolk for a historical RTS of his.

## What this adds on top of Kimodo and AssetFurnace

NVIDIA Kimodo is a research model with a command line; AssetFurnace is a local studio for 3D assets. Neither one
gives you game animations out of the box. This repository fills the gap:

- **A one-click install inside AssetFurnace.** `setup.sh` builds Kimodo at a pinned commit, with PyTorch, the C++
  foot clean-up, and checks for missing compilers, Eigen and Python headers that explain what to install. Every run
  is offline.
- **A way past the Llama 3 gate.** Kimodo's text encoder needs Meta's gated Llama 3. `get_weights.sh --mirror`
  builds it on an open copy of the same weights and rewires the LLM2Vec adapters to it, so you are not blocked for
  days waiting for approval.
- **A real animation file.** Kimodo writes a NumPy archive; the add-on also writes a glTF (GLB) with the SOMA
  skeleton, the motion and a skinned figure, verified to reproduce the motion exactly, plus `provenance.json`.
- **Retargeting onto your own rig in Godot.** This handles limb alignment from any rest pose (A-pose included),
  hips scaled to your character's size, and facing.
- **Clips a game can use.** Kimodo stands still before an action and drifts while doing it. The retarget finds
  seamless loops, trims one-shots to the motion, keeps deaths lying, and makes climbs and turns stay in place.
- **Tested prompts** for soldiers, workers and townsfolk, and a way to check takes, because Kimodo often does
  something plausible but different from what you asked.
- **Instructions for AI agents** ([AGENTS.md](AGENTS.md)), so Claude, GPT/Codex or Cursor can install and use all
  of this for you.

## Using it with an AI agent

Open this repository in your agent (Claude Code, Codex, Cursor, …) and say: *"Read AGENTS.md and set up Kimodo moves
in my AssetFurnace, then make me a sword strike for my Godot character."* The agent knows the install order, which
steps need you (sudo, your Hugging Face login, the 18 GB download), how to drive AssetFurnace's MCP server, how
to pick good takes and how to retarget them.

| Doc | What's in it |
|---|---|
| [docs/retarget.md](docs/retarget.md) | How a SOMA motion lands on an A-pose rig; how clips are cut |
| [docs/prompts.md](docs/prompts.md) | What to write so Kimodo gives usable strikes, loops and work moves; 32 tested prompts |
| [docs/setup-notes.md](docs/setup-notes.md) | AssetFurnace update, WSL build tools, the Llama 3 gate and the open-copy workaround, MCP quirks |
| [docs/licences.md](docs/licences.md) | Which licence covers what |
| [AGENTS.md](AGENTS.md) | Step-by-step for AI agents |

## The AssetFurnace add-on

One tool, **Make a move**. Its inputs:

| Input | What it does |
|---|---|
| What the body does | One move, in English: *"A soldier thrusts a spear forward, then steps back."* |
| Length | 1–10 seconds. |
| Seed | Another number gives another take of the same text. |
| Model | `Kimodo-SOMA-RP-v1.1` (default, broader set of moves) or `Kimodo-SOMA-SEED-v1.1`. |
| Text encoder on CPU | The text encoder (Llama 3 8B) needs about 17 GB of video memory with everything on the GPU. With this on, the GPU needs about 3 GB, and the encoder loads into system memory instead (about 20 GB). |

What it writes, in `output/addon-kimodo/<run>/`:

- `<run>.glb` is the SOMA skeleton (77 joints, Y up, metres, 30 fps) with the move as its animation, plus a clay
  stick figure skinned to it so the Library can show it. The bind pose is SOMA's T-pose. Retarget it like any
  other mocap clip.
- `<run>.npz` is Kimodo's own motion file (`global_rot_mats`, `posed_joints`, foot contacts …). Games that
  retarget Kimodo themselves read this file (`godot/` does).
- `move.json` records the text, length, seed, model and frame count.

## Install

1. **AssetFurnace 0.6.0 or newer.** Add-ons arrived in 0.6.0.
2. **A Hugging Face account with access to Llama 3.** Kimodo's text encoder is built on the gated
   [`meta-llama/Meta-Llama-3-8B-Instruct`](https://huggingface.co/meta-llama/Meta-Llama-3-8B-Instruct). Open that page
   and accept Meta's licence. Access is per account and usually comes within hours. Then make a **read** token at
   <https://huggingface.co/settings/tokens>.
3. **Install the add-on** from the AssetFurnace folder:

   ```bash
   ./lab addon add --unlisted https://github.com/dktitah-mart/kimodo-moves@<40-character commit>
   ```

   `setup.sh` runs once. It makes `.venv` with PyTorch (CUDA 12.4 build) and Kimodo at a pinned commit, and builds
   Kimodo's small C++ part. That needs `g++` (and Eigen, which it fetches if missing); on Ubuntu or WSL, `sudo apt install build-essential libeigen3-dev`. For another CUDA
   build, set `KIMODO_TORCH_INDEX`, for example `https://download.pytorch.org/whl/cu121`.
4. **Fetch the weights once.** About 18 GB goes into your Hugging Face cache:

   ```bash
   cd addons/kimodo
   .venv/bin/hf auth login        # paste your own token; the add-on never stores or sees it
   bash get_weights.sh            # add --seed to also fetch the SEED model
   ```

   Meta's approval can take days. To go on without it, run `bash get_weights.sh --mirror`. It builds the text
   encoder on an open copy of the same Llama 3 weights (`NousResearch/Meta-Llama-3-8B-Instruct`; Llama 3's licence
   allows passing them on together with the licence) and keeps it in `encoders/`.

After that, every run is offline (`HF_HUB_OFFLINE=1`).

## In Godot

Copy `godot/kimodo_clip.gd` and `godot/kimodo_retarget.gd` into your project:

```gdscript
var clip := KimodoClip.new()
clip.load_npz("res://moves/strike.npz")
var rt := KimodoRetarget.new()
rt.bone_map = KimodoRetarget.MIXAMO      # or GODOT_HUMANOID, or {your_bone: SOMA_joint}
var anim := rt.build($Armature/Skeleton3D, clip, {"cut": "action", "length": 0.9, "skeleton_path": "Armature/Skeleton3D"})
```

[docs/retarget.md](docs/retarget.md) explains the maths and the cuts.

## Writing prompts

One sentence, one action, present tense. Kimodo has no props, so describe what the arms do: *"…the left arm held
forward as if holding a shield"*. See [docs/prompts.md](docs/prompts.md).

## Licences

| What | Licence |
|---|---|
| This add-on's code | Apache-2.0 (`LICENSE`) |
| Kimodo's code | Apache-2.0 (NVIDIA) |
| Kimodo SOMA weights (RP v1.1, SEED v1.1) | [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) |
| LLM2Vec adapters (McGill-NLP) | MIT |
| Meta-Llama-3-8B-Instruct | [Meta Llama 3 Community License](https://www.llama.com/llama3/license/) |

The add-on avoids Kimodo's SMPL-X models, which carry a research-only licence. The moves you make are output of
these models, and their licences say what you may do with that output. Read them (or have your lawyer read them)
before shipping moves in a commercial game.

## Tests

```bash
python3 tests/test_glb.py      # builds a GLB from a sample motion and checks the skeleton reproduces it exactly
python3 tests/make_sample.py && godot --headless --path tests/godot -s test_retarget.gd   # retarget onto an A-pose rig
```

## Author

**Vladimir** — [github.com/dktitah-mart](https://github.com/dktitah-mart). Issues and pull requests are welcome; if
you ship something with these moves, I'd love to see it.

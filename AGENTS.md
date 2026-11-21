# Instructions for AI agents (Claude, GPT/Codex, Gemini, Cursor, …)

You are helping someone make game animations from text with this repository. Read this file first. It tells you what
to do and in what order, and which steps the human must do themselves.

## What this repository is

- `addon.json`, `setup.sh`, `get_weights.sh`, `run.sh`, `kimodo_move.py` — an **AssetFurnace add-on**. It runs
  NVIDIA Kimodo (text → human motion) on the user's own NVIDIA GPU.
- `godot/kimodo_clip.gd`, `godot/kimodo_retarget.gd` — **Godot 4** scripts. They read Kimodo's `.npz` and retarget
  it onto any `Skeleton3D`.
- `docs/` — `retarget.md` (the maths and the cuts), `prompts.md` (what to write; 32 tested prompts),
  `setup-notes.md` (real install problems and fixes), `licences.md`.

## Install (in this order)

1. **AssetFurnace ≥ 0.6.0** (<https://assetfurnace.com>). On Windows it runs in WSL2. Check the version with its
   MCP `status` tool or `./lab --version`. To update, run the installer again over the folder (`docs/setup-notes.md`
   §1). If the new studio fails with "Address already in use", the old one still holds port 8777: stop it.
2. **Build tools** (WSL/Ubuntu): `sudo apt install -y build-essential libeigen3-dev`. The human runs this, because
   sudo needs their password.
3. **Install the add-on** from the AssetFurnace folder:
   `./lab addon add --unlisted https://github.com/dktitah-mart/kimodo-moves@<40-character commit>`.
   It shows a plan and asks y/N; the human confirms. AssetFurnace's MCP `install_addon` only installs listed
   add-ons, so this one goes through the CLI.
4. **Weights, about 18 GB:** `cd addons/kimodo && .venv/bin/hf auth login && bash get_weights.sh`.
   - **Never type, ask for or store the user's Hugging Face token.** They run `hf auth login` themselves.
   - Meta's Llama 3 repository is gated and approval can take days. `bash get_weights.sh --mirror` uses an open
     copy of the same weights (same licence). Tell the user this, and let them choose.
   - Downloading 18 GB is the user's decision. Ask first.
5. **Check it:** `addons/kimodo/.venv/bin/python -c "import torch, kimodo; print(torch.cuda.is_available())"` should
   print `True`.

## Making moves

Through AssetFurnace's MCP server (preferred):

```
run_addon(addon_id="kimodo", tool="move", inputs={
  "prompt": "A person raises the right hand above the head and quickly strikes down at an enemy in front, the left arm held forward as if holding a shield.",
  "seconds": "2.5", "seed": "1", "model": "Kimodo-SOMA-RP-v1.1", "text_on_cpu": "false"})
run_status(run_id=..., wait_seconds=50)      # about 30 s per take on an RTX 4090
```

- **Pass every input as a string**, numbers and the toggle included. Real numbers or booleans fail with a bare
  "Error executing tool".
- Each take lands in `output/addon-kimodo/<run>/`: `<run>.glb`, `<run>.npz` (use this one in engines) and
  `provenance.json` (prompt, seed, model). Keep the provenance next to anything you ship.
- Make **2–3 seeds per move** and pick the best. Kimodo varies a lot between seeds.
- Without the MCP server, from the add-on folder: `bash run.sh <out_dir> "<prompt>" <seconds> <seed> <model> <true|false>`.

## Picking good takes (do this, don't skip it)

Kimodo makes plausible human motion that is often **not what was asked**: a run comes out backwards, a repeated
action freezes after one swing, an overhead strike stops at shoulder height. Check every take before you use it:

- **Travel:** compare `posed_joints[-1, 0] - posed_joints[0, 0]` (hips) with the facing in `global_root_heading`.
  A walk moves forwards, a side-step sideways, a strike stays in place.
- **Look at it:** render a 10-frame stick figure from `posed_joints`, using the parents in
  `godot/kimodo_clip.gd → PARENTS`. Frozen poses and wrong directions show at a glance.
- **Overhead moves:** the hand should rise above the head, then move down fast (more than 4 m/s).

`docs/prompts.md` lists what works. Most importantly, describe what the arms do ("…the left arm held forward as if
holding a shield"), because Kimodo has no props.

## Godot

Copy `godot/*.gd` into the project, then:

```gdscript
var clip := KimodoClip.new(); clip.load_npz("res://moves/strike.npz")
var rt := KimodoRetarget.new(); rt.bone_map = KimodoRetarget.MIXAMO   # or GODOT_HUMANOID, or your own map
var anim := rt.build(skeleton, clip, {"cut": "action", "length": 0.9, "skeleton_path": "Armature/Skeleton3D"})
```

Cuts: `walk`, `run`, `idle`, `work` (loops), `action` (one-shot, trimmed to the motion, no drift), `death` (to the
end), `climb` (loop with the climb removed), `turn` (loop with the hips' turn removed), and `""` (whole clip). For a
rig whose bone names match neither map, write `{your_bone: SOMA_joint}` for hips, spine ×3, neck, head, both
shoulders, arms, forearms, hands, thighs, shins, feet and toes. The SOMA names are in `KimodoClip.SOMA77`.

## Tests (run after any change)

```bash
python3 tests/test_glb.py
python3 tests/make_sample.py && godot --headless --path tests/godot -s test_retarget.gd
```

Both must print `ok` / `FAILS: 0`.

## Rules

- Licences: Kimodo's SOMA weights are under the NVIDIA Open Model License, the text encoder under the Llama 3
  Community License (`docs/licences.md`). Do not switch the add-on to Kimodo's SMPL-X models: their licence is
  research-only.
- Do not commit weights, generated `.npz`/`.glb` files, `.venv/` or `encoders/`.
- Commits use Conventional Commits (`feat:`, `fix:`, `docs:`), and `CHANGELOG.md` is updated with every change.

# Changelog

## 0.2.1

- Retarget aligns the full limb frame (palm normal for arms, foot direction for legs), not only the bone direction: hands and forearms no longer twist, so held props stay in the grip. Optional `finger_map` for unusual finger names. Test checks palms.

## 0.2.0

- Godot 4 scripts: `godot/kimodo_clip.gd` reads Kimodo `.npz` (native or AssetFurnace-packed), `godot/kimodo_retarget.gd` retargets onto any `Skeleton3D` with loop / action / death / climb / turn cuts. Test on an A-pose rig.
- Docs: retarget maths, prompts (32 tested), setup notes, licences.

## 0.1.1

- `get_weights.sh --mirror`: text encoder on an open copy of Llama 3 (NousResearch, same licence) while Meta's approval is pending; `run.sh` points Kimodo at it.

## 0.1.0

- First version: one tool, "Make a move" (text → Kimodo SOMA motion), writing an animated GLB, Kimodo's NPZ and
  `move.json`. Kimodo is pinned to commit e1c219c99b4b94ba48be1fb6a1cbc64ecee4c954; the weights come from
  `get_weights.sh`.

# Putting a Kimodo motion on your own skeleton

This explains `godot/kimodo_retarget.gd`. The same maths drives the soldiers, workers and townsfolk of the author's
RTS, where it feeds a vertex-animation baker. It works for any humanoid skeleton in Godot 4.

## What Kimodo gives you

Kimodo animates SOMA, a 77-joint human skeleton. The axes are Y up, +Z forward and +X to the character's left. That
is the same as a glTF character facing +Z, so no axis swap is needed.

For every frame the `.npz` holds two arrays:

- `global_rot_mats[t, j]` — the world rotation of joint *j*, **measured from SOMA's T-pose**. Call it *G_j(t)*.
- `posed_joints[t, j]` — the world position of joint *j*.

Rotations measured from the T-pose mean this: joint *j* sits at
*x_j = x_p + G_p (N_j − N_p)*, where *p* is the parent and *N* the T-pose positions. The file does not store the
T-pose, but frame 0 gives it back:

> *N_j = N_p + G_p(0)ᵀ (x_j(0) − x_p(0))*, with *N_hips = 0*.

`KimodoClip.load_npz` does this. It also reads AssetFurnace's packed clips (`quats`, `joints0`, `hips`).

## Your rest pose is not a T-pose

Most rigs rest in an A-pose, or at least not in SOMA's T-pose. Copying *G* onto your bones straight would bend the
arms by the difference between the two poses. So every limb bone first gets an **alignment rotation** *A*: the
shortest arc that turns the bone's own rest direction (bone → its child) into SOMA's T-pose direction for the same
bone:

> *A_b = arc(rest_dir_b, N_next − N_b)*

The limbs are shoulder → upper arm → forearm → hand, and thigh → shin → foot → toe. Hands and toes have no child to
aim at, so they take their parent's *A*. The spine, neck and head get no alignment. They take SOMA's bend as it is.

## The world target of each bone

> *world_b(t) = face · G_soma(b)(t) · A_b · rest_world_b*

Read it right to left. Start from your bone's rest orientation. Turn it into SOMA's T-pose (*A*). Apply Kimodo's
rotation from the T-pose (*G*). Finally turn the whole motion to face +Z (*face*, below). The bone's local key is
*parent_worldᵀ · world_b*.

Bones you do not map keep their rest pose under their parent: fingers, twist bones, props and weapon sockets. A
sword held in the hand therefore stays in the grip. The author's game goes one step further and takes the fingers from the
model's own clip, so the grip is the one the artist made.

Why the limb directions come out exact: a bone's child sits at *rest_world_b · offset*. After the formula, its
direction is *face · G · A · rest_dir = face · G · (N_next − N_b)* — exactly SOMA's direction. The Godot test
checks this on an A-pose skeleton with odd rest rotations, and the error is below 0.001°.

## The hips path

The hips move along SOMA's path, scaled by **hip height**: your hips above your feet, divided by SOMA's. A shorter
character takes proportionally shorter steps, so the feet do not slide. The facing rotation is applied to the path
too.

## Facing

The motion is turned so the character faces +Z. The angle comes from how the **hips faced at the start** of the
piece, not from where it travels. A side-step stays a side-step and a back-step stays a back-step. For a forward
walk or run (travel within 40° of facing), the travel direction is used instead, so the loop runs exactly along +Z.

## Cutting the clip

Kimodo does not make clean game clips. A one-shot action usually stands still first, does the move in the middle,
then settles. A walk starts from standing. `opts.cut` picks how to cut:

| cut | for | what happens |
|---|---|---|
| `walk`, `run`, `idle`, `work` | loops | Finds the stretch whose end pose (and pose velocity) best matches its start, with a length between 0.8–1.7 s (walk), 0.5–1.2 s (run), 2–4.5 s (idle) or 1–5 s (work). Poses are compared **relative to the hips**, so travel and turning do not count. The first 0.3 s (starting from standing) is skipped. |
| `action` | strike, throw, shield bash, getting hit | Trims to the motion. Per-frame "energy" is the angular speed of arms, legs, spine and head relative to the hips, plus hips turning and hips speed, smoothed over 0.1 s. The piece runs from the first to the last frame above a quarter of the peak, padded by 0.25 s before and 0.3 s after. The horizontal drift is removed linearly, so the clip ends where it started. `length` retimes it. |
| `death` | death | From the start of the motion to the **end** of the clip, so the body stays lying. |
| `climb` | ladder | A loop with the climb removed: the hips' vertical drift is taken out linearly. Your code moves the character up. |
| `turn` | turning on the spot | A loop with the hips' turn removed: the yaw is undone linearly over the piece. The character steps in place facing forward, and your code turns it. |
| `""` | anything else | The whole clip as it is. |

## Using it

```gdscript
var clip := KimodoClip.new()
if not clip.load_npz("res://moves/strike.npz"):
    push_error(clip.err)
var rt := KimodoRetarget.new()
rt.bone_map = KimodoRetarget.MIXAMO        # or GODOT_HUMANOID, or your own {your_bone: SOMA_joint}
var anim := rt.build($Armature/Skeleton3D, clip, {"cut": "action", "length": 0.9, "skeleton_path": "Armature/Skeleton3D"})
$AnimationPlayer.get_animation_library("").add_animation("strike", anim)
```

After `build`, `rt.window` holds the piece of the Kimodo clip that was used. For walk and run loops, `rt.speed`
holds the travel speed on your character, so you can match the clip to how fast your character moves.

## Tests

- `python3 tests/test_glb.py` — the GLB the add-on writes reproduces the motion exactly.
- `python3 tests/make_sample.py && godot --headless --path tests/godot -s test_retarget.gd` — the retarget on an
  A-pose skeleton: limb directions, unmapped bones, hips path, the action cut and retiming. The sample is synthetic
  (random rotations), not model output.

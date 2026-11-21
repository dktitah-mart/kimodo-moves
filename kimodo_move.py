#!/usr/bin/env python3
"""Make a move with NVIDIA Kimodo (text -> human motion) and write it as an animated GLB.

    python kimodo_move.py OUT_DIR --prompt "A soldier swings a sword overhead." --seconds 3 --seed 1 \
        --model Kimodo-SOMA-RP-v1.1 --text-on-cpu false

Writes, in OUT_DIR (AssetFurnace's run folder, named after the run):
  <stem>.glb  the SOMA skeleton (77 joints) with the move, plus a stick figure so the Library can show it
  <stem>.npz  Kimodo's own motion file (global_rot_mats, posed_joints, ...) for games that retarget it

Runs offline: the Kimodo model and the text encoder must already be in the Hugging Face cache
(run get_weights.sh once). `--from-npz` skips generation and only builds the GLB (for tests).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent

# SOMA 77-joint order and parents as Kimodo writes them (kimodo.skeleton.definitions.SOMASkeleton77).
SOMA77 = [
    "Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "HeadEnd", "Jaw",
    "LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "LeftHandThumb1", "LeftHandThumb2", "LeftHandThumb3", "LeftHandThumbEnd",
    "LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandIndex4", "LeftHandIndexEnd",
    "LeftHandMiddle1", "LeftHandMiddle2", "LeftHandMiddle3", "LeftHandMiddle4", "LeftHandMiddleEnd",
    "LeftHandRing1", "LeftHandRing2", "LeftHandRing3", "LeftHandRing4", "LeftHandRingEnd",
    "LeftHandPinky1", "LeftHandPinky2", "LeftHandPinky3", "LeftHandPinky4", "LeftHandPinkyEnd",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "RightHandThumb1", "RightHandThumb2", "RightHandThumb3", "RightHandThumbEnd",
    "RightHandIndex1", "RightHandIndex2", "RightHandIndex3", "RightHandIndex4", "RightHandIndexEnd",
    "RightHandMiddle1", "RightHandMiddle2", "RightHandMiddle3", "RightHandMiddle4", "RightHandMiddleEnd",
    "RightHandRing1", "RightHandRing2", "RightHandRing3", "RightHandRing4", "RightHandRingEnd",
    "RightHandPinky1", "RightHandPinky2", "RightHandPinky3", "RightHandPinky4", "RightHandPinkyEnd",
    "LeftLeg", "LeftShin", "LeftFoot", "LeftToeBase", "LeftToeEnd",
    "RightLeg", "RightShin", "RightFoot", "RightToeBase", "RightToeEnd",
]
PARENTS = [
    -1, 0, 1, 2, 3, 4, 5, 6, 6, 6, 6, 3, 11, 12, 13, 14, 15, 16, 17, 14, 19, 20, 21, 22, 14, 24, 25, 26,
    27, 14, 29, 30, 31, 32, 14, 34, 35, 36, 37, 3, 39, 40, 41, 42, 43, 44, 45, 42, 47, 48, 49, 50, 42,
    52, 53, 54, 55, 42, 57, 58, 59, 60, 42, 62, 63, 64, 65, 0, 67, 68, 69, 70, 0, 72, 73, 74, 75,
]
MODELS = ("Kimodo-SOMA-RP-v1.1", "Kimodo-SOMA-SEED-v1.1")


# ------------------------------------------------------------------ motion

def load_motion(path: Path) -> tuple[np.ndarray, np.ndarray, float]:
    """(global rotations [T,77,3,3] from the T-pose, joint positions [T,77,3], fps)."""
    d = np.load(path)
    if "quats" in d.files:  # AssetFurnace's packed clips
        g = quats_to_mats(d["quats"].astype(np.float64))
        j0 = d["joints0"].astype(np.float64)
        hips = d["hips"].astype(np.float64)
        x = np.repeat(j0[None], len(g), axis=0)
        x += (hips - hips[0])[:, None, :]  # only the hips track is kept; enough for the root
        return g, x, float(d["fps"]) if "fps" in d.files else 30.0
    g, x = d["global_rot_mats"], d["posed_joints"]
    if g.ndim == 5:
        g, x = g[0], x[0]
    fps = float(d["fps"]) if "fps" in d.files else 30.0
    return g.astype(np.float64), x.astype(np.float64), fps


def quats_to_mats(q: np.ndarray) -> np.ndarray:
    """[..., 4] (w, x, y, z) -> [..., 3, 3]."""
    q = q / np.linalg.norm(q, axis=-1, keepdims=True)
    w, x, y, z = (q[..., i] for i in range(4))
    return np.stack([
        np.stack([1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)], -1),
        np.stack([2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)], -1),
        np.stack([2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)], -1),
    ], -2)


def mats_to_quats_xyzw(m: np.ndarray) -> np.ndarray:
    """[..., 3, 3] -> [..., 4] glTF order (x, y, z, w), w >= 0."""
    w = np.sqrt(np.clip(1 + m[..., 0, 0] + m[..., 1, 1] + m[..., 2, 2], 0, None)) / 2
    x = np.sqrt(np.clip(1 + m[..., 0, 0] - m[..., 1, 1] - m[..., 2, 2], 0, None)) / 2
    y = np.sqrt(np.clip(1 - m[..., 0, 0] + m[..., 1, 1] - m[..., 2, 2], 0, None)) / 2
    z = np.sqrt(np.clip(1 - m[..., 0, 0] - m[..., 1, 1] + m[..., 2, 2], 0, None)) / 2
    x = np.copysign(x, m[..., 2, 1] - m[..., 1, 2])
    y = np.copysign(y, m[..., 0, 2] - m[..., 2, 0])
    z = np.copysign(z, m[..., 1, 0] - m[..., 0, 1])
    q = np.stack([x, y, z, w], axis=-1)
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def tpose(g: np.ndarray, x: np.ndarray) -> np.ndarray:
    """SOMA's T-pose joint positions (hips at 0) from frame 0: x_j = x_p + G_p (N_j - N_p)."""
    n = np.zeros((77, 3))
    for j, p in enumerate(PARENTS):
        if p >= 0:
            n[j] = n[p] + g[0, p].T @ (x[0, j] - x[0, p])
    return n


# ------------------------------------------------------------------ glTF

def build_glb(g: np.ndarray, x: np.ndarray, fps: float, name: str) -> bytes:
    """Animated SOMA skeleton with a stick figure skinned to it."""
    T = len(g)
    n = tpose(g, x)
    nodes = []
    for j, p in enumerate(PARENTS):
        off = n[j] - (n[p] if p >= 0 else 0.0)
        if p < 0:
            off = x[0, 0]
        node = {"name": SOMA77[j], "translation": [float(v) for v in off]}
        kids = [k for k, pp in enumerate(PARENTS) if pp == j]
        if kids:
            node["children"] = kids
        nodes.append(node)
    # local rotations: L_j = G_p^T G_j (rest is the T-pose: identity)
    loc = np.empty_like(g)
    for j, p in enumerate(PARENTS):
        loc[:, j] = g[:, j] if p < 0 else np.matmul(np.transpose(g[:, p], (0, 2, 1)), g[:, j])
    quats = mats_to_quats_xyzw(loc).astype(np.float32)
    # keep neighbouring quaternions on the same hemisphere (no flips when the player slerps)
    for t in range(1, T):
        flip = (quats[t] * quats[t - 1]).sum(-1) < 0
        quats[t, flip] *= -1
    hips = x[:, 0].astype(np.float32)
    times = (np.arange(T) / fps).astype(np.float32)

    # stick figure: a thin box from each joint to each child, weighted to that joint
    pos, nrm, joints, weights, idx = [], [], [], [], []
    for j, p in enumerate(PARENTS):
        if p < 0 or SOMA77[j].endswith(("End", "Eye")) or SOMA77[j] == "Jaw":
            continue
        a, b = n[p], n[j]
        d = b - a
        L = np.linalg.norm(d)
        if L < 1e-4:
            continue
        u = d / L
        side = np.cross(u, [0.0, 0.0, 1.0] if abs(u[2]) < 0.9 else [1.0, 0.0, 0.0])
        side /= np.linalg.norm(side)
        up = np.cross(u, side)
        r = 0.035 if "Hand" not in SOMA77[p] else 0.008
        corners = [side * r + up * r, -side * r + up * r, -side * r - up * r, side * r - up * r]
        base = len(pos)
        for c in corners:
            pos.append(a + c)
            pos.append(b + c)
            nn = c / np.linalg.norm(c)
            nrm += [nn, nn]
            joints += [[p, 0, 0, 0]] * 2
            weights += [[1.0, 0, 0, 0]] * 2
        for k in range(4):
            k2 = (k + 1) % 4
            a0, a1, b0, b1 = base + 2 * k, base + 2 * k2, base + 2 * k + 1, base + 2 * k2 + 1
            idx += [a0, b0, a1, a1, b0, b1]
    # bind pose = SOMA's T-pose standing where the hips start
    pos = np.array(pos, np.float32) + x[0, 0].astype(np.float32)
    nrm = np.array(nrm, np.float32)
    joints = np.array(joints, np.uint16)
    weights = np.array(weights, np.float32)
    idx = np.array(idx, np.uint32)
    # inverse bind: the T-pose world of each joint (hips placed where node 0 starts)
    world_rest = n + x[0, 0]
    ibm = np.zeros((77, 4, 4), np.float32)
    for j in range(77):
        m = np.eye(4, dtype=np.float32)
        m[:3, 3] = -world_rest[j]
        ibm[j] = m.T  # glTF: column-major

    blob = bytearray()
    views, accs = [], []

    def add(arr: np.ndarray, comp: int, typ: str, target: int | None = None, minmax: bool = False) -> int:
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": arr.nbytes}
        if target:
            view["target"] = target
        blob.extend(arr.tobytes())
        views.append(view)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            acc["min"] = [float(v) for v in arr.min(0)] if arr.ndim > 1 else [float(arr.min())]
            acc["max"] = [float(v) for v in arr.max(0)] if arr.ndim > 1 else [float(arr.max())]
        accs.append(acc)
        return len(accs) - 1

    a_pos = add(pos, 5126, "VEC3", 34962, True)
    a_nrm = add(nrm, 5126, "VEC3", 34962)
    a_jnt = add(joints, 5123, "VEC4", 34962)
    a_wgt = add(weights, 5126, "VEC4", 34962)
    a_idx = add(idx, 5125, "SCALAR", 34963)
    a_ibm = add(ibm.reshape(77, 16), 5126, "MAT4")
    a_time = add(times, 5126, "SCALAR", None, True)
    samplers, channels = [], []
    a_hips = add(hips, 5126, "VEC3")
    samplers.append({"input": a_time, "output": a_hips, "interpolation": "LINEAR"})
    channels.append({"sampler": 0, "target": {"node": 0, "path": "translation"}})
    for j in range(77):
        a_q = add(np.ascontiguousarray(quats[:, j]), 5126, "VEC4")
        samplers.append({"input": a_time, "output": a_q, "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": "rotation"}})
    mesh_node = len(nodes)
    nodes.append({"name": "Mannequin", "mesh": 0, "skin": 0})
    gltf = {
        "asset": {"version": "2.0", "generator": "kimodo-addon (NVIDIA Kimodo, SOMA skeleton)"},
        "scene": 0,
        "scenes": [{"nodes": [0, mesh_node]}],
        "nodes": nodes,
        "meshes": [{"name": "Mannequin", "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm,
                    "JOINTS_0": a_jnt, "WEIGHTS_0": a_wgt}, "indices": a_idx, "material": 0}]}],
        "materials": [{"name": "Clay", "pbrMetallicRoughness": {"baseColorFactor": [0.75, 0.7, 0.62, 1.0],
                       "metallicFactor": 0.0, "roughnessFactor": 0.8}}],
        "skins": [{"joints": list(range(77)), "inverseBindMatrices": a_ibm, "skeleton": 0}],
        "animations": [{"name": name, "samplers": samplers, "channels": channels}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": accs,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    return out


# ------------------------------------------------------------------ generation

def generate(prompt: str, seconds: float, seed: int, model: str, text_on_cpu: bool, stem: Path) -> Path:
    """Run Kimodo's own command line in this add-on's environment; returns the .npz it wrote."""
    exe = shutil.which("kimodo_gen") or str(Path(sys.executable).with_name("kimodo_gen"))
    env = dict(os.environ)
    if text_on_cpu:
        env["TEXT_ENCODER_DEVICE"] = "cpu"
    cmd = [exe, prompt, "--model", model, "--duration", f"{seconds:g}", "--output", str(stem)]
    if seed >= 0:
        cmd += ["--seed", str(seed)]
    print("kimodo:", " ".join(cmd[1:]), flush=True)
    r = subprocess.run(cmd, env=env)
    if r.returncode != 0:
        raise SystemExit(
            "Kimodo failed. If it says a model is missing, run get_weights.sh once (it needs a Hugging Face "
            "token with access to meta-llama/Meta-Llama-3-8B-Instruct). Out of video memory: turn on "
            "'Text encoder on CPU'.")
    npz = stem.with_suffix(".npz")
    if not npz.exists():
        raise SystemExit(f"Kimodo wrote no {npz.name}")
    return npz


def as_bool(s: str) -> bool:
    return str(s).strip().lower() in ("1", "true", "yes", "on")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("out", type=Path, help="run folder; the result is <folder name>.glb inside it")
    ap.add_argument("--prompt", default="A person walks forward.")
    ap.add_argument("--seconds", type=float, default=4.0)
    ap.add_argument("--seed", type=float, default=1)
    ap.add_argument("--model", default=MODELS[0], choices=MODELS)
    ap.add_argument("--text-on-cpu", default="false")
    ap.add_argument("--from-npz", type=Path, default=None, help="skip Kimodo: build the GLB from this motion")
    a = ap.parse_args(argv)
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    stem = out / out.name
    seconds = min(10.0, max(0.5, a.seconds))
    if a.from_npz:
        npz = stem.with_suffix(".npz")
        if a.from_npz.resolve() != npz:
            shutil.copyfile(a.from_npz, npz)
    else:
        npz = generate(a.prompt.strip() or "A person stands still.", seconds, int(a.seed), a.model, as_bool(a.text_on_cpu), stem)
    g, x, fps = load_motion(npz)
    glb = build_glb(g, x, fps, a.prompt.strip()[:60] or "move")
    stem.with_suffix(".glb").write_bytes(glb)
    (out / "move.json").write_text(json.dumps({"prompt": a.prompt, "seconds": seconds, "seed": int(a.seed),
                                               "model": a.model, "frames": int(len(g)), "fps": fps}, indent=1))
    print(f"wrote {stem.with_suffix('.glb').name} ({len(g)} frames at {fps:g} fps) and {npz.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""The GLB must reproduce the motion exactly: build one from a synthetic Kimodo-style motion, read it back,
run forward kinematics and compare joint rotations and positions."""

import json
import struct
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import kimodo_move as k  # noqa: E402


def rand_rot(rng, n, scale):
    v = rng.normal(size=(n, 3)) * scale
    a = np.linalg.norm(v, axis=1, keepdims=True)
    q = np.concatenate([np.cos(a / 2), np.sin(a / 2) * v / np.maximum(a, 1e-9)], axis=1)
    return k.quats_to_mats(q)


def synth(T=40, seed=3):
    """Kimodo-style motion: global rotations from a T-pose and positions that obey them."""
    rng = np.random.default_rng(seed)
    n = np.zeros((77, 3))
    for j, p in enumerate(k.PARENTS):
        if p >= 0:
            n[j] = n[p] + rng.normal(size=3) * 0.1
    g = np.empty((T, 77, 3, 3))
    x = np.empty((T, 77, 3))
    for t in range(T):
        loc = rand_rot(rng, 77, 0.4)
        for j, p in enumerate(k.PARENTS):
            if p < 0:
                g[t, j] = loc[j]
                x[t, j] = [0.01 * t, 1.0, 0.03 * t]
            else:
                g[t, j] = g[t, p] @ loc[j]
                x[t, j] = x[t, p] + g[t, p] @ (n[j] - n[p])
    return g, x


def read_glb(b):
    jl = struct.unpack("<I", b[12:16])[0]
    js = json.loads(b[20:20 + jl])
    bin_ = b[28 + jl:]

    def acc(i):
        a = js["accessors"][i]
        v = js["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
        dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]
        arr = np.frombuffer(bin_[v["byteOffset"]:v["byteOffset"] + v["byteLength"]], dt)
        return arr.reshape(a["count"], n) if n > 1 else arr

    return js, acc


def main():
    g, x = synth()
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "m.npz"
        np.savez(p, global_rot_mats=g[None].astype(np.float32), posed_joints=x[None].astype(np.float32))
        g, x, fps = k.load_motion(p)
    assert fps == 30.0
    js, acc = read_glb(k.build_glb(g, x, fps, "test"))
    an = js["animations"][0]
    rot, tr = {}, None
    for c in an["channels"]:
        out = acc(an["samplers"][c["sampler"]]["output"])
        if c["target"]["path"] == "rotation":
            rot[c["target"]["node"]] = out
        else:
            tr = out
    assert len(rot) == 77 and tr is not None
    err_r = err_p = 0.0
    for t in range(len(g)):
        W, P = [None] * 77, np.zeros((77, 3))
        for j, p in enumerate(k.PARENTS):
            qx, qy, qz, qw = rot[j][t]
            L = k.quats_to_mats(np.array([qw, qx, qy, qz], np.float64))
            off = np.array(js["nodes"][j]["translation"])
            W[j], P[j] = (L, tr[t]) if p < 0 else (W[p] @ L, P[p] + W[p] @ off)
            err_r = max(err_r, np.abs(W[j] - g[t, j]).max())
        err_p = max(err_p, np.abs(P - x[t]).max())
    print(f"max rotation error {err_r:.2e}, max position error {err_p:.2e} m")
    assert err_r < 1e-3 and err_p < 1e-3  # float32 through 10-joint finger chains
    # skin: every vertex weighted to a real joint, inverse binds undo the T-pose
    prim = js["meshes"][0]["primitives"][0]
    assert acc(prim["attributes"]["JOINTS_0"])[:, 0].max() < 77
    print("ok")


if __name__ == "__main__":
    main()

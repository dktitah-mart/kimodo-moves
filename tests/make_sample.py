#!/usr/bin/env python3
"""Write tests/sample.npz: a synthetic Kimodo-format motion (no model output), for the Godot retarget test."""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_glb import synth  # noqa: E402

g, x = synth(T=60, seed=7)
x[:, :, 1] += 0.0
np.savez(Path(__file__).with_name("sample.npz"), global_rot_mats=g[None].astype(np.float32),
         posed_joints=x[None].astype(np.float32))
print("wrote tests/sample.npz", g.shape)

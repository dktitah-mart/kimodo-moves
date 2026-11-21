# SPDX-License-Identifier: Apache-2.0
class_name KimodoClip
extends RefCounted
## A motion made by NVIDIA Kimodo on its SOMA skeleton (77 joints), read straight from the .npz file.
##
## Axes: Y up, +Z forward, +X to the character's left (the same as a glTF character facing +Z).
## Kimodo stores, per frame, each joint's world rotation measured from SOMA's T-pose (`global_rot_mats`) and each
## joint's world position (`posed_joints`). AssetFurnace's packed clips store the same rotations as float16
## quaternions (w, x, y, z) plus the hips path and the first-frame joints; both forms are read.
##
## No Python needed: the .npz (a zip of .npy arrays, float16/32/64, C order) is parsed here.

const SOMA77 := ["Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "HeadEnd", "Jaw",
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
	"RightLeg", "RightShin", "RightFoot", "RightToeBase", "RightToeEnd"]
const PARENTS := [-1, 0, 1, 2, 3, 4, 5, 6, 6, 6, 6, 3, 11, 12, 13, 14, 15, 16, 17, 14, 19, 20, 21, 22, 14, 24, 25, 26,
	27, 14, 29, 30, 31, 32, 14, 34, 35, 36, 37, 3, 39, 40, 41, 42, 43, 44, 45, 42, 47, 48, 49, 50, 42,
	52, 53, 54, 55, 42, 57, 58, 59, 60, 42, 62, 63, 64, 65, 0, 67, 68, 69, 70, 0, 72, 73, 74, 75]

var err := ""
var frames := 0
var fps := 30.0
var rots: Array = []              # [frame] -> Array[Quaternion] (77): world rotation from SOMA's T-pose
var hips := PackedVector3Array()  # hips path, metres
var tpose := PackedVector3Array() # SOMA's T-pose joint positions, hips at the origin
var foot0 := 0.0                  # lowest foot joint on the first frame


## Read a Kimodo .npz (native: global_rot_mats + posed_joints; or AssetFurnace-packed: quats + joints0 + hips).
func load_npz(path: String) -> bool:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		err = "cannot open %s" % path
		return false
	var arr := {}
	for f: String in z.get_files():
		if f.ends_with(".npy"):
			var a := _npy(z.read_file(f))
			if not a.is_empty():
				arr[f.get_basename()] = a
	z.close()
	var j0 := PackedVector3Array()
	if arr.has("quats"):
		var q: Dictionary = arr.quats
		frames = int((q.shape as Array)[0])
		var d: PackedFloat32Array = q.data
		for t in frames:
			var row: Array[Quaternion] = []
			for j in 77:
				var o := (t * 77 + j) * 4
				row.append(Quaternion(d[o + 1], d[o + 2], d[o + 3], d[o]).normalized())
			rots.append(row)
		var jd: PackedFloat32Array = (arr.joints0 as Dictionary).data
		for j in 77:
			j0.append(Vector3(jd[j * 3], jd[j * 3 + 1], jd[j * 3 + 2]))
		var hd: PackedFloat32Array = (arr.hips as Dictionary).data
		for t in frames:
			hips.append(Vector3(hd[t * 3], hd[t * 3 + 1], hd[t * 3 + 2]))
	elif arr.has("global_rot_mats") and arr.has("posed_joints"):
		var g: Dictionary = arr.global_rot_mats
		var sh: Array = g.shape
		if sh.size() == 5:                 # [samples, frames, 77, 3, 3]: the first sample
			sh = sh.slice(1)
		frames = int(sh[0])
		if int(sh[1]) != 77:
			err = "skeleton has %d joints, SOMA 77 expected" % int(sh[1])
			return false
		var gd: PackedFloat32Array = g.data
		var pd: PackedFloat32Array = (arr.posed_joints as Dictionary).data
		for t in frames:
			var row2: Array[Quaternion] = []
			for j in 77:
				var o := (t * 77 + j) * 9
				# numpy rows -> Basis columns
				var b := Basis(Vector3(gd[o], gd[o + 3], gd[o + 6]), Vector3(gd[o + 1], gd[o + 4], gd[o + 7]), Vector3(gd[o + 2], gd[o + 5], gd[o + 8]))
				row2.append(b.orthonormalized().get_rotation_quaternion())
			rots.append(row2)
			hips.append(Vector3(pd[t * 231], pd[t * 231 + 1], pd[t * 231 + 2]))
		for j in 77:
			j0.append(Vector3(pd[j * 3], pd[j * 3 + 1], pd[j * 3 + 2]))
	else:
		err = "%s has no Kimodo motion (quats or global_rot_mats)" % path.get_file()
		return false
	if arr.has("fps"):
		fps = float((arr.fps as Dictionary).data[0])
	# SOMA's T-pose from frame 0: x_j = x_p + G_p (N_j - N_p)  =>  N_j = N_p + G_p^T (x_j - x_p)
	tpose.resize(77)
	tpose[0] = Vector3.ZERO
	for j in range(1, 77):
		var p: int = PARENTS[j]
		tpose[j] = tpose[p] + (rots[0][p] as Quaternion).inverse() * (j0[j] - j0[p])
	foot0 = INF
	for n in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
		foot0 = minf(foot0, j0[SOMA77.find(n)].y)
	return true


func duration() -> float:
	return maxf(0.0, float(frames - 1) / fps)


## Hips height above the feet on the first frame (m).
func hip_height() -> float:
	return hips[0].y - foot0 if frames > 0 else 1.0


## World rotation of joint j at time t (slerp between frames).
func rot_at(j: int, t: float) -> Quaternion:
	var f := clampf(t * fps, 0.0, float(frames - 1))
	var i := int(floor(f))
	var u := f - i
	var a: Quaternion = rots[i][j]
	if u < 1e-4 or i + 1 >= frames:
		return a
	return a.slerp(rots[i + 1][j], u)


func hips_at(t: float) -> Vector3:
	var f := clampf(t * fps, 0.0, float(frames - 1))
	var i := int(floor(f))
	var u := f - i
	return hips[i] if i + 1 >= frames else hips[i].lerp(hips[i + 1], u)


## Which way the hips face at t (radians from +Z towards +X).
func yaw_at(t: float) -> float:
	var f: Vector3 = rot_at(0, t) * Vector3(0, 0, 1)
	return atan2(f.x, f.z)


## .npy -> {shape: Array, data: PackedFloat32Array} (float16/32/64, C order).
static func _npy(b: PackedByteArray) -> Dictionary:
	if b.size() < 10 or b[0] != 0x93 or b.slice(1, 6).get_string_from_ascii() != "NUMPY":
		return {}
	var major := b[6]
	var hl := b.decode_u16(8) if major == 1 else b.decode_u32(8)
	var hs := 10 if major == 1 else 12
	var head := b.slice(hs, hs + hl).get_string_from_ascii()
	var descr := head.get_slice("'descr':", 1).get_slice("'", 1)
	var shp := head.get_slice("'shape':", 1).get_slice("(", 1).get_slice(")", 0)
	var shape := []
	for s in shp.split(",", false):
		if s.strip_edges() != "":
			shape.append(int(s.strip_edges()))
	var n := 1
	for s2: int in shape:
		n *= s2
	var off := hs + hl
	var out := PackedFloat32Array()
	out.resize(n)
	match descr:
		"<f4":
			out = b.slice(off, off + n * 4).to_float32_array()
		"<f2":
			for i in n:
				out[i] = b.decode_half(off + i * 2)
		"<f8":
			var d := b.slice(off, off + n * 8).to_float64_array()
			for i in n:
				out[i] = d[i]
		_:
			return {}
	return {"shape": shape, "data": out}

# SPDX-License-Identifier: Apache-2.0
class_name KimodoRetarget
extends RefCounted
## Put a Kimodo motion on your own Skeleton3D and get an Animation back.
##
##   var clip := KimodoClip.new()
##   clip.load_npz("res://moves/strike.npz")
##   var rt := KimodoRetarget.new()
##   rt.bone_map = KimodoRetarget.MIXAMO     # your bone -> SOMA joint (or write your own)
##   var anim := rt.build(skeleton, clip, {"cut": "action", "length": 0.9})
##   $AnimationPlayer.get_animation_library("").add_animation("strike", anim)
##
## How it works (docs/retarget.md has the maths):
## 1. Kimodo gives each joint's WORLD rotation measured from SOMA's T-pose. Your rest pose is not a T-pose (often an
##    A-pose), so each limb bone first gets an alignment A: the shortest arc that turns the bone's rest direction
##    (bone -> its child) into SOMA's T-pose direction of the same bone. Hands and toes take their parent's A.
## 2. World target of a mapped bone: face * G_soma(t) * A * rest_global. Its local rotation is parent_world^-1 * that.
##    Bones you do not map (fingers, props, twist bones) keep their rest pose.
## 3. The hips path is SOMA's, scaled by the ratio of hip heights (yours / SOMA's), so a short character takes
##    shorter steps instead of sliding.
## 4. How the clip is cut (opts.cut): see CUTS. Kimodo puts a one-shot action in the middle of the clip with a
##    standing start, so "action" trims to where the body actually moves.

## your bone -> SOMA joint. Spine, neck and head take SOMA's bend; limbs are aligned (LIMB) first.
const MIXAMO := {
	"mixamorig_Hips": "Hips", "mixamorig_Spine": "Spine1", "mixamorig_Spine1": "Spine2", "mixamorig_Spine2": "Chest",
	"mixamorig_Neck": "Neck1", "mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "LeftShoulder", "mixamorig_LeftArm": "LeftArm", "mixamorig_LeftForeArm": "LeftForeArm", "mixamorig_LeftHand": "LeftHand",
	"mixamorig_RightShoulder": "RightShoulder", "mixamorig_RightArm": "RightArm", "mixamorig_RightForeArm": "RightForeArm", "mixamorig_RightHand": "RightHand",
	"mixamorig_LeftUpLeg": "LeftLeg", "mixamorig_LeftLeg": "LeftShin", "mixamorig_LeftFoot": "LeftFoot", "mixamorig_LeftToeBase": "LeftToeBase",
	"mixamorig_RightUpLeg": "RightLeg", "mixamorig_RightLeg": "RightShin", "mixamorig_RightFoot": "RightFoot", "mixamorig_RightToeBase": "RightToeBase",
}
## Godot's humanoid profile names (SkeletonProfileHumanoid) -> SOMA
const GODOT_HUMANOID := {
	"Hips": "Hips", "Spine": "Spine1", "Chest": "Spine2", "UpperChest": "Chest", "Neck": "Neck1", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpperLeg": "LeftLeg", "LeftLowerLeg": "LeftShin", "LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightLeg", "RightLowerLeg": "RightShin", "RightFoot": "RightFoot", "RightToes": "RightToeBase",
}
## SOMA joint -> the SOMA joint that gives its direction (limbs only)
const SOMA_NEXT := {"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftLeg": "LeftShin", "LeftShin": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightLeg": "RightShin", "RightShin": "RightFoot", "RightFoot": "RightToeBase"}
## end joints that copy their parent's alignment
const SOMA_ENDS := {"LeftHand": "LeftForeArm", "RightHand": "RightForeArm", "LeftToeBase": "LeftFoot", "RightToeBase": "RightFoot"}

## How to cut the clip.
##   ""       whole clip as it is
##   action   one-shot (strike, throw, getting hit): trimmed to the motion, no drift (ends where it started)
##   death    from the start of the motion to the end of the clip (lies on the ground)
##   walk/run loop: the stretch whose ends match best; faces +Z
##   idle     loop 2-4.5 s;  work: loop 1-5 s (hammering, chopping)
##   climb    loop with the climb removed (your code moves the character up)
##   turn     loop with the hips turn removed (steps in place; your code turns the character)
const LOOP_LEN := {"walk": [0.8, 1.7], "run": [0.5, 1.2], "idle": [2.0, 4.5], "work": [1.0, 5.0], "climb": [0.8, 2.0], "turn": [0.8, 2.0]}

var bone_map: Dictionary = MIXAMO
## filled by build()
var window := Vector2.ZERO     # the piece of the Kimodo clip used, seconds
var speed := 0.0               # walk/run loops: travel speed on YOUR character, m/s
var err := ""


## opts: cut (see CUTS), t0/t1 (seconds, overrides the automatic cut), length (seconds: retime a one-shot),
## fps (keys per second, default the clip's), skeleton_path (track path to the skeleton, default "Skeleton3D").
func build(skel: Skeleton3D, clip: RefCounted, opts := {}) -> Animation:
	err = ""
	var cut := String(opts.get("cut", ""))
	var t0 := float(opts.get("t0", -1.0))
	var t1 := float(opts.get("t1", -1.0))
	if t0 < 0.0 or t1 <= t0:
		t0 = 0.0
		t1 = clip.call("duration")
		if LOOP_LEN.has(cut):
			window = loop_window(clip, LOOP_LEN[cut])
			t0 = window.x
			t1 = window.y
		elif cut == "action" or cut == "death":
			window = action_window(clip, cut == "death")
			t0 = window.x
			t1 = window.y
	window = Vector2(t0, t1)
	var dur := t1 - t0
	var once := cut in ["", "action", "death"]
	var out_len := float(opts.get("length", 0.0)) if once and float(opts.get("length", 0.0)) > 0.05 else dur
	var SOMA: Array = clip.get_script().SOMA77
	# facing: as the hips faced at the start of the piece (side and back steps stay side and back); a forward walk
	# is turned to run exactly along +Z
	var h0: Vector3 = clip.call("hips_at", t0)
	var h1: Vector3 = clip.call("hips_at", t1)
	var trav := Vector2(h1.x - h0.x, h1.z - h0.z)
	var yaw0: float = clip.call("yaw_at", t0)
	var yaw1: float = clip.call("yaw_at", t1)
	var face := Quaternion(Vector3.UP, -yaw0)
	if cut in ["walk", "run"] and trav.length() > 0.3 and absf(wrapf(atan2(trav.x, trav.y) - yaw0, -PI, PI)) < deg_to_rad(40.0):
		face = Quaternion(Vector3.UP, -atan2(trav.x, trav.y))
	# rest pose (global) of the skeleton
	var nb := skel.get_bone_count()
	var rest_g: Array[Transform3D] = []
	for i in nb:
		rest_g.append(skel.get_bone_global_rest(i))
	var by_name := {}
	for i in nb:
		by_name[skel.get_bone_name(i)] = i
	var soma_of := {}       # bone index -> SOMA index
	var name_of_soma := {}  # SOMA name -> bone index
	for b: String in bone_map:
		if by_name.has(b):
			var si := SOMA.find(String(bone_map[b]))
			if si >= 0:
				soma_of[by_name[b]] = si
				name_of_soma[String(bone_map[b])] = by_name[b]
	if not name_of_soma.has("Hips"):
		err = "bone_map has no bone for SOMA Hips on this skeleton"
		return null
	# limb alignment A: rest direction -> SOMA T-pose direction
	var tpose: PackedVector3Array = clip.get("tpose")
	var A := {}
	for bi: int in soma_of:
		A[bi] = Quaternion.IDENTITY
	for sname: String in SOMA_NEXT:
		var nxt: String = SOMA_NEXT[sname]
		if not name_of_soma.has(sname) or not name_of_soma.has(nxt):
			continue
		var bi2: int = name_of_soma[sname]
		var have: Vector3 = rest_g[name_of_soma[nxt]].origin - rest_g[bi2].origin
		var want: Vector3 = tpose[SOMA.find(nxt)] - tpose[SOMA.find(sname)]
		if have.length() > 1e-5 and want.length() > 1e-5:
			A[bi2] = _arc(have.normalized(), want.normalized())
	for e: String in SOMA_ENDS:
		if name_of_soma.has(e) and name_of_soma.has(SOMA_ENDS[e]):
			A[name_of_soma[e]] = A[name_of_soma[SOMA_ENDS[e]]]
	# size: your hips over your feet vs SOMA's
	var hips_i: int = name_of_soma["Hips"]
	var fy := INF
	for fnm in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		if name_of_soma.has(fnm):
			fy = minf(fy, rest_g[name_of_soma[fnm]].origin.y)
	if fy == INF:
		fy = 0.0
	var ratio: float = (rest_g[hips_i].origin.y - fy) / maxf(0.1, float(clip.call("hip_height")))
	var hips_par := skel.get_bone_parent(hips_i)
	var Pg: Transform3D = rest_g[hips_par] if hips_par >= 0 else Transform3D.IDENTITY
	# keys
	var kfps := float(opts.get("fps", clip.get("fps")))
	var n := maxi(2, int(round(dur * kfps)))
	var anim := Animation.new()
	anim.length = out_len
	anim.loop_mode = Animation.LOOP_NONE if once else Animation.LOOP_LINEAR
	var sk_path := String(opts.get("skeleton_path", "Skeleton3D"))
	var rot_track := {}
	for bi3: int in soma_of:
		var tr_i := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr_i, NodePath("%s:%s" % [sk_path, skel.get_bone_name(bi3)]))
		rot_track[bi3] = tr_i
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("%s:%s" % [sk_path, skel.get_bone_name(hips_i)]))
	for i in n + 1:
		var u := float(i) / n
		var t := t0 + dur * u
		var key_t := out_len * u
		var face_t := face
		if cut == "turn":
			face_t = Quaternion(Vector3.UP, -(yaw0 + wrapf(yaw1 - yaw0, -PI, PI) * u))
		# world rotation of every bone this frame (memoised, parents first)
		var gq := {}
		for bi4 in nb:
			_world(skel, bi4, t, face_t, clip, soma_of, A, rest_g, gq)
		for bi5: int in soma_of:
			var par := skel.get_bone_parent(bi5)
			var pq: Quaternion = gq[par] if par >= 0 else Quaternion.IDENTITY
			anim.rotation_track_insert_key(rot_track[bi5], key_t, (pq.inverse() * (gq[bi5] as Quaternion)).normalized())
		# hips: SOMA's path, scaled; drift removed where the cut asks for it
		var hp: Vector3 = face * ((clip.call("hips_at", t) as Vector3) - h0)
		var dy := (clip.call("hips_at", t) as Vector3).y - h0.y
		if cut == "action" or cut == "turn":
			var hend: Vector3 = face * (h1 - h0)
			hp -= Vector3(hend.x, 0.0, hend.z) * u
		if cut == "climb":
			dy -= (h1.y - h0.y) * u
		var w := rest_g[hips_i].origin + Vector3(hp.x, 0.0, hp.z) * ratio + Vector3(0.0, dy * ratio, 0.0)
		anim.position_track_insert_key(pos_track, key_t, Pg.affine_inverse() * w)
	speed = trav.length() * ratio / maxf(dur, 1e-3) if cut in ["walk", "run"] else 0.0
	return anim


## World rotation of bone bi at t, memoised in gq (parents first).
func _world(skel: Skeleton3D, bi: int, t: float, face: Quaternion, clip: RefCounted, soma_of: Dictionary, A: Dictionary,
		rest_g: Array[Transform3D], gq: Dictionary) -> Quaternion:
	if gq.has(bi):
		return gq[bi]
	var par := skel.get_bone_parent(bi)
	var pq := _world(skel, par, t, face, clip, soma_of, A, rest_g, gq) if par >= 0 else Quaternion.IDENTITY
	var g: Quaternion
	if soma_of.has(bi):
		g = face * (clip.call("rot_at", soma_of[bi], t) as Quaternion) * (A[bi] as Quaternion) * rest_g[bi].basis.get_rotation_quaternion()
	else:
		g = pq * skel.get_bone_rest(bi).basis.get_rotation_quaternion()      # unmapped: rest pose under its parent
	gq[bi] = g.normalized()
	return gq[bi]


## Loop: [t0, t1] whose end pose (and pose velocity) matches its start best, length within lim (seconds).
## Poses are compared relative to the hips, so travel and turning do not count. The first 0.3 s (starting from
## standing) is skipped.
static func loop_window(clip: RefCounted, lim: Array) -> Vector2:
	var fr: int = clip.get("frames")
	var kfps: float = clip.get("fps")
	var SOMA: Array = clip.get_script().SOMA77
	var joints := []
	for nm in ["LeftLeg", "LeftShin", "LeftFoot", "RightLeg", "RightShin", "RightFoot", "LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "Spine2", "Chest"]:
		joints.append(SOMA.find(nm))
	var rots: Array = clip.get("rots")
	var lo := maxi(2, int(float(lim[0]) * kfps))
	var hi := int(float(lim[1]) * kfps)
	var best := Vector2(0.0, float(fr - 1) / kfps)
	var bd := INF
	for a in range(int(0.3 * kfps), fr - lo):
		var ha: Quaternion = rots[a][0]
		for b in range(a + lo, mini(fr, a + hi + 1)):
			var hb: Quaternion = rots[b][0]
			var d := 0.0
			for j: int in joints:
				d += (ha.inverse() * (rots[a][j] as Quaternion)).angle_to(hb.inverse() * (rots[b][j] as Quaternion))
			if a + 1 < fr and b + 1 < fr:
				for j2: int in joints:
					d += 0.5 * (ha.inverse() * (rots[a + 1][j2] as Quaternion)).angle_to(hb.inverse() * (rots[b + 1][j2] as Quaternion))
			if d < bd:
				bd = d
				best = Vector2(float(a) / kfps, float(b) / kfps)
	return best


## One-shot: where the body actually moves. Per-frame "energy" = angular speed of arms, legs, spine and head
## relative to the hips + hips turning + hips speed, smoothed over 0.1 s. The piece runs from the first to the last
## frame above a quarter of the peak, plus 0.25 s before and 0.3 s after (to_end: to the end of the clip).
static func action_window(clip: RefCounted, to_end: bool) -> Vector2:
	var fr: int = clip.get("frames")
	var kfps: float = clip.get("fps")
	var SOMA: Array = clip.get_script().SOMA77
	var rots: Array = clip.get("rots")
	var hips: PackedVector3Array = clip.get("hips")
	var joints := []
	for nm in ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftLeg", "LeftShin", "RightLeg", "RightShin", "Spine2", "Chest", "Head"]:
		joints.append(SOMA.find(nm))
	var e := PackedFloat32Array()
	e.resize(fr)
	for f in range(1, fr):
		var ha: Quaternion = rots[f - 1][0]
		var hb: Quaternion = rots[f][0]
		var s := 0.0
		for j: int in joints:
			s += (ha.inverse() * (rots[f - 1][j] as Quaternion)).angle_to(hb.inverse() * (rots[f][j] as Quaternion))
		s += ha.angle_to(hb) * 2.0 + (hips[f] - hips[f - 1]).length() * 3.0
		e[f] = s * kfps
	var r := maxi(1, int(0.05 * kfps))
	var sm := PackedFloat32Array()
	sm.resize(fr)
	var peak := 0.0
	for f in fr:
		var acc := 0.0
		var cnt := 0
		for g in range(maxi(0, f - r), mini(fr, f + r + 1)):
			acc += e[g]
			cnt += 1
		sm[f] = acc / cnt
		peak = maxf(peak, sm[f])
	if peak <= 1e-4:
		return Vector2(0.0, float(fr - 1) / kfps)
	var a := 0
	var b := fr - 1
	for f in fr:
		if sm[f] > peak * 0.25:
			a = f
			break
	for f in range(fr - 1, -1, -1):
		if sm[f] > peak * 0.25:
			b = f
			break
	var t0 := maxf(0.0, float(a) / kfps - 0.25)
	var t1 := float(fr - 1) / kfps if to_end else minf(float(fr - 1) / kfps, float(b) / kfps + 0.3)
	if t1 - t0 < 0.4:
		t1 = minf(float(fr - 1) / kfps, t0 + 0.4)
	return Vector2(t0, t1)


## Shortest-arc rotation turning unit vector a into unit vector b.
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length() < 1e-4:
			ax = a.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(d))

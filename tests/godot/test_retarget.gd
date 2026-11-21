extends SceneTree
## KimodoRetarget on an A-pose skeleton: every mapped limb must point where SOMA's does, unmapped bones keep their
## rest, the hips follow SOMA's path scaled by hip height.
##   godot --headless --path tests/godot -s test_retarget.gd      (run tests/make_sample.py first)
const Clip := preload("res://kimodo/kimodo_clip.gd")
const RT := preload("res://kimodo/kimodo_retarget.gd")
var fails := 0
func check(c: bool, what: String) -> void:
	print("  ok   " if c else "  FAIL ", what)
	if not c: fails += 1

const MAP := {"hips": "Hips", "spine": "Spine1", "spine1": "Spine2", "chest": "Chest", "neck": "Neck1", "head": "Head",
	"l_clav": "LeftShoulder", "l_up": "LeftArm", "l_low": "LeftForeArm", "l_hand": "LeftHand",
	"r_clav": "RightShoulder", "r_up": "RightArm", "r_low": "RightForeArm", "r_hand": "RightHand",
	"l_thigh": "LeftLeg", "l_shin": "LeftShin", "l_foot": "LeftFoot", "l_toe": "LeftToeBase",
	"r_thigh": "RightLeg", "r_shin": "RightShin", "r_foot": "RightFoot", "r_toe": "RightToeBase"}

## A skeleton shaped like SOMA's T-pose but scaled 0.8 and with arms 45 deg down (an A-pose), bones with a
## twist in their rest rotation, plus an unmapped "prop" bone on the right hand.
func make_skeleton(clip) -> Skeleton3D:
	var sk := Skeleton3D.new()
	var SOMA: Array = Clip.SOMA77
	var names := MAP.keys()
	var pos := {}
	for b: String in names:
		pos[b] = (clip.tpose[SOMA.find(MAP[b])] as Vector3) * 0.8 + Vector3(0, 1.0, 0)
	# A-pose: swing each arm chain 45 deg down about the shoulder
	for side in [["l_", 1.0], ["r_", -1.0]]:
		var piv: Vector3 = pos[side[0] + "up"]
		var q := Quaternion(Vector3(0, 0, 1), -deg_to_rad(45.0) * float(side[1]))
		for b in ["low", "hand"]:
			pos[side[0] + b] = piv + q * ((pos[side[0] + b] as Vector3) - piv)
	var parent := {"hips": "", "spine": "hips", "spine1": "spine", "chest": "spine1", "neck": "chest", "head": "neck",
		"l_clav": "chest", "l_up": "l_clav", "l_low": "l_up", "l_hand": "l_low", "r_clav": "chest", "r_up": "r_clav",
		"r_low": "r_up", "r_hand": "r_low", "l_thigh": "hips", "l_shin": "l_thigh", "l_foot": "l_shin", "l_toe": "l_foot",
		"r_thigh": "hips", "r_shin": "r_thigh", "r_foot": "r_shin", "r_toe": "r_foot", "prop": "r_hand"}
	pos["prop"] = (pos["r_hand"] as Vector3) + Vector3(0, -0.1, 0.05)
	var order := ["hips", "spine", "spine1", "chest", "neck", "head", "l_clav", "l_up", "l_low", "l_hand", "r_clav", "r_up",
		"r_low", "r_hand", "prop", "l_thigh", "l_shin", "l_foot", "l_toe", "r_thigh", "r_shin", "r_foot", "r_toe"]
	var glob := {}
	var k := 0
	for b: String in order:
		sk.add_bone(b)
		var gb := Basis(Quaternion(Vector3(0.3, 1, 0.2).normalized(), 0.4 + 0.1 * k))     # arbitrary rest rotations
		k += 1
		glob[b] = Transform3D(gb, pos[b])
		var pi := sk.find_bone(String(parent[b]))
		if pi >= 0:
			sk.set_bone_parent(sk.get_bone_count() - 1, pi)
			sk.set_bone_rest(sk.get_bone_count() - 1, (glob[parent[b]] as Transform3D).affine_inverse() * glob[b])
		else:
			sk.set_bone_rest(0, glob[b])
	sk.reset_bone_poses()
	return sk

func _initialize() -> void:
	var clip = Clip.new()
	check(clip.load_npz("res://../sample.npz"), "sample.npz loads (%s)" % clip.err)
	var sk := make_skeleton(clip)
	var rt = RT.new()
	rt.bone_map = MAP
	var anim: Animation = rt.build(sk, clip, {"cut": "", "skeleton_path": "."})
	check(anim != null and rt.err == "", "animation built (%s)" % rt.err)
	check(absf(anim.length - clip.duration()) < 1e-3, "length = clip length")
	var worst := 0.0
	var prop_err := 0.0
	var hips_err := 0.0
	var SOMA: Array = Clip.SOMA77
	var yaw0: float = clip.yaw_at(0.0)
	var face := Quaternion(Vector3.UP, -yaw0)
	var ratio: float = 0.0
	for ti in 7:
		var t: float = float(ti * 9) / clip.fps          # on keys: the synthetic motion jumps between frames
		for i in anim.get_track_count():
			var bone := String(anim.track_get_path(i).get_concatenated_subnames())
			var bi := sk.find_bone(bone)
			if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bi, anim.rotation_track_interpolate(i, t))
			else:
				sk.set_bone_pose_position(bi, anim.position_track_interpolate(i, t))
		var g := {}
		for bi2 in sk.get_bone_count():
			var p := sk.get_bone_parent(bi2)
			var lp := Transform3D(Basis(sk.get_bone_pose_rotation(bi2)), sk.get_bone_pose_position(bi2))
			g[bi2] = (g[p] as Transform3D) * lp if p >= 0 else lp
		# limb directions: ours (bone -> child) vs SOMA's (face * G * T-pose direction)
		for s: String in RT.SOMA_NEXT:
			var ours: String = MAP.find_key(s)
			var nxt: String = MAP.find_key(RT.SOMA_NEXT[s])
			var d_ours: Vector3 = ((g[sk.find_bone(nxt)] as Transform3D).origin - (g[sk.find_bone(ours)] as Transform3D).origin).normalized()
			var tp: Vector3 = clip.tpose[SOMA.find(RT.SOMA_NEXT[s])] - clip.tpose[SOMA.find(s)]
			var d_soma: Vector3 = (face * (clip.rot_at(SOMA.find(s), t) * tp)).normalized()
			worst = maxf(worst, rad_to_deg(d_ours.angle_to(d_soma)))
		# unmapped prop keeps its rest offset from the hand
		var want_prop: Transform3D = (g[sk.find_bone("r_hand")] as Transform3D) * sk.get_bone_rest(sk.find_bone("prop"))
		prop_err = maxf(prop_err, (want_prop.origin - (g[sk.find_bone("prop")] as Transform3D).origin).length())
		# hips: rest + face * (SOMA path - start) * ratio
		var hy: float = sk.get_bone_global_rest(0).origin.y
		if ti == 0:
			var fy := INF
			for f in ["l_foot", "r_foot", "l_toe", "r_toe"]:
				fy = minf(fy, sk.get_bone_global_rest(sk.find_bone(f)).origin.y)
			ratio = (hy - fy) / maxf(0.1, clip.hip_height())
		var want_h: Vector3 = sk.get_bone_global_rest(0).origin + face * (clip.hips_at(t) - clip.hips_at(0.0)) * ratio
		hips_err = maxf(hips_err, (want_h - (g[0] as Transform3D).origin).length())
	print("    worst limb direction error %.3f deg, prop drift %.4f m, hips error %.4f m" % [worst, prop_err, hips_err])
	check(worst < 0.5, "every limb points where SOMA's does (worst %.3f deg)" % worst)
	check(prop_err < 1e-3, "unmapped bones keep their rest under their parent")
	check(hips_err < 1e-3, "hips follow SOMA's path scaled by hip height")
	# one-shot retime
	var a2: Animation = rt.build(sk, clip, {"cut": "action", "length": 0.8, "skeleton_path": "."})
	check(absf(a2.length - 0.8) < 1e-3 and rt.window.y > rt.window.x, "action cut + retime (window %.2f-%.2f s)" % [rt.window.x, rt.window.y])
	print("FAILS: ", fails)
	quit()

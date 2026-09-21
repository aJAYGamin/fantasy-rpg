extends SceneTree

## Imports a SpriteFlow animation export into assets/props/animated/.
##
## Pro Mode returns 32 frames at generation resolution (~1100px wide) on a
## mostly-empty canvas. A torch renders at ~58 world units, so those frames
## carry far more pixel than they will ever show: nine animations imported raw
## run well past 100MB of repo, permanently in git history. This trims and
## downscales them, typically shrinking a loop by 10-20x with no visible change.
##
## Three things it gets right that a naive per-frame trim would not:
##
##  * **One shared crop.** Every frame is cropped to the UNION of all frames'
##    opaque bounds. Cropping each frame to its own bounds would re-centre the
##    content as the flame moves, making the whole prop jitter.
##  * **Alpha bleed before resize.** fix_alpha_edges() pushes colour into the
##    transparent border first, so downscaling cannot blend black into the
##    silhouette and leave a dark fringe.
##  * **Frames renamed to a fixed order.** SpriteFlow names exports after the
##    generation, so output is normalised to frame_01.png ... frame_NN.png.
##
## It also reports the two failure modes worth re-rolling for: base drift (the
## foot wandering between frames) and size instability.
##
## USAGE:
##   godot --headless --path . --script res://tools/import_animation.gd -- \
##       --src "/path/to/unzipped/frames" --name candle [--height 160] [--fps 12]
##
## --height is the output frame height in pixels. Omitted, it is derived from
## the prop's PropLibrary height x4 (clamped 128-320), which keeps enough
## detail to scale up a little without hoarding pixels no one will see.

const OUT_ROOT := "res://assets/props/animated/"
const OVERSAMPLE := 4.0
const MIN_H := 128
const MAX_H := 320

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var src: String = args.get("src", "")
	var prop_name: String = args.get("name", "")
	if src == "" or prop_name == "":
		printerr("usage: --src <dir> --name <prop> [--height N] [--fps N]")
		quit(1)
		return

	var files := _frame_files(src)
	if files.is_empty():
		printerr("no PNG frames found in: ", src)
		quit(1)
		return

	# --- load, and measure the union crop + the quality signals ---
	var images: Array[Image] = []
	var union := Rect2i()
	var bottoms: Array[int] = []
	var widths: Array[int] = []
	for f in files:
		var img := Image.load_from_file(src.path_join(f))
		if img == null:
			printerr("could not read frame: ", f)
			quit(1)
			return
		img.convert(Image.FORMAT_RGBA8)
		var r := img.get_used_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			printerr("frame is fully transparent: ", f)
			quit(1)
			return
		bottoms.append(r.position.y + r.size.y)
		widths.append(r.size.x)
		union = r if images.is_empty() else union.merge(r)
		images.append(img)

	var src_w: int = images[0].get_width()
	var src_h: int = images[0].get_height()
	var drift: int = bottoms.max() - bottoms.min()
	var wobble: int = widths.max() - widths.min()

	print("--- source ---")
	print("  frames      : %d at %dx%d" % [images.size(), src_w, src_h])
	print("  union crop  : %dx%d at (%d,%d)" % [union.size.x, union.size.y, union.position.x, union.position.y])
	print("  base drift  : %d px  %s" % [drift, _verdict(drift, 6, 14)])
	print("  size wobble : %d px  %s" % [wobble, _verdict(wobble, 6, 14)])

	# --- target size ---
	var target_h: int = int(args.get("height", "0").to_int())
	if target_h <= 0:
		var lib := PropLibrary.height_for(prop_name)
		target_h = clampi(int(round(lib * OVERSAMPLE)), MIN_H, MAX_H) if lib > 0.0 else 256
	var scale := float(target_h) / float(union.size.y)
	var target_w := maxi(1, int(round(float(union.size.x) * scale)))

	var out_dir := OUT_ROOT + prop_name
	var abs_out := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(abs_out)

	# --- crop to the shared rect, bleed alpha, downscale, write ---
	var written := 0
	for i in images.size():
		var img: Image = images[i]
		var cropped := img.get_region(union)
		# Push colour outward first: resizing straight alpha would otherwise
		# blend the transparent border's black into the edge.
		cropped.fix_alpha_edges()
		cropped.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
		var path := "%s/frame_%02d.png" % [abs_out, i + 1]
		if cropped.save_png(path) != OK:
			printerr("failed writing ", path)
			quit(1)
			return
		written += 1

	print("--- output ---")
	print("  %d frames at %dx%d -> %s/" % [written, target_w, target_h, out_dir])

	var before := _dir_bytes(src)
	var after := _dir_bytes(abs_out)
	if before > 0:
		print("  size        : %.1f MB -> %.1f MB  (%.1fx smaller)" % [
			before / 1048576.0, after / 1048576.0, float(before) / maxf(1.0, float(after))])
	print("")
	print("Next: add an AnimatedProp and pick \"%s\" from its prop_name dropdown." % prop_name)
	quit(0)

func _verdict(v: int, good: int, warn: int) -> String:
	if v <= good:
		return "OK"
	if v <= warn:
		return "marginal - check the loop"
	return "FAIL - consider re-rolling this prop"

func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var a := raw[i]
		if a.begins_with("--") and i + 1 < raw.size():
			out[a.substr(2)] = raw[i + 1]
			i += 2
		else:
			i += 1
	return out

func _frame_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.to_lower().ends_with(".png"):
			out.append(f)
	out.sort()   # SpriteFlow zero-pads its indices, so lexical order is frame order
	return out

func _dir_bytes(dir_path: String) -> int:
	var total := 0
	var d := DirAccess.open(dir_path)
	if d == null:
		return 0
	for f in d.get_files():
		if not f.to_lower().ends_with(".png"):
			continue
		var fa := FileAccess.open(dir_path.path_join(f), FileAccess.READ)
		if fa != null:
			total += fa.get_length()
			fa.close()
	return total

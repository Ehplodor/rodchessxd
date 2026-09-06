extends SceneTree

const EngineManagerScript := preload("res://src/engine/EngineManager.gd")

var failures := 0

func _init() -> void:
	print("--- Running EngineManager Android discovery unit test ---")
	_test_native_lib_dir_from_maps()
	_test_is_elf_binary()
	_test_find_engine_file_in_dir()
	if failures == 0:
		print("ENGINE ANDROID DISCOVERY TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		print("ENGINE ANDROID DISCOVERY TESTS FAILED: %d assertion(s)." % failures)
		quit(1)

func _check(got: Variant, expected: Variant, label: String) -> void:
	if got != expected:
		failures += 1
		printerr("ASSERT FAILED [%s]: got '%s', expected '%s'" % [label, got, expected])
	else:
		print("  ok - ", label)

func _test_native_lib_dir_from_maps() -> void:
	print("- _native_lib_dir_from_maps")
	var extracted_maps := """55d0d00000-55d0d01000 r--p 00000000 fd:02 1234 /data/app/~~abc123==/com.votreapp.rodchess-xyz==/lib/arm64/libgodot_android.so
55d0d01000-55d0d02000 r-xp 00001000 fd:02 1234 /data/app/~~abc123==/com.votreapp.rodchess-xyz==/lib/arm64/libgodot_android.so
7a00000000-7a00001000 r--p 00000000 fd:02 5678 /data/app/~~abc123==/com.votreapp.rodchess-xyz==/lib/arm64/libc++_shared.so
7a01000000-7a01001000 r--p 00000000 b3:12 9999 /system/lib64/libandroid.so
"""
	_check(
		EngineManagerScript._native_lib_dir_from_maps(extracted_maps),
		"/data/app/~~abc123==/com.votreapp.rodchess-xyz==/lib/arm64",
		"maps extraites -> nativeLibraryDir"
	)

	# Libs mappées depuis l'APK (extractNativeLibs=false) : aucune copie disque, donc rien.
	var in_apk_maps := """7a00000000-7a00001000 r--p 00000000 b3:12 1 /data/app/~~abc==/base.apk!lib/arm64-v8a/libgodot_android.so
7a01000000-7a01001000 r--p 00000000 b3:12 2 /data/app/~~abc==/base.apk!lib/arm64-v8a/libc++_shared.so
"""
	_check(EngineManagerScript._native_lib_dir_from_maps(in_apk_maps), "", "libs in-APK -> ignorees")

	_check(EngineManagerScript._native_lib_dir_from_maps(""), "", "maps vide")
	_check(EngineManagerScript._native_lib_dir_from_maps("rien ici\npas de marqueur\n"), "", "aucun marqueur")

func _test_is_elf_binary() -> void:
	print("- _is_elf_binary / _elf_machine")
	var mgr := EngineManagerScript.new()

	var fake_elf_path := OS.get_user_data_dir() + "/tests_fake_elf.bin"
	var data := PackedByteArray()
	data.resize(20)
	data[0] = 0x7f
	data[1] = 0x45
	data[2] = 0x4c
	data[3] = 0x46
	data[4] = 0x02
	data[18] = 0xB7 # e_machine AArch64
	var f := FileAccess.open(fake_elf_path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()
	_check(mgr._is_elf_binary(fake_elf_path), true, "fichier ELF 64 reconnu")
	_check(mgr._elf_machine(fake_elf_path), 183, "e_machine AArch64")
	_check(mgr._elf_machine_label(183), "arm64 (AArch64)", "label arm64")

	var not_elf_path := "res://project.godot"
	_check(mgr._is_elf_binary(not_elf_path), false, "fichier non-ELF refusé")
	_check(mgr._is_elf_binary(OS.get_user_data_dir() + "/inexistant.bin"), false, "fichier absent")

	DirAccess.remove_absolute(fake_elf_path)

func _test_find_engine_file_in_dir() -> void:
	print("- _find_engine_file_in_dir")
	var mgr := EngineManagerScript.new()

	var test_dir := OS.get_user_data_dir() + "/tests_engine_dir"
	var test_dir2 := test_dir + "_variante"
	# Nettoyage tolérant d'éventuels restes d'une exécution précédente.
	for path in [test_dir + "/libstockfish.so", test_dir2 + "/libstockfish.so.19", test_dir + "/autre.txt"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(test_dir)
	DirAccess.remove_absolute(test_dir2)

	DirAccess.make_dir_recursive_absolute(test_dir)
	DirAccess.make_dir_recursive_absolute(test_dir2)

	var write := FileAccess.open(test_dir + "/libstockfish.so", FileAccess.WRITE)
	write.store_string("x")
	write.close()
	var write2 := FileAccess.open(test_dir + "/autre.txt", FileAccess.WRITE)
	write2.store_string("x")
	write2.close()

	var names := PackedStringArray(["stockfish", "libstockfish.so"])
	_check(mgr._find_engine_file_in_dir(test_dir, names), test_dir + "/libstockfish.so", "nom exact trouve")
	_check(mgr._find_engine_file_in_dir("", names), "", "repertoire vide ignore")

	var write3 := FileAccess.open(test_dir2 + "/libstockfish.so.19", FileAccess.WRITE)
	write3.store_string("x")
	write3.close()
	_check(mgr._find_engine_file_in_dir(test_dir2, names), test_dir2 + "/libstockfish.so.19", "variante de nom toleree")

	# Nettoyage.
	DirAccess.remove_absolute(test_dir + "/libstockfish.so")
	DirAccess.remove_absolute(test_dir + "/autre.txt")
	DirAccess.remove_absolute(test_dir2 + "/libstockfish.so.19")
	DirAccess.remove_absolute(test_dir)
	DirAccess.remove_absolute(test_dir2)

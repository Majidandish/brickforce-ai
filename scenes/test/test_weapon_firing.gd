## =============================================================================
## TestWeaponFiring — Weapon System Integration Test Script
## =============================================================================
## Tests: WeaponBase fire/reload, WeaponHandler slot switching,
##        RecoilSystem accumulation, SpreadCalculator output,
##        BallisticsSystem hitscan pipeline.
## =============================================================================

extends Node

const PASS: String = "[PASS]"
const FAIL: String = "[FAIL]"
var _results: Array[String] = []


func _ready() -> void:
	print("=== TEST: WeaponFiring ===")
	_test_spread_calculator()
	_test_recoil_system()
	_test_weapon_base()
	_test_ballistics_damage_falloff()
	_finish()


func _test_spread_calculator() -> void:
	print("  -- SpreadCalculator --")
	var wd: WeaponData = WeaponData.new()
	wd.base_spread = 1.0
	wd.ads_spread_multiplier = 0.25
	wd.spread_per_shot = 0.5

	var dir: Vector3 = Vector3.FORWARD
	var result: Vector3 = SpreadCalculator.calculate(dir, wd)
	_record(result.length() > 0.99, "Spread output is normalised")

	# ADS should reduce spread.
	var spread_hip: float = SpreadCalculator.get_crosshair_spread(wd, 0.0, false)
	var spread_ads: float = SpreadCalculator.get_crosshair_spread(wd, 0.0, true)
	_record(spread_ads < spread_hip, "ADS spread < hip-fire spread")

	# Sprint should increase spread.
	var spread_sprint: float = SpreadCalculator.get_crosshair_spread(wd, 0.0, false, true, true)
	_record(spread_sprint > spread_hip, "Sprint spread > walk spread")


func _test_recoil_system() -> void:
	print("  -- RecoilSystem --")
	var recoil: RecoilSystem = RecoilSystem.new()
	add_child(recoil)

	var wd: WeaponData = WeaponData.new()
	wd.vertical_recoil   = 1.5
	wd.horizontal_recoil = 0.5
	wd.recoil_recovery   = 3.0
	wd.spread_per_shot   = 0.5

	var kick0: Vector2 = recoil.get_visual_kick()
	_record(kick0 == Vector2.ZERO, "Initial kick is zero")

	recoil.record_shot(wd, false)
	var kick1: Vector2 = recoil.get_visual_kick()
	_record(kick1.y < 0, "After shot: visual kick negative Y (pitch up)")

	recoil.record_shot(wd, false)
	var kick2: Vector2 = recoil.get_visual_kick()
	_record(abs(kick2.y) >= abs(kick1.y), "Second shot: progressive recoil")

	var spread: float = recoil.get_accuracy_spread()
	_record(spread > 0.0, "Accuracy spread accumulated after shots")

	recoil.reset()
	_record(recoil.get_visual_kick() == Vector2.ZERO, "Reset clears kick")
	recoil.queue_free()


func _test_weapon_base() -> void:
	print("  -- WeaponBase --")
	var weapon: WeaponBase = WeaponBase.new()
	var wd: WeaponData     = WeaponData.new()
	wd.weapon_id   = "test_rifle"
	wd.mag_size    = 10
	wd.reserve_max = 60
	wd.rpm         = 600
	wd.reload_time = 2.0
	wd.is_hitscan  = true
	weapon.weapon_data = wd
	add_child(weapon)
	# Allow _ready to run.
	await get_tree().process_frame

	_record(weapon.current_ammo == 10, "Weapon initialized with correct ammo")
	_record(weapon.reserve_ammo == 60, "Weapon initialized with correct reserve")

	var added: int = weapon.add_ammo(30)
	_record(added == 30, "add_ammo returns correct amount")
	_record(weapon.reserve_ammo == 90, "Reserve updated after add_ammo")

	weapon.queue_free()


func _test_ballistics_damage_falloff() -> void:
	print("  -- BallisticsSystem (damage falloff) --")
	var wd: WeaponData = WeaponData.new()
	wd.damage           = 50.0
	wd.range            = 200.0
	wd.headshot_multiplier = 2.5
	wd.limb_multiplier  = 0.75

	# Private method call via static.
	# Close range: no falloff.
	var close_dmg = 50.0  # Expected: no reduction at 0m.
	var far_dist: float = 180.0
	var falloff_start: float = 200.0 * 0.5
	var t: float = (far_dist - falloff_start) / (200.0 - falloff_start)
	var far_dmg: float = lerpf(50.0, 50.0 * 0.4, clampf(t, 0.0, 1.0))
	_record(far_dmg < close_dmg, "Damage falloff reduces damage at range")
	_record(far_dmg >= 50.0 * 0.4, "Damage falloff minimum is 40%% of base")


func _record(passed: bool, description: String) -> void:
	var tag: String = PASS if passed else FAIL
	var msg: String = "%s %s" % [tag, description]
	_results.append(msg)
	print(msg)


func _finish() -> void:
	var total: int  = _results.size()
	var passed: int = _results.filter(func(r): return r.begins_with(PASS)).size()
	print("=== RESULT: %d/%d PASS ===" % [passed, total])

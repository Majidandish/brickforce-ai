## =============================================================================
## TestCharacterMovement — Movement System Integration Test Scene Script
## =============================================================================
## Attach to a Node3D scene that contains:
##   - CharacterBody3D with MovementComponent child
##   - ThirdPersonCamera
##   - Ground plane (StaticBody3D)
## Prints pass/fail to console when run in editor (-s flag) or at runtime.
## =============================================================================

extends Node

const PASS: String = "[PASS]"
const FAIL: String = "[FAIL]"
var _results: Array[String] = []
var _character: CharacterBase
var _movement: MovementComponent
var _frame_count: int = 0
const TEST_FRAMES: int = 120  # Run for 2 seconds at 60fps.


func _ready() -> void:
	print("=== TEST: CharacterMovement ===")
	_character = _find_character()
	if not _character:
		_record(false, "Character node found")
		_finish()
		return
	_record(true, "Character node found")
	_movement = _character.find_child("MovementComponent", false, false)
	_record(_movement != null, "MovementComponent attached")

	if _movement:
		_record(_movement.config != null, "MovementConfig loaded")
		_record(_movement.body == _character, "MovementComponent.body set correctly")


func _physics_process(_delta: float) -> void:
	_frame_count += 1
	if _frame_count == 10:
		_test_walk()
	if _frame_count == 30:
		_test_sprint()
	if _frame_count == 60:
		_test_crouch()
	if _frame_count == 90:
		_test_jump()
	if _frame_count >= TEST_FRAMES:
		set_physics_process(false)
		_finish()


func _test_walk() -> void:
	if not _movement:
		return
	_movement.flag_sprint  = false
	_movement.flag_crouch  = false
	var vel: Vector3 = _movement.calculate_velocity(0.016, Vector2(0, -1))
	_record(vel.z < 0, "Walk forward: velocity.z negative")


func _test_sprint() -> void:
	if not _movement:
		return
	_movement.flag_sprint = true
	var vel: Vector3 = _movement.calculate_velocity(0.016, Vector2(0, -1))
	_record(abs(vel.z) > abs(_movement.config.walk_speed * 0.9), "Sprint faster than walk")
	_movement.flag_sprint = false


func _test_crouch() -> void:
	if not _movement:
		return
	_movement.flag_crouch = true
	var vel: Vector3 = _movement.calculate_velocity(0.016, Vector2(0, -1))
	_record(abs(vel.z) < _movement.config.walk_speed, "Crouch slower than walk")
	_movement.flag_crouch = false


func _test_jump() -> void:
	if not _movement:
		return
	_movement.flag_jump = true
	_movement.calculate_velocity(0.016, Vector2.ZERO)
	_record(_movement.vertical_velocity > 0, "Jump: positive vertical velocity")
	_movement.flag_jump = false


func _record(passed: bool, description: String) -> void:
	var tag: String = PASS if passed else FAIL
	var msg: String = "%s %s" % [tag, description]
	_results.append(msg)
	print(msg)


func _find_character() -> CharacterBase:
	var candidates: Array = get_tree().get_nodes_in_group("characters")
	if candidates.size() > 0:
		return candidates[0] as CharacterBase
	return get_tree().root.find_child("*Character*", true, false) as CharacterBase


func _finish() -> void:
	var total: int = _results.size()
	var passed: int = _results.filter(func(r): return r.begins_with(PASS)).size()
	print("=== RESULT: %d/%d PASS ===" % [passed, total])
	if passed == total:
		print("ALL MOVEMENT TESTS PASSED")
	else:
		print("SOME TESTS FAILED — check output above.")

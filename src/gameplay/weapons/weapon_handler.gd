## =============================================================================
## WeaponHandler — Character Weapon Management Component
## =============================================================================
## Architecture:
##   Manages weapon slots, active weapon switching, holstering/drawing,
##   and aggregates input → weapon actions. One instance per character.
##   Decoupled from character logic via signals.
##
##   Slots: primary | secondary | sidearm | throwable | melee
##
##   Network-safe: weapon state (slot, ammo) must be replicated.
##   Use get_replication_state() / apply_replication_state() for sync.
## =============================================================================

class_name WeaponHandler
extends Node

# ── Slot Names ─────────────────────────────────────────────────────────────────
const SLOT_PRIMARY:   String = "primary"
const SLOT_SECONDARY: String = "secondary"
const SLOT_SIDEARM:   String = "sidearm"
const SLOT_THROWABLE: String = "throwable"
const SLOT_MELEE:     String = "melee"
const SLOT_ORDER: Array[String] = [
	SLOT_PRIMARY, SLOT_SECONDARY, SLOT_SIDEARM, SLOT_THROWABLE, SLOT_MELEE
]

# ── Signals ────────────────────────────────────────────────────────────────────
signal weapon_drawn(weapon: WeaponBase, slot: String)
signal weapon_holstered(weapon: WeaponBase, slot: String)
signal weapon_switched(from_slot: String, to_slot: String)
signal weapon_dropped(weapon_data: WeaponData, ammo: Dictionary)
signal ammo_changed(slot: String, current: int, reserve: int)

# ── State ──────────────────────────────────────────────────────────────────────
var owner_character: CharacterBase = null
var slots: Dictionary = {
	SLOT_PRIMARY:   null,
	SLOT_SECONDARY: null,
	SLOT_SIDEARM:   null,
	SLOT_THROWABLE: null,
	SLOT_MELEE:     null,
}
var active_slot: String       = ""
var active_weapon: WeaponBase = null
var _is_switching: bool       = false
var _switch_timer: float      = 0.0
var _queued_slot: String      = ""


func _ready() -> void:
	name = "WeaponHandler"


func _process(delta: float) -> void:
	_update_switch_timer(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with the owning character.
func initialize(character: CharacterBase) -> void:
	owner_character = character


## Equip a weapon into a slot. Replaces existing if occupied.
func equip(weapon: WeaponBase, slot: String) -> void:
	if not SLOT_ORDER.has(slot):
		Logger.warn("WeaponHandler", "Invalid slot: %s" % slot)
		return
	if slots[slot]:
		_drop_weapon(slot)
	slots[slot] = weapon
	weapon.owner_character = owner_character
	weapon.hide()
	Logger.info("WeaponHandler", "Equipped %s in %s." % [weapon.weapon_id, slot])

	if active_slot == "":
		switch_to(slot)


## Switch to a named slot.
func switch_to(slot: String) -> void:
	if not SLOT_ORDER.has(slot):
		return
	if not slots[slot]:
		Logger.debug("WeaponHandler", "Slot empty: %s" % slot)
		return
	if slot == active_slot:
		return
	if _is_switching:
		_queued_slot = slot
		return

	_start_switch(slot)


## Switch to next occupied slot.
func switch_next() -> void:
	var start: int = SLOT_ORDER.find(active_slot) + 1
	for i in SLOT_ORDER.size():
		var idx: int = (start + i) % SLOT_ORDER.size()
		var s: String = SLOT_ORDER[idx]
		if slots[s] and s != active_slot:
			switch_to(s)
			return


## Switch to previous occupied slot.
func switch_prev() -> void:
	var start: int = SLOT_ORDER.find(active_slot) - 1
	for i in SLOT_ORDER.size():
		var idx: int = (start - i + SLOT_ORDER.size()) % SLOT_ORDER.size()
		var s: String = SLOT_ORDER[idx]
		if slots[s] and s != active_slot:
			switch_to(s)
			return


## Try to fire the active weapon. Returns false if not possible.
func try_fire(aim_direction: Vector3) -> bool:
	if not active_weapon or _is_switching:
		return false
	return active_weapon.try_fire(aim_direction)


## Try to reload the active weapon.
func try_reload() -> bool:
	if not active_weapon or _is_switching:
		return false
	return active_weapon.try_reload()


## Drop the current active weapon.
func drop_active() -> void:
	if active_slot != "":
		_drop_weapon(active_slot)


## Returns the active WeaponBase (null if holstered).
func get_active_weapon() -> WeaponBase:
	return active_weapon


## Returns the weapon in a slot.
func get_weapon_in_slot(slot: String) -> WeaponBase:
	return slots.get(slot, null)


## Check if a slot has an ammo type (for pickup validation).
func has_ammo_type(ammo_type: String) -> bool:
	for slot in slots:
		var w: WeaponBase = slots[slot]
		if w and w.weapon_data and w.weapon_data.ammo_type == ammo_type:
			return true
	return false


## Add ammo to matching weapons.
func add_ammo(ammo_type: String, amount: int) -> int:
	var total_added: int = 0
	for slot in slots:
		var w: WeaponBase = slots[slot]
		if w and w.weapon_data and w.weapon_data.ammo_type == ammo_type:
			total_added += w.add_ammo(amount - total_added)
			if total_added >= amount:
				break
	return total_added


## Returns replication state for network sync.
func get_replication_state() -> Dictionary:
	var state: Dictionary = { "active_slot": active_slot, "slots": {} }
	for slot in slots:
		var w: WeaponBase = slots[slot]
		if w:
			state.slots[slot] = {
				"weapon_id": w.weapon_id,
				"current":   w.current_ammo,
				"reserve":   w.reserve_ammo,
			}
	return state


## Apply a received replication state.
func apply_replication_state(state: Dictionary) -> void:
	var target_slot: String = state.get("active_slot", "")
	if target_slot != active_slot and slots.has(target_slot) and slots[target_slot]:
		switch_to(target_slot)
	for slot in state.get("slots", {}):
		var w: WeaponBase = slots.get(slot)
		if w:
			var slot_data: Dictionary = state.slots[slot]
			w.current_ammo = slot_data.get("current", w.current_ammo)
			w.reserve_ammo = slot_data.get("reserve", w.reserve_ammo)


# ── Internal ───────────────────────────────────────────────────────────────────

func _start_switch(to_slot: String) -> void:
	_is_switching = true
	var from_slot: String = active_slot
	var draw_time: float  = 0.0

	# Holster current.
	if active_weapon:
		active_weapon.unequip()
		weapon_holstered.emit(active_weapon, from_slot)
		draw_time = active_weapon.weapon_data.equip_time if active_weapon.weapon_data else 0.5

	_switch_timer = draw_time
	_queued_slot  = to_slot
	active_slot   = to_slot

	EventBus.weapon_holstered.emit(
		owner_character.character_id if owner_character else -1, from_slot
	)


func _finish_switch() -> void:
	_is_switching = false
	var weapon: WeaponBase = slots.get(active_slot)
	if not weapon:
		active_weapon = null
		return
	active_weapon = weapon
	weapon.equip(owner_character)
	weapon_drawn.emit(weapon, active_slot)
	weapon_switched.emit(_queued_slot if _queued_slot != "" else active_slot, active_slot)
	_queued_slot = ""

	EventBus.weapon_drawn.emit(
		owner_character.character_id if owner_character else -1,
		weapon.weapon_id, active_slot
	)

	# Connect ammo signal.
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed.bind(active_slot))

	if owner_character:
		owner_character.active_weapon = weapon


func _update_switch_timer(delta: float) -> void:
	if not _is_switching:
		return
	_switch_timer -= delta
	if _switch_timer <= 0.0:
		_finish_switch()


func _drop_weapon(slot: String) -> void:
	var weapon: WeaponBase = slots[slot]
	if not weapon:
		return
	if slot == active_slot:
		active_weapon = null
		active_slot   = ""
	slots[slot] = null
	var ammo: Dictionary = weapon.get_ammo_state()
	weapon_dropped.emit(weapon.weapon_data, ammo)
	EventBus.weapon_dropped.emit(
		owner_character.character_id if owner_character else -1,
		weapon.weapon_id,
		owner_character.global_position if owner_character else Vector3.ZERO
	)
	weapon.queue_free()


func _on_ammo_changed(current: int, reserve: int, slot: String) -> void:
	ammo_changed.emit(slot, current, reserve)

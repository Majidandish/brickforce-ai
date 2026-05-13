## =============================================================================
## EventBus — Global Signal Bus (Autoload Singleton)
## =============================================================================
## Purpose:
##   Decoupled publish/subscribe messaging layer. All systems communicate
##   through EventBus rather than direct node references, enabling hot-swap,
##   testability, and future network replication hooks.
##
## Usage:
##   # Emit:  EventBus.player_died.emit(player_id, cause)
##   # Listen: EventBus.player_died.connect(_on_player_died)
## =============================================================================

extends Node

# ── Match Lifecycle ────────────────────────────────────────────────────────────
signal match_started(match_config: Dictionary)
signal match_ended(result: Dictionary)
signal match_paused(reason: String)
signal match_resumed()
signal phase_changed(old_phase: String, new_phase: String)
signal safe_zone_shrinking(center: Vector3, radius: float, time_left: float)
signal safe_zone_tick_damage(amount: float)

# ── Player ─────────────────────────────────────────────────────────────────────
signal player_spawned(player_id: int, position: Vector3)
signal player_died(player_id: int, killer_id: int, cause: String)
signal player_downed(player_id: int, attacker_id: int)
signal player_revived(player_id: int, reviver_id: int)
signal player_took_damage(player_id: int, amount: float, source: String)
signal player_healed(player_id: int, amount: float)
signal player_landed(player_id: int)
signal player_entered_zone(player_id: int, zone_id: String)
signal player_exited_zone(player_id: int, zone_id: String)
signal player_level_up(player_id: int, new_level: int)
signal player_xp_gained(player_id: int, amount: int, source: String)

# ── Weapon ─────────────────────────────────────────────────────────────────────
signal weapon_fired(shooter_id: int, weapon_id: String, position: Vector3, direction: Vector3)
signal weapon_reloaded(owner_id: int, weapon_id: String)
signal weapon_switched(owner_id: int, old_weapon: String, new_weapon: String)
signal weapon_picked_up(owner_id: int, weapon_id: String)
signal weapon_dropped(owner_id: int, weapon_id: String, position: Vector3)
signal ammo_changed(owner_id: int, weapon_id: String, current: int, max_ammo: int)
signal grenade_thrown(thrower_id: int, grenade_type: String, position: Vector3)
signal explosion_occurred(origin: Vector3, radius: float, damage: float)

# ── Hit & Combat ───────────────────────────────────────────────────────────────
signal hit_registered(target_id: int, attacker_id: int, damage: float, hit_point: Vector3, bone: String)
signal headshot_registered(target_id: int, attacker_id: int)
signal kill_registered(killer_id: int, victim_id: int, weapon_id: String)
signal damage_number_requested(position: Vector3, amount: float, is_critical: bool)

# ── Squad / AI ─────────────────────────────────────────────────────────────────
signal squad_formed(squad_id: int, member_ids: Array)
signal squad_dissolved(squad_id: int)
signal squad_member_added(squad_id: int, member_id: int)
signal squad_member_removed(squad_id: int, member_id: int)
signal squad_command_issued(squad_id: int, command: String, target: Variant)
signal ai_state_changed(agent_id: int, old_state: String, new_state: String)
signal ai_spotted_enemy(spotter_id: int, target_id: int, position: Vector3)
signal ai_lost_target(agent_id: int, last_known_position: Vector3)
signal ai_cover_claimed(agent_id: int, cover_node: NodePath)
signal ai_cover_released(agent_id: int, cover_node: NodePath)

# ── Inventory & Items ──────────────────────────────────────────────────────────
signal item_picked_up(owner_id: int, item_id: String, quantity: int)
signal item_dropped(owner_id: int, item_id: String, quantity: int, position: Vector3)
signal item_used(owner_id: int, item_id: String)
signal item_equipped(owner_id: int, item_id: String, slot: String)
signal item_unequipped(owner_id: int, item_id: String, slot: String)
signal inventory_full(owner_id: int)
signal loot_spawned(loot_id: String, position: Vector3, items: Array)
signal loot_container_opened(opener_id: int, container_id: String)

# ── Economy ────────────────────────────────────────────────────────────────────
signal currency_changed(currency_type: String, old_amount: int, new_amount: int)
signal purchase_completed(item_id: String, cost: int, currency_type: String)
signal purchase_failed(item_id: String, reason: String)
signal cosmetic_unlocked(cosmetic_id: String)
signal shop_refreshed(shop_id: String)

# ── UI ─────────────────────────────────────────────────────────────────────────
signal hud_show_requested(element: String)
signal hud_hide_requested(element: String)
signal notification_requested(message: String, type: String, duration: float)
signal screen_fade_requested(target_alpha: float, duration: float)
signal screen_shake_requested(intensity: float, duration: float)
signal crosshair_hit_flash_requested(is_critical: bool)
signal popup_opened(popup_id: String)
signal popup_closed(popup_id: String)

# ── Audio ──────────────────────────────────────────────────────────────────────
signal sound_play_requested(sound_id: String, position: Vector3, volume_db: float)
signal music_change_requested(track_id: String, fade_duration: float)
signal ambient_change_requested(ambient_id: String)
signal audio_snapshot_requested(snapshot: String)

# ── VFX ────────────────────────────────────────────────────────────────────────
signal vfx_play_requested(vfx_id: String, position: Vector3, rotation: Vector3, parent: NodePath)
signal vfx_stop_requested(vfx_id: String)
signal decal_place_requested(decal_id: String, position: Vector3, normal: Vector3)

# ── Save / Settings ────────────────────────────────────────────────────────────
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal settings_changed(category: String, key: String, value: Variant)
signal language_changed(locale: String)

# ── Network ────────────────────────────────────────────────────────────────────
signal server_connected(server_id: String)
signal server_disconnected(reason: String)
signal peer_joined(peer_id: int, data: Dictionary)
signal peer_left(peer_id: int)
signal network_latency_updated(peer_id: int, latency_ms: int)
signal state_sync_received(state: Dictionary)

# ── World ──────────────────────────────────────────────────────────────────────
signal zone_activated(zone_id: String, zone_type: String)
signal zone_deactivated(zone_id: String)
signal destructible_destroyed(object_id: String, position: Vector3)
signal door_opened(door_id: String, opener_id: int)
signal door_closed(door_id: String)
signal vehicle_entered(vehicle_id: String, occupant_id: int)
signal vehicle_exited(vehicle_id: String, occupant_id: int)

# ── Debug / Dev ────────────────────────────────────────────────────────────────
signal debug_command_issued(command: String, args: Array)
signal performance_warning(system: String, message: String, value: float)
signal log_entry_added(level: int, category: String, message: String)


func _ready() -> void:
	name = "EventBus"
	Logger.info("EventBus", "Global event bus initialized.")

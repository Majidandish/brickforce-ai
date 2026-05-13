## =============================================================================
## CurrencyManager — Multi-Currency Economy System (Autoload)
## =============================================================================
## Purpose:
##   Manages all in-game currencies (gold, gems, battle points, etc.)
##   with transaction logging, cap enforcement, and EventBus broadcasting.
##   Integrates with SaveManager for persistence and APIManager for sync.
## =============================================================================

extends Node

## Currency type identifiers.
enum CurrencyType { GOLD, GEMS, BATTLE_POINTS, TOKENS }

const CURRENCY_KEYS: Dictionary = {
	CurrencyType.GOLD:         "gold",
	CurrencyType.GEMS:         "gems",
	CurrencyType.BATTLE_POINTS: "battle_points",
	CurrencyType.TOKENS:       "tokens",
}

const CAPS: Dictionary = {
	"gold":          999_999,
	"gems":          99_999,
	"battle_points": 999_999,
	"tokens":        9_999,
}

const STARTING_BALANCES: Dictionary = {
	"gold":          1_000,
	"gems":          50,
	"battle_points": 0,
	"tokens":        0,
}

signal balance_changed(currency: String, old_amount: int, new_amount: int)
signal transaction_logged(type: String, currency: String, amount: int, reason: String)

var _balances: Dictionary = {}
var _transaction_log: Array[Dictionary] = []


func _ready() -> void:
	name = "CurrencyManager"
	_balances = STARTING_BALANCES.duplicate()
	SaveManager.register_serializer("currency", _save, _load_data)
	Logger.info("CurrencyManager", "Initialized.")


# ── Public API ─────────────────────────────────────────────────────────────────

## Get balance for a currency key (e.g. "gold").
func get_balance(currency: String) -> int:
	return _balances.get(currency, 0)


## Add currency. Returns the actual amount added (may be capped).
func add(currency: String, amount: int, reason: String = "reward") -> int:
	if amount <= 0:
		return 0
	var old: int = _balances.get(currency, 0)
	var cap: int = CAPS.get(currency, 999_999)
	var new_val: int = min(old + amount, cap)
	var actually_added: int = new_val - old
	_balances[currency] = new_val
	_log_transaction("add", currency, actually_added, reason)
	balance_changed.emit(currency, old, new_val)
	EventBus.currency_changed.emit(currency, old, new_val)
	Logger.debug("CurrencyManager", "+%d %s (%s). Balance: %d" % [actually_added, currency, reason, new_val])
	return actually_added


## Spend currency. Returns true on success, false if insufficient funds.
func spend(currency: String, amount: int, reason: String = "purchase") -> bool:
	if amount <= 0:
		return true
	var old: int = _balances.get(currency, 0)
	if old < amount:
		Logger.warn("CurrencyManager", "Insufficient %s: need %d, have %d." % [currency, amount, old])
		return false
	var new_val: int = old - amount
	_balances[currency] = new_val
	_log_transaction("spend", currency, amount, reason)
	balance_changed.emit(currency, old, new_val)
	EventBus.currency_changed.emit(currency, old, new_val)
	Logger.debug("CurrencyManager", "-%d %s (%s). Balance: %d" % [amount, currency, reason, new_val])
	return true


## Returns true if the player can afford the amount.
func can_afford(currency: String, amount: int) -> bool:
	return _balances.get(currency, 0) >= amount


## Get all balances.
func get_all_balances() -> Dictionary:
	return _balances.duplicate()


## Get transaction history (optionally filtered by currency).
func get_transactions(currency: String = "") -> Array[Dictionary]:
	if currency == "":
		return _transaction_log.duplicate()
	var filtered: Array[Dictionary] = []
	for t in _transaction_log:
		if t.currency == currency:
			filtered.append(t)
	return filtered


## Reset to starting balances (e.g. new game).
func reset() -> void:
	for key in STARTING_BALANCES:
		var old: int = _balances.get(key, 0)
		_balances[key] = STARTING_BALANCES[key]
		balance_changed.emit(key, old, _balances[key])
	Logger.info("CurrencyManager", "Balances reset.")


# ── Internal ───────────────────────────────────────────────────────────────────

func _log_transaction(type: String, currency: String, amount: int, reason: String) -> void:
	_transaction_log.append({
		"type":      type,
		"currency":  currency,
		"amount":    amount,
		"reason":    reason,
		"timestamp": Time.get_unix_time_from_system(),
	})
	if _transaction_log.size() > 500:
		_transaction_log.pop_front()
	transaction_logged.emit(type, currency, amount, reason)


func _save() -> Dictionary:
	return { "balances": _balances.duplicate() }


func _load_data(data: Dictionary) -> void:
	if data.has("balances"):
		for key in data.balances:
			if _balances.has(key):
				_balances[key] = int(data.balances[key])
	Logger.info("CurrencyManager", "Balances loaded from save.")

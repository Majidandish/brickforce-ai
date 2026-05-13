## =============================================================================
## ShopManager — In-Game Shop & Store System (Autoload)
## =============================================================================
## Purpose:
##   Manages shop catalogue, purchase validation, transaction processing,
##   daily/weekly rotating offers, and discount logic. Coordinates between
##   CurrencyManager, InventoryManager, and APIManager.
## =============================================================================

extends Node

const DAILY_REFRESH_HOUR: int = 0  # UTC midnight

signal shop_ready(catalogue: Array)
signal purchase_success(item_id: String)
signal purchase_failure(item_id: String, reason: String)
signal catalogue_refreshed()

var _catalogue: Array[Dictionary] = []
var _catalogue_map: Dictionary = {}  # item_id -> item_dict
var _last_refresh_day: int = -1
var _is_loading: bool = false


func _ready() -> void:
	name = "ShopManager"
	EventBus.shop_refreshed.connect(_on_shop_refreshed)
	_fetch_catalogue()
	Logger.info("ShopManager", "Initialized.")


# ── Public API ─────────────────────────────────────────────────────────────────

## Fetch (or refresh) the shop catalogue from the backend.
func _fetch_catalogue() -> void:
	if _is_loading:
		return
	_is_loading = true
	APIManager.shop_get_catalogue(func(success: bool, data: Dictionary):
		_is_loading = false
		if not success:
			Logger.error("ShopManager", "Failed to fetch catalogue.")
			return
		_catalogue = []
		_catalogue_map = {}
		for item in data.get("items", []):
			_catalogue.append(item)
			_catalogue_map[item.get("id", "")] = item
		catalogue_refreshed.emit()
		shop_ready.emit(_catalogue)
		Logger.info("ShopManager", "Catalogue loaded: %d items." % _catalogue.size())
	)


## Attempt to purchase an item.
func purchase(item_id: String) -> void:
	if not _catalogue_map.has(item_id):
		var msg: String = "Item not in catalogue: %s" % item_id
		purchase_failure.emit(item_id, msg)
		EventBus.purchase_failed.emit(item_id, msg)
		return

	var item: Dictionary = _catalogue_map[item_id]
	var currency: String = item.get("currency", "gold")
	var cost: int = _get_effective_cost(item)

	# Ownership check.
	if InventoryManager.has_item(item_id):
		var msg: String = "Already owned: %s" % item_id
		purchase_failure.emit(item_id, msg)
		EventBus.purchase_failed.emit(item_id, msg)
		return

	# Funds check.
	if not CurrencyManager.can_afford(currency, cost):
		var msg: String = "Insufficient %s (need %d, have %d)" % [
			currency, cost, CurrencyManager.get_balance(currency)
		]
		purchase_failure.emit(item_id, msg)
		EventBus.purchase_failed.emit(item_id, msg)
		Logger.warn("ShopManager", msg)
		return

	# Process via backend.
	APIManager.shop_purchase(item_id, currency, func(success: bool, _data: Dictionary):
		if not success:
			var msg: String = "Backend rejected purchase: %s" % item_id
			purchase_failure.emit(item_id, msg)
			EventBus.purchase_failed.emit(item_id, msg)
			return
		# Deduct locally.
		CurrencyManager.spend(currency, cost, "shop:%s" % item_id)
		InventoryManager.add_item(item_id)
		purchase_success.emit(item_id)
		EventBus.purchase_completed.emit(item_id, cost, currency)
		Logger.info("ShopManager", "Purchased: %s for %d %s." % [item_id, cost, currency])
	)


## Get all catalogue items (with discount applied).
func get_catalogue() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _catalogue:
		var copy: Dictionary = item.duplicate()
		copy["effective_cost"] = _get_effective_cost(item)
		copy["owned"] = InventoryManager.has_item(item.get("id", ""))
		result.append(copy)
	return result


## Get items filtered by type.
func get_items_by_type(item_type: String) -> Array[Dictionary]:
	return get_catalogue().filter(func(i): return i.get("type", "") == item_type)


## Get a single item from the catalogue.
func get_item(item_id: String) -> Dictionary:
	return _catalogue_map.get(item_id, {}).duplicate()


## Force a catalogue refresh.
func refresh() -> void:
	_fetch_catalogue()


# ── Internal ───────────────────────────────────────────────────────────────────

func _get_effective_cost(item: Dictionary) -> int:
	var base: int = item.get("cost", 0)
	var discount: float = item.get("discount", 0.0)
	return max(0, int(base * (1.0 - discount)))


func _on_shop_refreshed(_shop_id: String) -> void:
	refresh()

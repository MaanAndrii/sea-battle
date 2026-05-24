## GridModel.gd
## 0=вільно, 1=корабель, 2=заборонена зона, 3=уламки (блокує розміщення)
## ВАЖЛИВО: place_from_nose — основний метод розміщення
## cells[0] завжди = ніс корабля

extends RefCounted

const SIZE = 20
enum CellState { EMPTY, SHIP, BLOCKED, WRECKAGE }
var grid: Array = []

func _init() -> void:
	grid = []
	for y in range(SIZE):
		var row = []
		for x in range(SIZE): row.append(CellState.EMPTY)
		grid.append(row)

func add_wreckage(cells: Array) -> void:
	for c in cells:
		var v = Vector2i(int(c.x), int(c.y))
		if _in_bounds(v):
			grid[v.y][v.x] = CellState.WRECKAGE

# ── Утиліта: всі клітинки від носа ─────────────────────────
## step=0(→): хвіст ліворуч  step=1(↓): хвіст вгору
## step=2(←): хвіст праворуч step=3(↑): хвіст вниз
func cells_from_nose(nose: Vector2i, size: int, step: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(size):
		match step:
			0: result.append(Vector2i(nose.x - i, nose.y))
			1: result.append(Vector2i(nose.x, nose.y - i))
			2: result.append(Vector2i(nose.x + i, nose.y))
			3: result.append(Vector2i(nose.x, nose.y + i))
	return result

# ── Перевірки ───────────────────────────────────────────────
func can_place_from_nose(nose: Vector2i, size: int, step: int) -> bool:
	for c in cells_from_nose(nose, size, step):
		if not _in_bounds(c): return false
		if grid[c.y][c.x] != CellState.EMPTY: return false
	return true

func can_place_excluding_nose(nose: Vector2i, size: int, step: int,
		own_cells: Array) -> bool:
	var own_set: Array[Vector2i] = []
	for c in own_cells:
		own_set.append(Vector2i(int(c.x), int(c.y)))

	var new_cells = cells_from_nose(nose, size, step)
	# Перевірка меж і чужих кораблів
	for c in new_cells:
		if not _in_bounds(c): return false
		var v = Vector2i(c.x, c.y)
		var gv = grid[c.y][c.x]
		if (gv == CellState.SHIP and not own_set.has(v)) or gv == CellState.WRECKAGE:
			return false
	# Перевірка відступу від чужих кораблів
	for c in new_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(c.x + dx, c.y + dy)
				if not _in_bounds(nb): continue
				if grid[nb.y][nb.x] == CellState.SHIP:
					if not own_set.has(Vector2i(nb.x, nb.y)):
						return false
	return true

# ── Розміщення від носа ─────────────────────────────────────
func place_from_nose(nose: Vector2i, size: int, step: int) -> Array[Vector2i]:
	var cells = cells_from_nose(nose, size, step)
	# Перевіряємо межі перед записом
	for c in cells:
		if not _in_bounds(c):
			return []   # не розміщуємо якщо хоч одна клітинка за межами
	for c in cells: grid[c.y][c.x] = CellState.SHIP
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = c.x + dx
				var ny = c.y + dy
				if _in_bounds(Vector2i(nx, ny)) and grid[ny][nx] == CellState.EMPTY:
					grid[ny][nx] = CellState.BLOCKED
	return cells

# ── Сумісність: старий place (від лівої/верхньої) ───────────
func can_place(coord: Vector2i, size: int, horizontal: bool) -> bool:
	for c in get_cells(coord, size, horizontal):
		if not _in_bounds(c): return false
		if grid[c.y][c.x] != CellState.EMPTY: return false
	return true

func place(coord: Vector2i, size: int, horizontal: bool) -> Array[Vector2i]:
	var cells = get_cells(coord, size, horizontal)
	for c in cells: grid[c.y][c.x] = CellState.SHIP
	for c in cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = c.x + dx; var ny = c.y + dy
				if _in_bounds(Vector2i(nx, ny)) and grid[ny][nx] == CellState.EMPTY:
					grid[ny][nx] = CellState.BLOCKED
	return cells

func can_place_excluding(coord: Vector2i, size: int, horizontal: bool,
		own_cells: Array) -> bool:
	var own_set: Array[Vector2i] = []
	for c in own_cells: own_set.append(Vector2i(int(c.x), int(c.y)))
	var new_cells = get_cells(coord, size, horizontal)
	for c in new_cells:
		if not _in_bounds(c): return false
		var gv = grid[c.y][c.x]
		if (gv == CellState.SHIP and not own_set.has(Vector2i(c.x, c.y))) or gv == CellState.WRECKAGE:
			return false
	for c in new_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var nb = Vector2i(c.x + dx, c.y + dy)
				if not _in_bounds(nb): continue
				if grid[nb.y][nb.x] == CellState.SHIP:
					if not own_set.has(Vector2i(nb.x, nb.y)):
						return false
	return true

# ── Видалення ───────────────────────────────────────────────
func remove(cells: Array) -> void:
	for c in cells: grid[c.y][c.x] = CellState.EMPTY
	_rebuild_forbidden()

# ── Утиліти ─────────────────────────────────────────────────
func get_cells(coord: Vector2i, size: int, horizontal: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(size):
		result.append(Vector2i(coord.x + i, coord.y) if horizontal \
			else Vector2i(coord.x, coord.y + i))
	return result

func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE

func _rebuild_forbidden() -> void:
	for y in range(SIZE):
		for x in range(SIZE):
			if grid[y][x] == CellState.BLOCKED: grid[y][x] = CellState.EMPTY
	for y in range(SIZE):
		for x in range(SIZE):
			if grid[y][x] == CellState.SHIP:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx = x + dx; var ny = y + dy
						if _in_bounds(Vector2i(nx, ny)) and grid[ny][nx] == CellState.EMPTY:
							grid[ny][nx] = CellState.BLOCKED

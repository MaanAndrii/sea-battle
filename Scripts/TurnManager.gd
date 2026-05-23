## TurnManager.gd
## Зберігає стан ходу. Три етапи: Move1 → Shoot → Move2

extends Node

signal energy_changed(current: int, maximum: int)
signal phase_changed(phase: String)

# Фази всередині одного ходу
enum Phase { MOVE1, SHOOT, MOVE2, EXECUTING }

const MAX_ENERGY: int = 12

var current_phase: Phase = Phase.MOVE1
var energy:        int   = MAX_ENERGY
var turn_number:   int   = 1

# Кількість пострілів за розміром корабля
static func shots_for_size(size: int) -> int:
	match size:
		2: return 1   # корвет
		3: return 2   # фрегат
		4: return 3   # лінкор
		5: return 0   # авіаносець не стріляє
		_: return 0

static func move_cost(damaged: bool) -> int:
	return 2 if damaged else 1

static func rotation_cost(ship_size: int, damaged: bool) -> int:
	# Поворот = 2x вартість ходу
	return move_cost(damaged) * 2

func spend(amount: int) -> bool:
	if amount > energy: return false
	energy -= amount
	emit_signal("energy_changed", energy, MAX_ENERGY)
	return true

func can_afford(amount: int) -> bool:
	return energy >= amount

func set_phase(p: Phase) -> void:
	current_phase = p
	var names = ["Рух 1", "Постріл", "Рух 2", "Виконання..."]
	emit_signal("phase_changed", names[p])

func end_turn() -> void:
	turn_number  += 1
	energy        = MAX_ENERGY
	current_phase = Phase.MOVE1
	emit_signal("energy_changed", energy, MAX_ENERGY)

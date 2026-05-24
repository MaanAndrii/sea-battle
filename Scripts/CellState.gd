## CellState.gd
## Shared visual/grid cell-state values used across gameplay scripts.
extends RefCounted

const GRID_EMPTY := 0
const GRID_SHIP := 1
const GRID_BLOCKED := 2
const GRID_WRECKAGE := 3

const MISS := 5
const HIT := 6
const PLANNED_SHOT := 7
const OLD_HIT := 8
const NOSE_MARK := 9
const WRECK := 10
const WRECK_ZONE := 11
const BOMB := 12

// The overworld, as the logistics module names it (pure, so the whole rule is unit testable: the
// module's host glue only asks `World.getDimension()` and hands the answer here).
//
// The host has two strings per world: `World.getId()` / `World.getName()` are the world id (the
// folder name, `world`) and `World.getDimension()` the dimension key (`minecraft:overworld`).
// A comparison against the wrong one never matches and never logs.

/// The dimension key of the overworld (`Level.OVERWORLD`), whose tick drives the global networks
/// (`GlobalLogisticsManager.tick`).
const String overworldDimension = 'minecraft:overworld';

/// Whether [dimension] is the overworld's dimension key, the one world whose tick drives the
/// global networks.
///
/// [dimension] must be a dimension key (`World.getDimension()`, `Level.dimension()`), never a
/// world id (`World.getId()`, the folder name `world`): `isOverworldDimension('world')` is
/// `false`, which is what a world id would silently answer here.
bool isOverworldDimension(String dimension) => dimension == overworldDimension;
# Geometry and player helpers

The host API passes positions as bare `(double, double, double)` records.
`pumpkin_api` adds methods to that record type, so `player.position` and
`world.spawnEntity(pos: ...)` work with the same math, with no wrapping.

```dart
final eye = player.position + vec3(0, 1.6, 0);
final target = eye + player.lookDirection * 5;
player.moveTo(target);
```

## Vec3

`typedef Vec3 = (double, double, double)`, `vec3(x, y, z)`, and `Vec3Math`:
`x y z`, `+ - * /` (scalar), `multiplyBy`, `divideBy`, `length`,
`lengthSquared`, `distanceTo`, `distanceSquaredTo`, `horizontalDistanceTo`,
`normalized`, `dot`, `cross`, `lerp`, `angleTo`, `clampLength`, `blockCoords`,
`toBlockPos()`, `toVector3f()`, `rotationTo(target)`, `describe()`.

`directionFromRotation(yaw, pitch)` follows Minecraft: yaw 0 looks +z, yaw 90
looks -x, pitch -90 looks up. `rotationFromDirection` is the inverse.

`BlockPos` gets `center`, `toVec3()`, `offset`, `+`, `-`, `above`, `below`,
`neighbours`, `distanceTo`. `Vector3f` gets `toVec3()`.

## Location

`Location` is immutable plain data: world name, x, y, z, yaw, pitch. It holds
no host handles, so it is safe to store (unlike `Player` or `World`).

```dart
final home = player.location;                  // read
other.teleportTo(server, home);                // throws WorldNotLoadedException
final spawn = world.spawnPoint;                // centered shared spawn
```

`teleportTo` looks the world up by name each time (the host consumes the
world handle on teleport). `Player.moveTo(vec, yaw:, pitch:)` stays in the
current world.

## Cuboid / Region

`Cuboid.corners(a, b)` is a box of whole blocks with inclusive corners:
`volume`, `size*`, `center`, `contains(Vec3)`, `containsBlock(BlockPos)`,
`expand`, `translate`, `intersects`, `intersection`, `union`, lazy `blocks`
(`BlockPos`) and `blockCoords`. `World.fill`, `fillBlock`, `replace` and
`countState` loop over the blocks (the WIT has no bulk fill for arbitrary
regions), so keep regions modest. Changes to unloaded chunks may be ignored
by the host.

## Spatial queries

`Server.playersNear / nearestPlayer / playersIn / playersInWorldNamed`,
`World.entitiesNear / nearestEntity`, `Entity.entitiesWithin`. Results are
sorted nearest first. Worlds are given by name, never as `World` handles,
because passing a `World` to the host consumes it.

## Player and sender helpers

* `sender.requirePlayer()` throws `CommandException` for the console.
* `player.uuidString`, `isOperator(server)`, `hasPermissionLevel`,
  `isCreative` / `isSurvival` / `isAdventure` / `isSpectator`, `isAlive`,
  `healFully()`, `feedFully()`, `eyePosition`, `lookDirection`.
* `player.give(stack)` puts a stack in the first empty slot and returns the
  stack back if the inventory is full (null when placed). `giveItem('diamond',
  count: 100)` also tops up plain stacks and returns how many did not fit.
  Overflow cannot be dropped: the WIT cannot spawn item entities.
* `player.applyEffect(StatusEffectType.speed, duration: Duration(minutes: 1),
  amplifier: 1)`, `effectTimeLeft(type)`. `removeEffect(effect:)`,
  `hasEffect(effect:)` and `clearEffects()` are already generated.

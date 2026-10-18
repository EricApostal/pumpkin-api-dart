# Entity flags and overrides

`entity-flags.wit`. Wrapper: `entity_flags.dart` (`EntityFlag`, `EntityFlagsApi`
on `Entity`, `PlayerFlagsApi` on `Player`, `Context.tickItemEntities`).
Permission `entity-flags` (`Permissions.entityFlags`). Nothing costs anything
until a plugin sets one. Failures throw `HostException`.

```dart
entity.setFlag(EntityFlag.fireImmune, true);
entity.setFlag(EntityFlag.projectilesHitRiders, true);   // what contraptions need
entity.hasFlag(EntityFlag.noFallBounce);
fakePlayer.setPlayerFlag(EntityFlag.ignoredByMobs, true);

entity.overrideSize((2.0, 3.0));          // every pose; null clears
entity.overridePose(EntityPose.swimming); // every pose change ends as this; null clears
player.overridePickupBox((2.0, 1.0, 2.0)); // vanilla (1.0, 0.5, 1.0); null clears

context.tickItemEntities('minecraft:stick', interval: 5);   // 0 stops
context.listen(Events.entityItemUpdate, (server, e) { /* e.entityId, e.stack, e.age */ });
```

Flags: `fireImmune`, `noFallBounce`, `ignoreRidersHit` (the opposite of vanilla;
prefer `projectilesHitRiders`), `projectilesHitRiders`, `ignoreVehicleBox`,
`fluidMovementEvents` (fires `Events.entityFluidMovement`), `ignoredByMobs`.
Bedrock clients get the size override, Java clients keep their own idea of the
box; `Events.entitySize` can still change the result.

The mixin style events that go with this are in
[events-and-time.md](events-and-time.md).

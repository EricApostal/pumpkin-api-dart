# Plugin entities, entity ticking and item entities

`entity-registry.wit`, `entity-ticking.wit` and the entity additions of
`world.wit`. Wrappers: `entities.dart` (`EntityTypeSpec`, `EntityRegistries`,
`Context.tickEntities`, `WorldEntities`, `PluginEntityData`).

## Registering entity types

Permission `registry.entities`; registration closes when the server accepts
connections. Custom types get the ids `vanillaCount + n`.

```dart
final id = EntityRegistries.register(const EntityTypeSpec(
  key: 'my_plugin:contraption',
  width: 2, height: 2,
  category: EntityCategory.misc,
  trackingRange: 10,
  spawnDataChannel: 'my_plugin:spawn_contraption',
));
```

`EntityTypeSpec` has defaults for everything but `key`, `width` and `height`.
Failures (bad key, different definition for a known key, registration closed)
throw `HostException`. `EntityRegistries.idOf` and `vanillaCount` read back.

## Spawning and plugin data

```dart
final entity = await world.spawnPlugin('my_plugin:contraption', (x, y, z),
    syncedData: encodedMetadata, spawnData: payload);
entity.setSyncedData(newMetadata);      // sent to clients tracking it
entity.pluginTypeKey;                    // 'my_plugin:contraption', null for vanilla
entity.resize(3, 3);
```

`pluginSyncedData`/`pluginSpawnData` read the stored bytes. The wire encodings
are yours to produce (`PacketBuffer` helps, see `packet_buffer.dart`).

## Ticking entities

```dart
context.tickEntities(EntityType.zombie, interval: 20);   // 0 stops
context.listen(Events.entityTick, (server, e) { /* e.entityId, e.tick */ });
```

Only vanilla `EntityType`s can be opted in. The setting is global, any plugin
that listens gets the event. Players have `Events.playerTick`.

## Item entities and box queries

```dart
final item = await world.dropItem((x, y, z), stack, velocity: (0, .2, 0), pickupDelay: 10);
await item?.setStack(stack: other);
item?.setNeverDespawn(neverDespawn: true);
final snapshots = world.entitiesIn(Cuboid.corners((0, 64, 0), (9, 68, 9)),
    filter: const EntityFilterItems());          // snapshots: no resources to release
final items = world.itemsIn(box);                  // ItemEntity resources
```

`getEntityByUuid`, `getEntityById`, `isLoaded` and `isAreaLoaded` are on
`World` directly. `Entity.asItem()` and `isItem()` convert. Owned `Entity` and
`ItemEntity` values follow [lifetimes.md](lifetimes.md).

## Entity lifecycle for plugin entities

Wrappers in `entities.dart` (`EntityRegistries`, `PluginEntityData`):

```dart
final serializer = EntityRegistries.registerDataSerializer('my_plugin:carriage'); // registration time
entity.setSyncedEntry(3, [serializer, ...encodedValue]);   // one entry (index 0..254), sent to trackers
entity.setPassengerSeat(rider, 0, 1.2, 0);                   // server places it every tick; not saved
entity.setTracking(updateInterval: 1, trackDeltas: true);    // smaller steps on the client
entity.acceptClientMovement(false);                           // default: the plugin moves its vehicles
final moved = entity.moveBy((0, 0, .2), collide: true);     // returns the distance; not for players
entity.setOnGround(true);
entity.setPositionRotationDelta(pos: p, yaw: 0, pitch: 0, velocity: v); // no teleport packets
context.listen(Events.pluginVehicleInput, (server, e) { /* forward, sideways, jump, sneak, sprint */ });
context.listen(Events.entityStartTracking, (server, e) { /* send your spawn payload */ });
```

`EntityTypeSpec` has `pushable` and `ignoreRidersHit` (the latter is the opposite
of vanilla: prefer the `projectilesHitRiders` flag, [entity-flags.md](entity-flags.md)).
Entries set with `setSyncedEntry` are saved with the entity and sent after the blob
of `setSyncedData` to clients that start tracking. Empty data forgets an entry on
the server only.

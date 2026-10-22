# Sounds, particles, mob effects, map decorations, datapack and synced registries

`extra-registries.wit`. Wrappers: `extra_registries.dart` (`ExtraRegistries`,
`SoundSpec`, `ParticleSpec`, `MobEffectSpec`, `MapDecorationSpec`,
`WorldPluginParticles`).

* Permission `registry.extra` (`Permissions.registryExtra`); all registries are
  append only and close when the server accepts connections.
* The n-th entry registered gets the id `vanilla count + n` in registries that
  clients synchronise. A NeoForge client only gets them when the plugin's
  declaration **names the registry** (`Context.declareNeoForge`,
  `NeoForgeRegistryAddition`): `minecraft:sound_event`, `minecraft:particle_type`,
  `minecraft:mob_effect` and `minecraft:map_decoration_type` are sent like
  `minecraft:item`, and a registry a mod owns (`mymod:thing`,
  `declareSyncedRegistry`) is sent whole only when it is named. Declaring the mod
  vouches for nothing: an entry no declaration names keeps the whole registry out
  of the snapshot, for every plugin. Other clients do not know the entries either
  way.
* Failures throw `HostException`.

```dart
ExtraRegistries.registerSound(const SoundSpec('my_plugin:whirr', fixedRange: 24));
world.playCustomSound(soundName: 'my_plugin:whirr', category: SoundCategory.blocks,
    pos: (x, y, z), volume: 1, pitch: 1);               // by key

ExtraRegistries.registerParticle(const ParticleSpec('my_plugin:spark',
    options: ParticleOptions.color));
world.spawnPluginParticleAt('my_plugin:spark', (x, y, z),
    options: ParticleOptionBytes.color(0xFFFFAA00), count: 8);   // NeoForge players only

ExtraRegistries.registerMobEffect(const MobEffectSpec('my_plugin:sticky',
    category: MobEffectCategory.harmful, color: 0x55FF55,
    modifiers: [MobEffectAttribute(attribute: 'minecraft:movement_speed',
        id: 'my_plugin:sticky', amount: -0.15,
        operation: ModifierOperation.multiplyTotal)]));

ExtraRegistries.registerMapDecoration(const MapDecorationSpec('my_plugin:flag',
    assetName: 'my_plugin_flag'));
```

Mob effects have no tick, applied or removed hooks; the translation key is
`effect.<namespace>.<path>`. `soundId`, `particleId`, `mobEffectId` and
`mapDecorationId` read ids back (vanilla keys work without the `minecraft:`
prefix).

## Datapack registries

```dart
ExtraRegistries.declareDatapackRegistry('minecraft:enchantment');  // or 'mymod:thing'
ExtraRegistries.addDatapackEntry('mymod:thing', 'mymod:gear', networkNbt);
```

The entry is network NBT (a nameless compound); `null` for an entry whose data
the client has. The same entry again is fine, other content is an error.
NeoForge clients get it with the registry data.

## Plugin synced registries

For registries like `create:fan_processing_type`: synced to NeoForge clients with
all entries in id order, **once the declaration names the registry**
(`Context.declareNeoForge` with a `NeoForgeRegistryAddition` for the key, whose
`entries` are the ones added here). The key only exists on a client whose mod
creates the registry, so the host sends it only when a declaration vouches for it;
an unvouched registry is left out (and one sent without the key being declared
would be refused with "unknown keys").

```dart
ExtraRegistries.declareSyncedRegistry('my_plugin:processing_type');
final id = ExtraRegistries.addSyncedEntry('my_plugin:processing_type', 'my_plugin:washing');
ExtraRegistries.syncedEntryId('my_plugin:processing_type', 'my_plugin:washing');
```

Not available: plugin biome tags, and anvil or enchanting table support for
plugin enchantments ([enchantments-and-advancements.md](enchantments-and-advancements.md)).

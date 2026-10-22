import 'dart:typed_data';

import 'bindings.g.dart' as generated;
import 'bindings.g.dart' show MobEffectCategory, ModifierOperation;
import 'host_result.dart';

/// A sound event to add to `minecraft:sound_event`.
final class SoundSpec {
  /// `namespace:path`; the `minecraft` namespace is reserved.
  final String key;

  /// The distance the sound is heard at, `null` for the usual range of its volume.
  final double? fixedRange;

  const SoundSpec(this.key, {this.fixedRange});
}

/// How the options of a plugin particle are encoded (`options-format` in
/// `extra-registries.wit`).
enum ParticleOptions {
  /// No options.
  none('none'),

  /// The bytes are written as given, in the format of the mod's particle codec.
  bytes('bytes'),

  /// An ARGB `s32`.
  color('color'),

  /// A block state id as a var int.
  blockState('block-state');

  const ParticleOptions(this.wireName);
  final String wireName;
}

/// A particle type to add to `minecraft:particle_type`.
final class ParticleSpec {
  final String key;

  /// Whether the particle ignores the particle limit of the client.
  final bool overrideLimiter;
  final ParticleOptions options;

  const ParticleSpec(this.key, {this.overrideLimiter = false, this.options = ParticleOptions.none});
}

/// An attribute modifier a mob effect applies, scaled by the amplifier.
final class MobEffectAttribute {
  /// The attribute, for example `minecraft:movement_speed`.
  final String attribute;

  /// The modifier id, `namespace:path`.
  final String id;
  final double amount;
  final ModifierOperation operation;

  const MobEffectAttribute({
    required this.attribute,
    required this.id,
    required this.amount,
    this.operation = ModifierOperation.add,
  });
}

/// A mob effect to add to `minecraft:mob_effect`. The translation key is
/// `effect.<namespace>.<path>`. Tick, applied and removed hooks are not
/// available.
final class MobEffectSpec {
  final String key;
  final MobEffectCategory category;

  /// The particle colour, RGB.
  final int color;
  final List<MobEffectAttribute> modifiers;

  const MobEffectSpec(
    this.key, {
    this.category = MobEffectCategory.neutral,
    this.color = 0xFFFFFF,
    this.modifiers = const [],
  });
}

/// A map decoration type to add to `minecraft:map_decoration_type`.
final class MapDecorationSpec {
  final String key;

  /// The texture asset name, a resource location path in the `map/decorations`
  /// atlas.
  final String assetName;
  final bool showOnItemFrame;

  /// The colour of the decoration on the map item, -1 for none.
  final int mapColor;
  final bool explorationMapElement;
  final bool trackCount;

  const MapDecorationSpec(
    this.key, {
    required this.assetName,
    this.showOnItemFrame = false,
    this.mapColor = -1,
    this.explorationMapElement = false,
    this.trackCount = false,
  });
}

/// Sound events, particle types, mob effects, map decoration types, datapack
/// registries and plugin owned registries (`extra-registries.wit`).
///
/// All of them are append only and close when the server accepts connections.
/// The n-th entry registered gets the id `vanilla count + n` in registries that
/// clients synchronise; other clients do not know the entries.
///
/// The registries a NeoForge client synchronises — `minecraft:sound_event`,
/// `minecraft:particle_type`, `minecraft:mob_effect`,
/// `minecraft:map_decoration_type` and the registry a mod owns
/// (`mymod:thing`, `declareSyncedRegistry`) — are sent only to a client whose
/// server **declares** them: name the registry in `Context.declareNeoForge`
/// (`NeoForgeRegistryAddition`), the same as for a block or an item. Declaring a
/// mod is not enough: an entry no declaration vouches for keeps the registry out
/// of the snapshot for everybody (the host's ids are positions, so a host-numbered
/// registry is sent whole or not at all). A plugin that registers a sound but
/// names nothing keeps it server-side.
///
/// Needs [Permissions.registryExtra]. Failures throw a [HostException].
///
/// ```dart
/// ExtraRegistries.registerSound(const SoundSpec('my_plugin:whirr'));
/// ExtraRegistries.registerMobEffect(const MobEffectSpec('my_plugin:slime', color: 0x55FF55));
/// ```
abstract final class ExtraRegistries {
  /// Registers a sound event and returns its id. Play it by key with
  /// `World.playCustomSound` or `Player.playCustomSound`.
  static int registerSound(SoundSpec sound) => unwrapHost(
    generated.extraRegistries.registerSound(
      definition: generated.SoundDefinition(key: sound.key, fixedRange: sound.fixedRange),
    ),
    'Registering the sound ${sound.key}',
  );

  /// The id of the sound event [key], vanilla or plugin.
  static int? soundId(String key) => generated.extraRegistries.getSoundId(key: key);

  /// Registers a particle type and returns its id. Spawn it with
  /// `World.spawnPluginParticleAt` ([WorldPluginParticles]); only
  /// NeoForge clients see it.
  static int registerParticle(ParticleSpec particle) => unwrapHost(
    generated.extraRegistries.registerParticle(
      definition: generated.ParticleDefinition(
        key: particle.key,
        overrideLimiter: particle.overrideLimiter,
        optionsFormat: particle.options.wireName,
      ),
    ),
    'Registering the particle ${particle.key}',
  );

  /// The id of the particle type [key], vanilla or plugin.
  static int? particleId(String key) => generated.extraRegistries.getParticleId(key: key);

  /// Registers a mob effect and returns its id.
  static int registerMobEffect(MobEffectSpec effect) => unwrapHost(
    generated.extraRegistries.registerMobEffect(
      definition: generated.MobEffectDefinition(
        key: effect.key,
        category: effect.category,
        color: effect.color,
        modifiers: [
          for (final m in effect.modifiers)
            generated.MobEffectModifier(
              attribute: m.attribute,
              id: m.id,
              amount: m.amount,
              operation: m.operation,
            ),
        ],
      ),
    ),
    'Registering the mob effect ${effect.key}',
  );

  /// The id of the mob effect [key], vanilla or plugin.
  static int? mobEffectId(String key) => generated.extraRegistries.getMobEffectId(key: key);

  /// Registers a map decoration type and returns its id.
  static int registerMapDecoration(MapDecorationSpec decoration) => unwrapHost(
    generated.extraRegistries.registerMapDecorationType(
      definition: generated.MapDecorationDefinition(
        key: decoration.key,
        assetName: decoration.assetName,
        showOnItemFrame: decoration.showOnItemFrame,
        mapColor: decoration.mapColor,
        explorationMapElement: decoration.explorationMapElement,
        trackCount: decoration.trackCount,
      ),
    ),
    'Registering the map decoration ${decoration.key}',
  );

  /// The id of the map decoration type [key], vanilla or plugin.
  static int? mapDecorationId(String key) =>
      generated.extraRegistries.getMapDecorationId(key: key);

  /// Declares a datapack registry, for example `minecraft:enchantment` to add
  /// entries to a vanilla one or `mymod:thing` for the registry of a mod.
  /// [kind] is a free label. Declaring it again with the same kind is fine.
  static void declareDatapackRegistry(String key, {String kind = 'plugin'}) => unwrapHost(
    generated.extraRegistries.registerDatapackRegistry(key: key, kind: kind),
    'Declaring the datapack registry $key',
  );

  /// Adds the entry [id] to the declared datapack registry [registry]. [nbt] is
  /// the entry as network NBT (a nameless compound), `null` for an entry whose
  /// data the client has. The same entry again is fine, another content is an
  /// error. NeoForge clients get it with the registry data.
  static void addDatapackEntry(String registry, String id, [List<int>? nbt]) => unwrapHost(
    generated.extraRegistries.addDatapackEntry(registry: registry, id: id, nbt: nbt),
    'Adding $id to the datapack registry $registry',
  );

  /// Declares a registry the plugin owns (`create:fan_processing_type` style)
  /// that is synced to NeoForge clients with all its entries in id order —
  /// **once the declaration names it** (`Context.declareNeoForge`,
  /// `NeoForgeRegistryAddition`, `entries` the ones [addSyncedEntry] added): the
  /// key only exists on a client whose mod creates it, so the host sends the
  /// registry only when a declaration vouches for it, and an unvouched one is
  /// refused by the client with "unknown keys".
  static void declareSyncedRegistry(String key) => unwrapHost(
    generated.extraRegistries.registerSyncedRegistry(key: key),
    'Declaring the synced registry $key',
  );

  /// Adds [entry] to the plugin owned registry [registry] and returns its id
  /// (its index).
  static int addSyncedEntry(String registry, String entry) => unwrapHost(
    generated.extraRegistries.addSyncedRegistryEntry(registry: registry, entry: entry),
    'Adding $entry to the synced registry $registry',
  );

  /// The id of [entry] in the plugin owned registry [registry].
  static int? syncedEntryId(String registry, String entry) =>
      generated.extraRegistries.getSyncedRegistryEntryId(registry: registry, entry: entry);
}

/// Spawning plugin particles in a [World].
extension WorldPluginParticles on generated.World {
  /// Spawns the particle [key] (see [ExtraRegistries.registerParticle]) for the
  /// NeoForge players of the world. [options] are the encoded options, see
  /// [ParticleOptions]. Throws a [HostException] on failure.
  void spawnPluginParticleAt(
    String key,
    (double, double, double) pos, {
    (double, double, double) delta = (0, 0, 0),
    double speed = 0,
    int count = 1,
    List<int> options = const [],
  }) => unwrapHost(
    spawnPluginParticle(
      key: key,
      pos: pos,
      delta: delta,
      speed: speed,
      count: count,
      options: options,
    ),
    'Spawning the particle $key',
  );
}

/// Encodes the options of a particle with the `color` or `block-state` format.
abstract final class ParticleOptionBytes {
  /// An ARGB colour as the 4 bytes the `color` format expects.
  static List<int> color(int argb) =>
      (ByteData(4)..setInt32(0, argb)).buffer.asUint8List().toList();

  /// A block state id as a var int, for the `block-state` format.
  static List<int> blockState(int stateId) {
    final out = <int>[];
    var v = stateId;
    while (v >= 0x80) {
      out.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return out;
  }
}

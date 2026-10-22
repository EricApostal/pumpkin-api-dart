// Everything a module registers, collected declaratively in `register()` and
// applied to the host by `registry_apply.dart` in a fixed order. Nothing here
// talks to the host. Order of calls = order of ids (see ARCHITECTURE.md).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import 'block_entity.dart';
import 'blocks.dart';
import 'ordered_registry.dart';
import 'payload.dart';

/// The registries whose order determines host ids; use with [CreateRegistry.useOrder].
enum RegistryKind {
  items,
  blocks,
  blockEntityTypes,
  menus,
  dataComponents,
  fluids,
  entityTypes,
  damageTypes,
  sounds,
  particles,
  mobEffects,
  recipeTypes,
}

/// Which tag registry a tag belongs to.
enum TagKind { block, item, fluid, entityType }

/// A data component type to register.
final class ComponentSpec {
  final String key;
  final ComponentCodec codec;
  final bool persistent;

  const ComponentSpec(this.key, this.codec, {required this.persistent});
}

/// A plugin-defined synced registry (`create:fan_processing_type`).
final class SyncedRegistrySpec {
  final String key;
  final List<String> entries;

  const SyncedRegistrySpec(this.key, this.entries);
}

/// A datapack registry entry for the NeoForge declaration.
final class DatapackEntrySpec {
  final String registry;
  final String id;
  final List<int>? data;

  const DatapackEntrySpec(this.registry, this.id, [this.data]);
}

/// A command to register once the registries are applied.
final class CommandSpec {
  final String name;
  final void Function(CommandBuilder c) build;
  final String description;
  final List<String> aliases;
  final Object? permission;

  const CommandSpec(this.name, this.build, this.description, this.aliases, this.permission);
}

/// A server-side declaration of the content of the mod.
final class CreateRegistry {
  final OrderedRegistry<ItemRegistration> items = OrderedRegistry('items');
  final OrderedRegistry<CreateBlock> blocks = OrderedRegistry('blocks');
  final OrderedRegistry<BlockEntityTypeSpec> blockEntityTypes = OrderedRegistry('blockEntityTypes');
  final OrderedRegistry<bool> menus = OrderedRegistry('menus');
  final OrderedRegistry<ComponentSpec> dataComponents = OrderedRegistry('dataComponents');
  final OrderedRegistry<FluidSpec> fluids = OrderedRegistry('fluids');
  final OrderedRegistry<EntityTypeSpec> entityTypes = OrderedRegistry('entityTypes');
  final OrderedRegistry<DamageTypeSpec> damageTypes = OrderedRegistry('damageTypes');
  final OrderedRegistry<SoundSpec> sounds = OrderedRegistry('sounds');
  final OrderedRegistry<ParticleSpec> particles = OrderedRegistry('particles');
  final OrderedRegistry<MobEffectSpec> mobEffects = OrderedRegistry('mobEffects');
  final OrderedRegistry<bool> recipeTypes = OrderedRegistry('recipeTypes');
  final OrderedRegistry<SyncedRegistrySpec> syncedRegistries = OrderedRegistry('syncedRegistries');

  /// The map decorations to register (`ExtraRegistries.registerMapDecoration`), in
  /// the order of the ids the client numbers them.
  final List<MapDecorationSpec> mapDecorations = [];

  /// The entity data serializers to register (`EntityRegistries.registerDataSerializer`),
  /// in the order of the ids the client numbers them.
  final List<String> entityDataSerializers = [];

  /// Tags by kind; entries of the same tag from several modules merge.
  final Map<TagKind, OrderedRegistry<List<String>>> tags = {
    for (final k in TagKind.values) k: OrderedRegistry('tags.${k.name}'),
  };

  final List<DatapackEntrySpec> datapackEntries = [];
  final List<String> datapackRegistries = [];
  final List<NeoForgeConfigFile> neoForgeConfigFiles = [];
  final List<NeoForgeDataMap> dataMaps = [];
  final List<Object> enchantments = [];
  final List<AdvancementSpec> advancements = [];
  final Map<String, String> advancementJson = {};
  final List<String> criterionTriggers = [];
  final List<CommandSpec> commands = [];

  /// The payload channels (client and server bound).
  final PayloadRegistry<Player> payloads = PayloadRegistry<Player>();

  OrderedRegistry<Object?> _of(RegistryKind kind) => switch (kind) {
    RegistryKind.items => items,
    RegistryKind.blocks => blocks,
    RegistryKind.blockEntityTypes => blockEntityTypes,
    RegistryKind.menus => menus,
    RegistryKind.dataComponents => dataComponents,
    RegistryKind.fluids => fluids,
    RegistryKind.entityTypes => entityTypes,
    RegistryKind.damageTypes => damageTypes,
    RegistryKind.sounds => sounds,
    RegistryKind.particles => particles,
    RegistryKind.mobEffects => mobEffects,
    RegistryKind.recipeTypes => recipeTypes,
  } as OrderedRegistry<Object?>;

  /// Installs a canonical id order for [kind] (for example the key list of the
  /// content manifest): listed keys first, in this order.
  void useOrder(RegistryKind kind, List<String> keys) => _of(kind).useOrder(keys);

  /// The ids order of [kind] (after canonical ordering).
  List<String> orderOf(RegistryKind kind) => _of(kind).keys;

  /// How the canonical order of [kind] differs from what was registered.
  OrderReport reportOf(RegistryKind kind) => _of(kind).report;

  // -- Registrations ---------------------------------------------------------------

  void item(ItemRegistration item) => items.add(item.key, item);

  /// Registers the block and (unless `hasItem: false`) its block item.
  void block(CreateBlock block) {
    final itemKey = block.itemKey;
    if (itemKey != null) item(ItemRegistration(key: itemKey, maxStackSize: block.itemMaxStackSize));
    blocks.add(block.key, block);
  }

  void blockEntityType(BlockEntityTypeSpec spec) => blockEntityTypes.add(spec.key, spec);

  void menu(String key) => menus.add(key, true);

  void dataComponent(String key, {required ComponentCodec codec, bool persistent = true}) =>
      dataComponents.add(key, ComponentSpec(key, codec, persistent: persistent));

  void fluid(FluidSpec spec) => fluids.add(spec.key, spec);

  void entityType(EntityTypeSpec spec) => entityTypes.add(spec.key, spec);

  void damageType(DamageTypeSpec spec) => damageTypes.add(spec.key, spec);

  void sound(SoundSpec spec) => sounds.add(spec.key, spec);

  void particle(ParticleSpec spec) => particles.add(spec.key, spec);

  void mobEffect(MobEffectSpec spec) => mobEffects.add(spec.key, spec);

  /// A recipe type (`create:pressing`). With [synced] it is also declared to
  /// `neoforge:recipe_content`.
  void recipeType(String key, {bool synced = true}) => recipeTypes.add(key, synced);

  /// A `create:*` registry the host does not know (`create:fan_processing_type`),
  /// numbered by the host through `ExtraRegistries` and synced to NeoForge clients.
  void syncedRegistry(String key, List<String> entries) =>
      syncedRegistries.add(key, SyncedRegistrySpec(key, entries));

  /// A map decoration (`minecraft:map_decoration_type`).
  void mapDecoration(MapDecorationSpec decoration) => mapDecorations.add(decoration);

  /// An entity data serializer (`neoforge:entity_data_serializers`).
  void entityDataSerializer(String key) => entityDataSerializers.add(key);

  void datapackRegistry(String key) => datapackRegistries.add(key);

  void datapackEntry(String registry, String id, [List<int>? networkNbt]) =>
      datapackEntries.add(DatapackEntrySpec(registry, id, networkNbt));

  void neoForgeConfigFile(String name, [List<int> content = const []]) =>
      neoForgeConfigFiles.add(NeoForgeConfigFile(name, content));

  void dataMap(NeoForgeDataMap map) => dataMaps.add(map);

  /// An `EnchantmentBuilder` or `CustomEnchantment`.
  void enchantment(Object enchantment) => enchantments.add(enchantment);

  void advancement(AdvancementSpec spec) => advancements.add(spec);

  void advancementJsonText(String id, String json) => advancementJson[id] = json;

  void criterionTrigger(String key) => criterionTriggers.add(key);

  /// Adds [entries] (keys or `#tag`s) to the tag [tag] of [kind].
  void tag(TagKind kind, String tag, List<String> entries) =>
      tags[kind]!.putIfAbsent(tag, () => <String>[]).addAll(entries);

  /// A command registered with `Context.command`.
  void command(
    String name,
    void Function(CommandBuilder c) build, {
    String description = '',
    List<String> aliases = const [],
    Object? permission,
  }) => commands.add(CommandSpec(name, build, description, aliases, permission));

  /// A client-to-server channel `create:<path>`.
  ServerboundChannel<T, Player> serverbound<T>(
    String path,
    PayloadCodec<T> codec,
    FutureOr<void> Function(Player player, T value) handler, {
    String version = '1',
    bool optional = false,
  }) => payloads.serverbound<T>(path, codec, handler, version: version, optional: optional);

  /// A server-to-client channel `create:<path>`; call `.send(player, value)`.
  ClientboundChannel<T, Player> clientbound<T>(
    String path,
    PayloadCodec<T> codec, {
    String version = '1',
    bool optional = false,
  }) => payloads.clientbound<T>(path, codec, version: version, optional: optional);

  /// Declares a channel the declaration carries without a codec or a handler
  /// here: another package owns the payload (`mymod:assemble`).
  ///
  /// [id] is a full resource location; the play phase is the only one Create
  /// declares.
  void declareChannel(
    String id, {
    String version = '1',
    required bool serverbound,
    bool optional = false,
  }) => payloads.declare(DeclaredPayload(id, version, serverbound: serverbound, optional: optional));

  /// [declareChannel] for a channel table of another package (`CreateAddon`).
  void declareChannels(Iterable<DeclaredPayload> channels) => payloads.declareAll(channels);
}

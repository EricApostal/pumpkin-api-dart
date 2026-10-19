// `CreateRegistries` and `CreateBuiltInRegistries` (pure): the keys of the registries Create adds
// on top of vanilla, and their manifest entries. Java registers these with NeoForge; this port
// declares them in the content manifest and numbers them through the plugin's synced registries
// (`CreateRegistry.syncedRegistry`), so this file is the lookup other modules use.
//
// The ids are the `ResourceKey` ids of `com.simibubi.create.api.registry.CreateRegistries`.
import '../../manifest/manifest.dart';

/// `CreateRegistries`: the ids of the registries Create adds.
abstract final class CreateRegistries {
  /// `ARM_INTERACTION_POINT_TYPE`.
  static const String armInteractionPointType =
      'create:arm_interaction_point_type';

  /// `FAN_PROCESSING_TYPE`.
  static const String fanProcessingType = 'create:fan_processing_type';

  /// `ITEM_ATTRIBUTE_TYPE`.
  static const String itemAttributeType = 'create:item_attribute_type';

  /// `DISPLAY_SOURCE`.
  static const String displaySource = 'create:display_source';

  /// `DISPLAY_TARGET`.
  static const String displayTarget = 'create:display_target';

  /// `MOUNTED_ITEM_STORAGE_TYPE`.
  static const String mountedItemStorageType =
      'create:mounted_item_storage_type';

  /// `MOUNTED_FLUID_STORAGE_TYPE`.
  static const String mountedFluidStorageType =
      'create:mounted_fluid_storage_type';

  /// `CONTRAPTION_TYPE`.
  static const String contraptionType = 'create:contraption_type';

  /// `PACKAGE_PORT_TARGET_TYPE`.
  static const String packagePortTargetType = 'create:package_port_target_type';

  /// `POTATO_PROJECTILE_TYPE`: a datapack registry, so it has no built-in static registry.
  static const String potatoProjectileType = 'create:potato_projectile/type';

  /// `POTATO_PROJECTILE_RENDER_MODE`.
  static const String potatoProjectileRenderMode =
      'create:potato_projectile/render_mode';

  /// `POTATO_PROJECTILE_ENTITY_HIT_ACTION`.
  static const String potatoProjectileEntityHitAction =
      'create:potato_projectile/entity_hit_action';

  /// `POTATO_PROJECTILE_BLOCK_HIT_ACTION`.
  static const String potatoProjectileBlockHitAction =
      'create:potato_projectile/block_hit_action';

  /// Every key, in the declaration order of Java.
  static const List<String> all = [
    armInteractionPointType,
    fanProcessingType,
    itemAttributeType,
    displaySource,
    displayTarget,
    mountedItemStorageType,
    mountedFluidStorageType,
    contraptionType,
    packagePortTargetType,
    potatoProjectileType,
    potatoProjectileRenderMode,
    potatoProjectileEntityHitAction,
    potatoProjectileBlockHitAction,
  ];
}

/// `CreateBuiltInRegistries`: the entries of the registries, from the content manifest.
abstract final class CreateBuiltInRegistries {
  /// Registry id to its entry ids, in registration order. Datapack registries
  /// (`potato_projectile/type`) are listed too; [isSynced] tells them apart.
  static final Map<String, List<String>> entries = {
    for (final r in kCustomRegistries)
      'create:${r.key}': [for (final e in r.entries) 'create:${e.key}'],
  };

  /// Registry id to whether NeoForge clients receive it.
  static final Map<String, bool> synced = {
    for (final r in kCustomRegistries) 'create:${r.key}': r.syncedToClient,
  };

  /// The manifest definition of a registry, `null` when the id is unknown.
  static CustomRegistryDef? definitionOf(String registryKey) {
    for (final r in kCustomRegistries) {
      if ('create:${r.key}' == registryKey) return r;
    }
    return null;
  }

  /// The entry ids of [registryKey], empty when it is unknown.
  static List<String> entriesOf(String registryKey) =>
      entries[registryKey] ?? const [];

  /// Whether [registryKey] is synced to NeoForge clients.
  static bool isSynced(String registryKey) => synced[registryKey] ?? false;

  /// Whether [entryKey] is an entry of [registryKey].
  static bool contains(String registryKey, String entryKey) =>
      entriesOf(registryKey).contains(entryKey);
}

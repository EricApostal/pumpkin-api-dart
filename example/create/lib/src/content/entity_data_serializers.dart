// The ids of the entity data serializers Create registers (`neoforge:entity_data_serializers`).
//
// `EntityRegistries.registerDataSerializer` numbers them `256 + registration index`
// (`CommonHooks.VANILLA_SERIALIZER_LIMIT`), and the client's own Create registers them in the same
// order (`kEntityDataSerializers`, the manifest's Java order), so the id is wire compatibility:
// `create:carriage_data` is 256 and `create:optional_uuid` 257. A plugin entity that pushes a
// `SynchedEntityData` entry puts the id of the serializer in front of the value, and a Java client
// resolves it through the vanilla map (below 256) or through the synced registry (above).
//
// Filled by `applyRegistry` (`core/registry_apply.dart`) while the server loads: the
// serializers come from `CreateRegistry.entityDataSerializers`, recorded by the
// modules in `register()` (`content_module.dart`, `trains/entity/entity_registration.dart`).
abstract final class EntityDataSerializerIds {
  static final Map<String, int> _byKey = {};

  /// Remembers the id [id] the host gave [key].
  static void record(String key, int id) => _byKey[key] = id;

  /// The id of [key], `null` while the serializers have not been registered.
  static int? of(String key) => _byKey[key];
}
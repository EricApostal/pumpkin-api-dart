// Registration of the train entity for the trains module: the `carriage_contraption` entity type
// from the manifest. The entity itself and the carriage contraption belong to the contraptions
// module; it implements `CarriageEntityFactory` and `CarriageContraptionAssembly` (see
// `api/trains.dart`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/module.dart';
import '../../core/registry.dart';
import '../../manifest/manifest.dart';
import 'carriage_sync_data.dart' show CarriageSyncDataSerializer;

/// `create:carriage_contraption`.
const String carriageContraptionEntity = 'create:carriage_contraption';

/// `create:carriage_data`, the entity data serializer the carriage wheel sync uses.
///
/// It is recorded in phase 1 (`registerEntity`) and registered by `applyRegistry`
/// (`create:carriage_data` is one of the host's `neoforge:entity_data_serializers`,
/// which the declaration has to name: `contentRegistries`), so [loadEntity] only
/// reads the id back.
const String carriageSyncDataSerializer = 'create:carriage_data';

/// Phase 1: the entity type and the carriage data serializer.
void registerEntity(CreateRegistry registry) {
  final d = kEntityTypes.firstWhere((e) => e.key == 'carriage_contraption');
  registry.entityType(
    EntityTypeSpec(
      key: 'create:${d.key}',
      width: d.width,
      height: d.height,
      eyeHeight: d.eyeHeight,
      fireImmune: d.fireImmune,
      trackingRange: d.trackingRange,
      updateInterval: d.updateInterval.clamp(1, 1000),
      trackDeltas: d.sendVelocity,
      summonable: d.summonable,
      spawnDataChannel: d.complexSpawnData
          ? 'neoforge:advanced_add_entity'
          : null,
    ),
  );
}

/// Phase 2: the id `applyRegistry` gave the `create:carriage_data` entity data serializer,
/// which the carriage wheel sync needs to put its value in an entity metadata entry.
///
/// [carriageSyncDataSerializer] is in the manifest's `kEntityDataSerializers`, which the
/// content module records (`content_module.dart`); it is not recorded here again, because
/// the host numbers the registry in registration order and a second call would be one more
/// entry in it.
void loadEntity(CreateContext ctx) {
  CarriageSyncDataSerializer.serializerId = ctx.ids.extra(carriageSyncDataSerializer);
}

/// Phase 3: nothing.
void serverEntityLoaded(CreateRuntime runtime) {}

/// Plugin unload: nothing.
void unloadEntity() {}

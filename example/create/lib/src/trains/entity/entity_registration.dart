// Registration of the train entity for the trains module: the `carriage_contraption` entity type
// from the manifest. The entity itself and the carriage contraption belong to the contraptions
// module; it implements `CarriageEntityFactory` and `CarriageContraptionAssembly` (see
// `api/trains.dart`).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/module.dart';
import '../../core/registry.dart';
import '../../manifest/manifest.dart';

/// `create:carriage_contraption`.
const String carriageContraptionEntity = 'create:carriage_contraption';

/// Phase 1: the entity type.
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

/// Phase 2: nothing (the contraptions module installs the entity factory).
void loadEntity(CreateContext ctx) {}

/// Phase 3: nothing.
void serverEntityLoaded(CreateRuntime runtime) {}

/// Plugin unload: nothing.
void unloadEntity() {}

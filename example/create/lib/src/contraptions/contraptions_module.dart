// The `contraptions` module: the contraption structure and entity host, and the wiring of the
// actuator content (bearings, pistons, pulleys, gantries, elevators, minecart contraptions,
// chassis, super glue, mounted contraptions, the wrench) and the actor content (movement
// behaviours, seats, portable storage interfaces, contraption controls).
//
// See `docs/ARCHITECTURE.md` for the module contract.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/trains.dart' show CarriageContraptionAssembly;
import '../common/common.dart' show Direction;
import '../core/module.dart';
import '../core/registry.dart';
import '../common/host_bridge.dart';
import '../trains/entity/carriage.dart' show Carriage;
import '../trains/entity/carriage_entity_host.dart' show CarriageEntities;
import '../trains/entity/train_level.dart' show TrainSettings;
import '../infrastructure/config/create_configs.dart';
import '../manifest/manifest.dart';
import '../api/observable.dart' show RedstoneObservables;
import '../api/payloads.dart' show PayloadBus;
import 'actors_registration.dart';
import 'actuators_registration.dart';
import 'blocks/actuator_contract.dart';
import 'blocks/actuator_runtime.dart';
import 'core/contraption_type.dart';
import 'core/structure_info.dart';
import 'entity/carriage_contraption_host.dart';
import 'entity/contraption_collider.dart';
import 'entity/contraption_entity.dart';
import 'entity/controlled_contraption_entity.dart';
import 'gantry/gantry_contraption_entity.dart';
import 'pulley/pulley_observable_probe.dart';
import 'entity/contraption_handler.dart';
import 'entity/contraption_packets.dart';
import 'entity/translating_contraption.dart';
import 'entity/host_contraption_entities.dart';
import 'storage/host_mounted_storage.dart';
import 'storage/mounted_storage.dart';
import 'storage/storage_manager.dart';
import 'storage/train_cargo_manager.dart';

/// The contraption entity types the base module registers.
const List<String> _contraptionEntityTypes = [
  'contraption',
  'stationary_contraption',
  'gantry_contraption',
];

/// The registered keys of every entity type that carries a contraption, including the train
/// carriage type of the trains module: all of them have to be ticked by the plugin.
const List<String> _contraptionEntityKeys = [
  'create:contraption',
  'create:stationary_contraption',
  'create:gantry_contraption',
  carriageContraptionEntityKey,
];

final class ContraptionsModule extends CreateModule {
  ContraptionHost? _host;
  MountedStorageHost? _storageHost;

  @override
  String get name => 'contraptions';

  @override
  void register(CreateRegistry registry) {
    // Core entity types, with the sizes of the content manifest.
    for (final key in _contraptionEntityTypes) {
      final def = kEntityTypes.firstWhere((e) => e.key == key);
      registry.entityType(
        EntityTypeSpec(
          key: 'create:${def.key}',
          width: def.width,
          height: def.height,
          eyeHeight: def.eyeHeight,
          fireImmune: def.fireImmune,
          trackingRange: def.trackingRange,
          updateInterval: def.updateInterval,
          trackDeltas: def.sendVelocity,
          summonable: def.summonable,
          // `IEntityWithComplexSpawn`: the client rebuilds the contraption from the spawn data
          // carried in `neoforge:advanced_add_entity`. Without this the client receives the
          // entity but no contraption, so nothing is rendered.
          spawnDataChannel: def.complexSpawnData
              ? 'neoforge:advanced_add_entity'
              : null,
        ),
      );
    }

    // A saved carriage contraption is read back as the train's kind.
    ContraptionTypes.register(
      carriageContraptionTypeId,
      () => HostCarriageContraption(Direction.north),
    );

    registerActuatorContent(registry);
    registerActorContent(registry);
  }

  @override
  void onLoad(CreateContext ctx) {
    final configs = ctx.services.find<CreateConfigs>();
    final ContraptionSettings settings = configs == null
        ? DefaultContraptionSettings()
        : ConfigsContraptionSettings(configs);

    final host = ContraptionHost(
      worlds: ctx.worlds,
      blockEntities: ctx.blockEntities,
      settings: settings,
      log: ctx.log,
    );
    _host = host;

    final bus = ctx.services.find<PayloadBus>();
    ContraptionHost.bus = bus;
    ctx.services.provide<ContraptionHost>(host);

    // The actuators create and spawn their entities through these factories.
    ActuatorHosts.entityFactory = HostContraptionEntityFactory(host);
    ActuatorHosts.levelFactory = host.levelOf;
    ActuatorHosts.glue = HostGlueEntityHost(host);
    ActuatorHosts.payloadBus = bus;

    ContraptionCollision.collideBlocks = ContraptionCollider.collideBlocks;
    ContraptionCollision.isCollidingWithWorld =
        (level, contraption, anchor, direction) =>
            contraption is TranslatingContraption &&
            ContraptionCollider.isCollidingWithWorld(
              contraption,
              anchor,
              direction,
            );

    // Bearings, clockwork bearings and pulleys cannot be moved while they run.
    ContraptionHostHooks.isActuatorRunning = (worldId, pos) {
      final be = ctx.blockEntities.at(worldId, pos.toBlockPos());
      if (be == null) return false;
      try {
        return (be as dynamic).isRunning as bool;
      } on Object {
        return false;
      }
    };

    ContraptionPackets.install(ctx, host);

    // `Create.java`: `AllMountedStorageTypes.register()` — without this every
    // `decodeItem`/`itemTypeOf` falls through to the fallback and no chest, barrel, depot,
    // vault, toolbox or tank ever mounts on a contraption.
    MountedStorages.installDefaults();

    // The menu of a mounted storage (Java `MountedItemStorage.handleInteraction`).
    final storageHost = MountedStorageHost(host, ctx);
    _storageHost = storageHost;
    storageHost.install();
    ContraptionEntityHooks.openStorage = storageHost.openStorage;

    // `MountedStorageSyncPacket.handle`: applies the storages the server sent to the client's
    // contraption (`MountedStorageManager.handleSync`). A server never receives this payload.
    bus?.onClientbound('create:mounted_storage_sync', (player, fields) {
      final id = fields['contraptionId'];
      if (id is! int) return;
      final entity = host.entityByIdAnyWorld(id);
      final contraption = entity?.contraption;
      if (contraption == null) return;
      contraption.storage.handleSync(StorageSync.fromWire(fields), contraption);
    });

    ctx.listen(Events.worldTick, (server, e) async {
      await host.tick(e.targetWorld.getId());
    });

    // `AbstractContraptionEntity.tick()` is the entity's own tick: the host only fires
    // `Events.entityTick` for a plugin type that opted in (`entity_tick_interval` is 0 otherwise,
    // `crates/pumpkin-core/src/world/mod.rs:1708-1734`). Without this every contraption exists,
    // is sent to the client and then never moves: no actor ticks, no passenger placement.
    ctx.listen(Events.entityTick, (server, e) async {
      if (!_contraptionEntityKeys.contains(e.entityType)) return;
      await host.onEntityTick(e.entityId);
    });
    for (final key in _contraptionEntityKeys) {
      try {
        ctx.host.tickPluginEntities(key, interval: 1);
      } on Object catch (error) {
        ctx.log.warn('contraptions of $key are not ticked: $error');
      }
    }
    ctx.listen(Events.worldUnload, (server, e) {
      if (e.cancelled) return;
      host.forgetWorld(e.targetWorld.getId());
    });

    // The trains module creates the entities of its carriages through this factory, and a fresh
    // carriage starts with the cargo the train takes over after assembly (`TrainCargoManager`).
    CarriageEntities.factory = HostCarriageEntityFactory(host);
    Carriage.storageFactory = TrainCargoManager.new;
    ctx.services.provide<CarriageContraptionAssembly>(
      HostCarriageContraptionAssembly(host),
    );

    // The station assembles carriages through `CarriageContraptionAssembly`, which is not one of
    // the contraption kinds above; the spawn needs the right entity type.
    ContraptionHostHooks.entityTypeOf = (entity) => switch (entity) {
      HostCarriageContraptionEntity() => carriageContraptionEntityKey,
      ControlledContraptionEntity() => 'create:stationary_contraption',
      GantryContraptionEntity() => 'create:gantry_contraption',
      _ => 'create:contraption',
    };

    // `ContraptionCollider` treats a carriage entity as a train carriage: it runs over entities
    // and hurts them (`create:run_over`) when the config allows it.
    ContraptionColliderHooks.isTrainCarriage =
        (entity) => entity is HostCarriageContraptionEntity;
    ContraptionColliderHooks.trainsCauseDamage =
        () => TrainSettings.current.trainsCauseDamage;
    ContraptionColliderHooks.damageRunOver =
        (entity, damage) => entity.damageRunOver(damage);

    loadActuatorContent(ctx);
    loadActorContent(ctx);
  }

  @override
  void onServerLoaded(CreateRuntime runtime) {
    serverActuatorContentLoaded(runtime);
    serverActorContentLoaded(runtime);
    // The threshold switch reads a pulley's rope offset (`ThresholdSwitchObservable`).
    runtime.services
        .find<RedstoneObservables>()
        ?.register(const PulleyObservableProbe());
  }

  @override
  void onUnload() {
    unloadActuatorContent();
    unloadActorContent();
    _storageHost?.clear();
    _storageHost = null;
    _host?.clear();
    _host = null;
    ActuatorHosts.reset();
    ContraptionHandler.clear();
    ContraptionEntityHooks.openStorage = null;
    ContraptionEntityHooks.leashedMob = null;
    ContraptionColliderHooks.isTrainCarriage = null;
    ContraptionColliderHooks.trainsCauseDamage = null;
    ContraptionColliderHooks.damageRunOver = null;
    ContraptionCollision.collideBlocks = null;
    ContraptionCollision.isCollidingWithWorld = null;
    ContraptionHostHooks.isActuatorRunning = null;
    ContraptionHostHooks.disassembleWindmillBearing = null;
    ContraptionHostHooks.notifyChainConveyor = null;
    ContraptionHostHooks.sitPassenger = null;
    ContraptionHostHooks.entityTypeOf = null;
    ContraptionHostHooks.spawned = null;
    CarriageEntities.factory = null;
    Carriage.storageFactory = null;
  }
}

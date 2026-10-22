// What the actuator content (bearings, pistons, pulleys, gantries, elevators, mounted contraptions)
// needs from the host. The contraption structure and the entity logic are pure (`core/`, `entity/`);
// creating the host entity of a contraption and reading a world as a [ContraptionLevel] are the
// plugin-side parts, installed by the contraptions host adapter (the same split the trains module
// uses with `CarriageEntities.factory`).
//
// Without the factory an actuator keeps its state and logs once: a server whose contraptions host
// is not loaded cannot move anything, but nothing crashes.
import '../../api/payloads.dart' show PayloadBus;
import '../../common/bounds.dart';
import '../../common/direction.dart';
import '../../common/pos.dart';
import '../../common/vec_helper.dart';
import '../core/contraption.dart';
import '../core/level.dart';
import '../core/structure_info.dart';
import 'actuator_runtime.dart';
import '../entity/contraption_entity.dart';
import '../entity/controlled_contraption_entity.dart';

/// Creates and spawns the contraption entities of the actuators.
abstract interface class ContraptionEntityFactory {
  /// `ControlledContraptionEntity.create(world, controller, contraption)`: the entity is not in
  /// the world yet.
  ///
  /// [entityKey] is the entity type of a `ControlledContraptionEntity` *subclass* the controller
  /// builds — `aeronautics:propeller_bearing_contraption` of a propeller bearing,
  /// `offroad:borehead_contraption_entity` of a borehead (Java's block entities construct their own
  /// subclass, so a client that only ever sees `create:stationary_contraption` loses the subclass'
  /// transforms). `null` builds the plain entity. The kind must be registered
  /// (`ContraptionHostHooks.registerControlledEntity`).
  ControlledContraptionEntity createControlled(
    String worldId,
    Pos controllerPos,
    Contraption contraption, {
    String? entityKey,
  });

  /// `OrientedContraptionEntity.create(world, contraption, facing)` for stabilised bearing
  /// sub-contraptions. The returned entity is the core's oriented entity.
  AbstractContraptionEntity createOriented(
    String worldId,
    Contraption contraption,
    Direction facing,
  );

  /// `GantryContraptionEntity.create(world, contraption, movementAxis)`.
  AbstractContraptionEntity createGantry(
    String worldId,
    Contraption contraption,
    Direction movementAxis,
  );

  /// `level.addFreshEntity(entity)`.
  void spawn(String worldId, AbstractContraptionEntity entity);

  /// The entity with [id] in [worldId], `null` when it is not loaded or not a contraption entity.
  AbstractContraptionEntity? entityById(String worldId, int id);
}

/// Builds the [ContraptionLevel] of a world (the plugin's view of the world for contraptions).
typedef ContraptionLevelFactory = ContraptionLevel Function(String worldId);

/// The super glue entities of a world (`SuperGlueEntity`).
abstract interface class GlueEntityHost {
  /// `new SuperGlueEntity(world, box)` followed by `addFreshEntity`.
  void spawn(String worldId, Aabb box);

  /// `entity.discard()`.
  void discard(String worldId, int entityId);

  /// `level.getEntitiesOfClass(SuperGlueEntity.class, box)` as the boxes of the glue entities.
  List<GlueRef> gluesIn(String worldId, Aabb box);

  /// The glue entity with [entityId], `null` when it is not loaded.
  GlueRef? glueById(String worldId, int entityId);
}

/// The install points of the contraptions host adapter.
abstract final class ActuatorHosts {
  static ContraptionEntityFactory? entityFactory;
  static ContraptionLevelFactory? levelFactory;
  static GlueEntityHost? glue;

  /// The payload bus (`create:glue_effect`, `create:gantry_update`, ...).
  static PayloadBus? payloadBus;

  static bool _warnedEntities = false;
  static bool _warnedLevel = false;

  /// The entity factory, `null` (and a one-time warning) when the host adapter is not installed.
  static ContraptionEntityFactory? get entities {
    final f = entityFactory;
    if (f == null && !_warnedEntities) {
      _warnedEntities = true;
      ActuatorRuntime.maybe?.log.warn(
        'No contraption entity factory: bearings, pistons, pulleys and elevators cannot move.',
      );
    }
    return f;
  }

  /// The level view of [worldId], `null` (and a one-time warning) without a level factory.
  static ContraptionLevel? levelOf(String worldId) {
    final f = levelFactory;
    if (f == null && !_warnedLevel) {
      _warnedLevel = true;
      ActuatorRuntime.maybe?.log.warn(
        'No contraption level factory: contraptions cannot be assembled.',
      );
    }
    return f?.call(worldId);
  }

  /// Clears the install points (tests, plugin unload).
  static void reset() {
    entityFactory = null;
    levelFactory = null;
    glue = null;
    payloadBus = null;
    _warnedEntities = false;
    _warnedLevel = false;
  }
}

/// `Vec3.atLowerCornerOf(direction.getUnitVec3i())`.
Vec3 directionVec(Direction d) => d.unitVec3;

/// `ContraptionCollider`, installed by the contraptions collider (pistons and gantries ask it
/// whether the moving structure hits the world).
abstract final class ContraptionCollision {
  /// `ContraptionCollider.collideBlocks(entity)`: true when the contraption hit something.
  static bool Function(AbstractContraptionEntity entity)? collideBlocks;

  /// `ContraptionCollider.isCollidingWithWorld(level, contraption, anchor, direction)`.
  static bool Function(
    ContraptionLevel level,
    Contraption contraption,
    Pos anchor,
    Direction direction,
  )?
  isCollidingWithWorld;
}

/// A block entity that remembers its last assembly failure (`IDisplayAssemblyExceptions`).
abstract interface class AssemblyExceptionHolding {
  AssemblyException? get lastAssemblyException;
}

/// An actuator whose contraption must not be moved while it runs: a mechanical or clockwork
/// bearing, a rope pulley (`BlockMovementChecksImpl.isMovementAllowedFallback`, which reads the
/// bearing's `isRunning()` and the pulley's `running`). The core's
/// [ContraptionLevel.isActuatorRunning] reads it through this interface instead of reflecting on
/// the field.
abstract interface class RunningActuator {
  /// `isRunning()`: whether the actuator is moving its contraption.
  bool get isRunning;
}

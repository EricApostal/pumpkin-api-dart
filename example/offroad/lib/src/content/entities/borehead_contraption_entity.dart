// `BoreheadContraptionEntity`: the contraption entity of a borehead bearing.
//
// The generic controlled contraption runs every actor of its structure, because any
// actor may be the point of the machine. A borehead is different: the only actor that
// may run is the rock cutting wheel (plus the contraption controls, which the player
// uses to stop and start the machine) — drills, saws, deployers and the rest must stay
// off. It also disassembles where it started: the structure is placed back with no
// rotation applied.
//
// The plain `ControlledContraptionEntity` the bearing used to spawn did neither: every
// actor kept ticking and the disassembly carried the rotation.
//
// Host: this file uses Create's contraption classes (and `pumpkin_api` through them).
// ignore_for_file: implementation_imports
import 'package:create/src/common/common.dart' show Axis, BlockMirror, BlockRotation, Pos, Vec3;
import 'package:create/src/contraptions/actors/contraption_controls/contraption_controls_behaviour.dart'
    show ContraptionControlsMovement;
import 'package:create/src/contraptions/core/movement.dart' show MovementBehaviour, MovementContext;
import 'package:create/src/contraptions/core/nbt_map.dart' show NbtMap;
import 'package:create/src/contraptions/core/structure_info.dart' show StructureBlockInfo;
import 'package:create/src/contraptions/core/structure_transform.dart' show StructureTransform;
import 'package:create/src/contraptions/entity/controlled_contraption_entity.dart'
    show ControlledContraptionEntity;

import '../../index/offroad_ids.dart';
import '../blocks/borehead_bearing/borehead_bearing_block.dart' show BoreheadBearingBlockEntity;
import '../blocks/rock_cutting_wheel/rock_cutting_wheel_block.dart' show RockCuttingWheelActor;
import '../contraptions/borehead_contraption.dart' show BoreheadBearingContraption;

/// `BoreheadContraptionEntity` (`content/entities/BoreheadContraptionEntity.java`).
///
/// Registered as `offroad:borehead_contraption_entity`
/// (`ContraptionHostHooks.registerControlledEntity`), which is also the entity type the
/// spawn sends to the client: the client has the Java class under that key, and it needs
/// it to animate the wheel from the bearing's speed.
final class BoreheadContraptionEntity extends ControlledContraptionEntity {
  BoreheadContraptionEntity(super.host);

  /// `shouldActorTrigger` (`:45-57`): only the rock cutting wheel and the contraption
  /// controls trigger; every other actor is switched off for good.
  @override
  bool shouldActorTrigger(
    MovementContext context,
    StructureBlockInfo blockInfo,
    MovementBehaviour actor,
    Vec3 actorPosition,
    Pos gridPosition,
  ) {
    if (!mayRun(actor)) {
      context.disabled = true;
      return false;
    }
    return super.shouldActorTrigger(context, blockInfo, actor, actorPosition, gridPosition);
  }

  /// `isActorActive` (`:59-67`): the same filter, for the actors that were already
  /// active when the contraption was assembled.
  @override
  bool isActorActive(MovementContext context, MovementBehaviour actor) {
    if (!mayRun(actor)) {
      context.disabled = true;
      return false;
    }
    return super.isActorActive(context, actor);
  }

  /// `getAngle(partialTicks)` (`:81-93`): the bearing's disassembly slowdown drives the
  /// angle while it runs, so the structure slows down with it instead of stopping dead.
  @override
  double getAngle(double partialTicks) {
    final controller = getController();
    if (controller is BoreheadBearingBlockEntity && controller.logic.isSlowingDown) {
      return controller.getInterpolatedAngle(partialTicks - 1);
    }
    return super.getAngle(partialTicks);
  }

  /// `makeStructureTransform` (`:113-124`): no rotation and no mirror — the structure is
  /// placed back exactly where it was assembled.
  @override
  StructureTransform makeStructureTransform() =>
      StructureTransform(super.makeStructureTransform().offset, Axis.x, BlockRotation.none, BlockMirror.none);

  /// `readAdditional` (`:99-111`): a world saved before the entity had its own type kept
  /// the contraption under the bearing kind; it is migrated to the borehead kind on the
  /// way in, so the structure is read back as a [BoreheadBearingContraption].
  @override
  void readAdditional(NbtMap compound, {bool spawnData = false}) {
    final contraption = compound.getCompound('Contraption');
    if (contraption.getString('Type') == 'create:bearing') {
      contraption.putString('Type', OffroadIds.boreheadContraption);
    }
    super.readAdditional(compound, spawnData: spawnData);
  }

  /// `getContraption()` (`:126-128`).
  BoreheadBearingContraption? get boreheadContraption {
    final contraption = this.contraption;
    return contraption is BoreheadBearingContraption ? contraption : null;
  }

  /// Whether [actor] may run on a borehead (`RockCuttingWheelActor` or
  /// `ContraptionControlsMovement`).
  static bool mayRun(MovementBehaviour actor) =>
      actor is RockCuttingWheelActor || actor is ContraptionControlsMovement;
}
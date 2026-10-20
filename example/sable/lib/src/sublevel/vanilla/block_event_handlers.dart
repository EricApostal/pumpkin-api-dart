// Vanilla behaviours around sub-levels that a plugin can drive from an event:
// dropped items leaving a ship, entities spawned inside one, fluids running off
// its edge, plants growing into it, and lightning striking its plot.
//
// Each handler takes a narrow [VanillaActionPort] (the plugin implements it
// over Pumpkin) and returns whether it acted, so the event handler that calls
// it stays a one-liner and the decision itself is testable.
//
// Java: dev.ryanhcode.sable.mixin.entity.entity_kicking.BlockMixin
// Java: dev.ryanhcode.sable.mixin.entity.entity_kicking.ServerLevelMixin
// Java: dev.ryanhcode.sable.mixin.fluids_on_sub_levels.FlowingFluidMixin
// Java: dev.ryanhcode.sable.mixin.prevent_overgrowth.VineBlockMixin
// Java: dev.ryanhcode.sable.mixin.stop_lightning.ServerLevelMixin
// Java: dev.ryanhcode.sable.mixin.entity.entity_sublevel_collision.AbstractMinecartMixin
//
// Pure: no host imports.
import '../math/bounding_box.dart';
import '../math/vector.dart';
import '../model/sub_level.dart';
import 'entity_tracking_rules.dart';

/// The world actions the vanilla-parity handlers perform.
///
/// Every method maps to something the host API already has (teleport, damage,
/// sound, block state); the port exists so the decisions stay pure and so the
/// plugin can log or veto a single action.
abstract interface class VanillaActionPort {
  /// The sub-level whose plot contains [worldPosition], if any.
  SubLevel? containingAt(Vector3d worldPosition);

  /// The sub-level whose plot contains the block at [worldBlock], if any.
  SubLevel? containingBlock((int, int, int) worldBlock);

  /// `EntitySubLevelUtil.kickEntity`: move the entity and its velocity out of
  /// the plot into world space.
  void kick(int entityId, SubLevel subLevel);

  /// Teleports an entity, in world space.
  void teleport(int entityId, Vector3d worldPosition);

  /// Removes an entity (`Entity#kill`).
  void destroy(int entityId);

  /// Plays a block sound at a world position.
  void playSound(Vector3d worldPosition, String sound, double volume, double pitch);

  /// `Level#getBlockState(pos).isAir()` for a plot block.
  bool isAir((int, int, int) worldBlock);
}

/// Dropped items.
abstract final class DropKicker {
  /// `BlockMixin#sable$popResourceFromFace`: a block broken inside a sub-level
  /// drops its item in world space, with the ship's motion.
  ///
  /// Returns true when the item was kicked (the plugin then leaves the vanilla
  /// drop alone, which the kick already moved).
  static bool onBlockDrop(
    VanillaActionPort port, {
    required int itemEntityId,
    required (int, int, int) blockPos,
  }) {
    final containing = port.containingBlock(blockPos);
    if (containing == null) return false;
    port.kick(itemEntityId, containing);
    return true;
  }
}

/// Entities added to the world.
abstract final class SpawnKicker {
  /// `ServerLevelMixin#sable$kickEntity`: an entity added inside a plot is moved
  /// out, unless its type is retained inside sub-levels.
  static bool onEntityAdded(
    VanillaActionPort port, {
    required int entityId,
    required String typeId,
    required Vector3d position,
    required Set<String> retainInSubLevel,
  }) {
    if (retainInSubLevel.contains(typeId)) return false;

    final containing = port.containingAt(position);
    if (containing == null) return false;

    port.kick(entityId, containing);
    return true;
  }
}

/// Entities that must not survive leaving their ship.
abstract final class PlotLeash {
  /// `EntityMixin#tick` / `AbstractMinecartMixin#postTick`: an entity of a type
  /// tagged `#sable:destroy_when_leaving_plot` dies once its bounding box no
  /// longer touches the plot it is in.
  ///
  /// [containing] is what the port resolved for the entity *before* this call;
  /// the plot's block bounds are what the entity must stay inside.
  static bool sweep(
    VanillaActionPort port, {
    required int entityId,
    required String typeId,
    required SubLevel? containing,
    required BoundingBox3dc entityBox,
    required Set<String> destroyWhenLeavingPlot,
    double inflate = 1.0,
  }) {
    final destroy = SubLevelEntityRules.shouldDestroyWhenLeavingPlot(
      containing: containing,
      entityBox: entityBox,
      destroyWhenLeavingPlot: destroyWhenLeavingPlot,
      typeId: typeId,
      inflate: inflate,
    );
    if (!destroy) return false;
    port.destroy(entityId);
    return true;
  }
}

/// Fluids.
abstract final class FluidSpreadGuard {
  /// `FlowingFluidMixin#sable$canSpreadTo`: a fluid may not spread off the edge
  /// of a sub-level. It *may* spread inside one as long as there is something
  /// below it inside the plot to flow along.
  ///
  /// [plotBounds] is the sub-level's block bounds (plot coordinates), [toPos]
  /// the block the fluid wants to enter.
  static bool allowSpread({
    required SubLevel? containing,
    required (int, int, int) toPos,
    required BoundingBox3ic plotBounds,
    required bool Function((int, int, int) worldBlock) isAir,
  }) {
    if (containing == null) return true;

    var mut = toPos;
    while (plotBounds.containsValues(mut.$1, mut.$2, mut.$3)) {
      mut = (mut.$1, mut.$2 - 1, mut.$3);
      if (mut.$2 < 0 || !isAir(mut)) return true;
    }

    // The column fell out of the plot without finding anything to flow along.
    return false;
  }

  /// The same check against [VanillaActionPort].
  static bool allowSpreadWithPort(
    VanillaActionPort port, {
    required SubLevel? containing,
    required (int, int, int) toPos,
  }) {
    if (containing == null) return true;
    return allowSpread(
      containing: containing,
      toPos: toPos,
      plotBounds: containing.getPlot().getBoundingBox(),
      isAir: port.isAir,
    );
  }
}

/// Plant growth.
abstract final class OvergrowthGuard {
  /// `VineBlockMixin`: vines do not spread inside a plot, so a ship does not
  /// grow a beard while it is parked.
  ///
  /// Cancels when the block the spread would write into is inside a sub-level.
  static bool shouldCancel({
    required SubLevel? containingTarget,
    required String newBlock,
  }) =>
      containingTarget != null && newBlock.startsWith('minecraft:vine');
}

/// Weather.
abstract final class LightningGuard {
  /// `stop_lightning/ServerLevelMixin`: no lightning strikes inside the plot
  /// yard. The Java check is on the *chunk*, so the whole plot chunk is
  /// protected, not just the sub-level's blocks.
  ///
  /// [inPlotYard] is `SubLevelContainer.inBounds(chunkX, chunkZ)` for the strike
  /// position's chunk.
  static bool shouldCancel({required bool inPlotYard, required SubLevel? containing}) =>
      inPlotYard || containing != null;
}

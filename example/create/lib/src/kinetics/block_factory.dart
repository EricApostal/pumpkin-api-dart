// Builds `CreateBlock`s from the generated manifest (so properties, value order,
// default state and stats are never retyped) and wires the shared behaviour of
// kinetic blocks: block entity state changes on placement and the player
// placement corrections.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/blocks.dart';
import 'block_data.dart';
import 'block_defs.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'placement.dart';
import 'runtime.dart';
import 'use_records.dart';

/// Creates the [CreateBlock] for `create:<path>` from the manifest.
///
/// The loot table is Create's generated one (`create:blocks/<path>`), the block
/// item is registered with the block when the manifest has one.
CreateBlock createBlockFromManifest(
  String path, {
  List<PlacementRule> placement = const [],
  BlockBehavior? behavior,
  String? blockEntityType,
  BlockShape? collisionShape,
  BlockShape? selectionShape,
  List<ShapeRule>? shapeRules,
  PistonBehavior? pistonBehavior,
  bool? canOcclude,
  bool useLootTable = true,
}) {
  final d = kineticBlockData(
    path,
    collisionShape: collisionShape,
    selectionShape: selectionShape,
    shapeRules: shapeRules,
    pistonBehavior: pistonBehavior,
    canOcclude: canOcclude,
    useLootTable: useLootTable,
  );
  return CreateBlock(
    key: d.key,
    properties: d.properties,
    defaultState: d.defaultState,
    booleansDefaultFalse: false,
    hardness: d.hardness,
    blastResistance: d.blastResistance,
    requiresCorrectTool: d.requiresCorrectTool,
    soundType: d.soundType,
    luminance: d.luminance,
    canOcclude: d.canOcclude,
    replaceable: d.replaceable,
    collisionShape: d.collisionShape,
    selectionShape: d.selectionShape,
    shapeRules: d.shapeRules,
    drops: d.drops,
    tags: d.tags,
    pistonBehavior: d.pistonBehavior,
    placement: placement,
    hasItem: d.itemKey != null,
    itemKey: d.itemKey,
    itemMaxStackSize: d.itemMaxStackSize,
    blockEntityType: blockEntityType,
    behavior: behavior,
  );
}

// -- Event helpers ---------------------------------------------------------------------

/// The state of [block] with the state index of an event.
KState stateOfEvent(CreateBlock block, int stateIndex) => KState(block.key, block.stateOf(stateIndex));

/// Writes [state] to the world (the state is resolved through the host).
Future<void> setKState(
  KineticsRuntime rt,
  World world,
  BlockPos pos,
  KState state, {
  Set<BlockFlagsFlag> flags = BlockUpdateFlags.normal,
}) async {
  final id = rt.states.idOf(state);
  if (id == null) {
    rt.log.warn('No block state for $state');
    return;
  }
  await world.setBlockState(pos: pos, state: id, updateFlags: flags);
}

/// What a kinetic block does besides what [KineticBlockEntity] does.
final class KineticBlockSpec {
  final CreateBlock block;

  /// The `IRotate` rules, `null` for blocks that are not kinetic.
  final KineticBlockDef? def;

  /// Corrects the state the host placed (the Java `getStateForPlacement`);
  /// `null` keeps the host's baseline state.
  final FutureOr<KState> Function(PlacementContext ctx, KState placed, UseRecord? use, World world)? placement;

  const KineticBlockSpec(this.block, {this.def, this.placement});
}

/// The kinetic part of `Block.onPlace` / `updateIndirectNeighbourShapes`
/// (`KineticBlock`): decides whether a block change at a position with a kinetic
/// block entity needs a new propagation.
void applyKineticBlockChange(
  KineticsRuntime rt,
  KineticBlockEntity be,
  KState? oldState,
  KState newState, {
  bool keepInfo = false,
}) {
  if (oldState == null) return;
  if (oldState.block != newState.block) {
    // A different block took the place of this one: nothing of the old block applies.
    be.resetForNewBlock();
    return;
  }
  be.preventSpeedUpdate = 0;
  final def = rt.blocks.defFor(newState);
  if (def != null && def.areStatesKineticallyEquivalent(oldState, newState)) {
    be.preventSpeedUpdate = 2;
  }
  if (keepInfo) be.preventSpeedUpdate = 2;
  if (be.preventSpeedUpdate > 0) return;
  // Remove previous information when the block changed in a way that matters.
  be.warnOfMovement();
  be.clearKineticInformation();
  be.updateSpeed = true;
}

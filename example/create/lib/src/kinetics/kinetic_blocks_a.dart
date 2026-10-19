// Block definitions, part one: shafts, cogwheels, encased variants, gearbox,
// clutch, gearshift, chain drives. (See `kinetic_blocks.dart` for the list.)
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/blocks.dart';
import 'behavior_builder.dart';
import 'block_entities.dart';
import 'block_defs.dart';
import 'block_factory.dart';
import 'chain_drive.dart';
import 'geometry.dart';
import 'kinetic_block_entity.dart';
import 'node.dart' show KineticBlockRegistry;
import 'placement.dart';
import 'placement_helper_host.dart';
import 'placement_helpers.dart';

/// The casing items that encase shafts and cogwheels, with the variant prefix.
const Map<String, String> casingItems = {
  'create:andesite_casing': 'andesite',
  'create:brass_casing': 'brass',
};

// -- Steam engine shaft rules (`PoweredShaftBlock`, `SteamEngineBlock`) ---------------------

/// `FaceAttachedHorizontalDirectionalBlock.getConnectedDirection`.
Dir steamEngineConnectedDirection(KState engine) => switch (engine['face']) {
  'ceiling' => Dir.down,
  'floor' => Dir.up,
  _ => engine.dirOf('facing') ?? Dir.north,
};

/// `SteamEngineBlock.getShaftPos`.
KPos steamEngineShaftPos(KState engine, KPos pos) => pos.relative(steamEngineConnectedDirection(engine), 2);

/// `SteamEngineBlock.isShaftValid`.
bool steamEngineShaftValid(KState engine, KState shaft) =>
    (shaft.isCreate('shaft') || shaft.isCreate('powered_shaft')) &&
    shaft.axisOf('axis') != steamEngineConnectedDirection(engine).axis;

/// `PoweredShaftBlock.stillValid`.
bool poweredShaftStillValid(KState state, KPos pos, KState Function(KPos) stateAt) {
  final axis = state.axisOf('axis');
  for (final d in Dir.values) {
    if (d.axis == axis) continue;
    final enginePos = pos.relative(d, 2);
    final engineState = stateAt(enginePos);
    if (!engineState.isCreate('steam_engine')) continue;
    if (steamEngineShaftPos(engineState, enginePos) != pos) continue;
    if (steamEngineShaftValid(engineState, state)) return true;
  }
  return false;
}

// -- Helpers -------------------------------------------------------------------------------

Future<String> _heldItem(CustomBlockUseEventData e) async {
  try {
    return await e.item.getRegistryKey();
  } catch (_) {
    return 'minecraft:air';
  }
}

/// `KineticBlockEntity.switchToBlockState` through the runtime.
Future<void> switchKinetic(HookCtx c, KState state) =>
    KineticOps.switchToBlockState(c.rt, c.worldId, c.pos, state);

/// `EncasableBlock.tryEncase` for shafts and cogwheels: [variants] maps the
/// casing item to the encased state.
Future<BlockUseResult?> tryEncase(
  HookCtx c,
  CustomBlockUseEventData e,
  KState Function(String variant) encased,
) async {
  final item = await _heldItem(e);
  final variant = casingItems[item];
  if (variant == null) return null;
  await switchKinetic(c, encased(variant));
  return BlockUseResult.success;
}

/// The result when a use was not handled.
BlockUseResult unhandled(CustomBlockUseEventData e) => e.withItem ? BlockUseResult.tryEmptyHand : BlockUseResult.pass;

/// The encased shaft for [variant] (`andesite` / `brass`) with [axis]
/// (`EncasedShaftBlock.handleEncasing`).
KState encasedShaftState(String variant, KAxis axis) => KState('create:${variant}_encased_shaft', {'axis': axis.name});

/// The encased cogwheel for [variant] with shafts towards neighbours that have one
/// (`EncasedCogwheelBlock.handleEncasing`).
KState encasedCogwheelState(
  KineticBlockRegistry blocks,
  KState Function(KPos) stateAt,
  KPos pos,
  String variant,
  bool large,
  KAxis axis,
) {
  var s = KState('create:$variant${large ? '_encased_large_cogwheel' : '_encased_cogwheel'}', {
    'axis': axis.name,
    'top_shaft': 'false',
    'bottom_shaft': 'false',
  });
  for (final d in Dir.inAxis(axis)) {
    final adjacent = stateAt(pos.relative(d));
    final def = blocks.defFor(adjacent);
    if (def == null) continue;
    if (!def.hasShaftTowards(adjacent, d.opposite)) continue;
    s = s.toggle(d.isPositive ? 'top_shaft' : 'bottom_shaft');
  }
  return s;
}

/// `ShaftBlock.PlacementHelper` / `PoweredShaftBlock.useItemOn`: a shaft, cogwheel or
/// large cogwheel used on a shaft extends the line.
Future<BlockUseResult?> shaftPlacementHelper(HookCtx c, CustomBlockUseEventData e) async {
  if (!e.withItem) return null;
  final item = await _heldItem(e);
  if (item != 'create:shaft' && item != 'create:cogwheel' && item != 'create:large_cogwheel') return null;
  final block = c.rt.kineticBlocks[item];
  if (block == null) return null;
  final w = helperWorldFor(c.rt, c.worldId, c.world);
  final hit = (c.pos.x + e.cursor.$1, c.pos.y + e.cursor.$2, c.pos.z + e.cursor.$3);
  final offset = shaftPoleOffset(
    w,
    c.kpos,
    c.state,
    hit,
    pickType: item == 'create:shaft'
        ? (s, at) => poweredShaftStillValid(s, at, c.level.stateAt) ? s.withBlock('create:powered_shaft') : s
        : null,
  );
  if (!offset.success) return null;
  final placed = await placeOffset(c.rt, c.world, c.worldId, offset, block, e.player, e.hand);
  return placed ? BlockUseResult.success : null;
}

// -- Shaft --------------------------------------------------------------------------------

KineticBlockSpec shaftSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'shaft',
    blockEntityType: 'create:simple_kinetic',
    placement: [PlacementRule.clickedAxis('axis'), PlacementRule.inWater('waterlogged')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      use: (c, e) async {
        if (e.sneaking) return unhandled(e);
        final axis = c.state.axisOf('axis') ?? KAxis.y;
        final encased = await tryEncase(c, e, (variant) => encasedShaftState(variant, axis));
        if (encased != null) return encased;

        // A metal girder on a horizontal shaft.
        if (e.withItem && axis != KAxis.y && await _heldItem(e) == 'create:metal_girder') {
          final girder = KState('create:metal_girder_encased_shaft', {
            'axis': axis == KAxis.z ? 'z' : 'x',
            'waterlogged': c.state['waterlogged'] ?? 'false',
            'bottom': 'false',
            'top': 'false',
          });
          if (c.rt.states.idOf(girder) != null) {
            await switchKinetic(c, girder);
            if (!e.player.isCreative) await _consumeHeld(e);
            return BlockUseResult.success;
          }
        }
        final helped = await shaftPlacementHelper(c, e);
        if (helped != null) return helped;
        return unhandled(e);
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    placement: (ctx, placed, use, world) {
      var s = placed.set('axis', rotatedPillarAxis(ctx).name);
      if (poweredShaftStillValid(s, ctx.pos, ctx.stateAt)) s = s.withBlock('create:powered_shaft');
      return s;
    },
  );
  return spec;
}

/// Takes one item from the held stack of the player that used a block.
Future<void> _consumeHeld(CustomBlockUseEventData e) async {
  final count = await e.item.getCount();
  final stack = e.player.getItemInHand(hand: e.hand);
  if (stack == null) return;
  if (count <= 1) {
    await e.player.setItemInHand(hand: e.hand, stack: null);
  } else {
    await stack.setCount(count: count - 1);
    await e.player.setItemInHand(hand: e.hand, stack: stack);
  }
}

// -- Cogwheels -------------------------------------------------------------------------------

KineticBlockSpec cogwheelSpec({required bool large}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  final key = large ? 'large_cogwheel' : 'cogwheel';
  block = createBlockFromManifest(
    key,
    blockEntityType: 'create:simple_kinetic',
    placement: [PlacementRule.clickedAxis('axis'), PlacementRule.inWater('waterlogged')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      canPlace: (c, e) async {
        final player = e.player;
        if (player == null) return true;
        final pc = await placementContextFor(c, player, e.face, e.pos);
        if (pc == null) return true;
        final axis = cogwheelAxis(pc, large: large);
        return isValidCogwheelPosition(large, pc.stateAt, c.rt.blocks, pc.pos, axis);
      },
      use: (c, e) async {
        if (e.sneaking) return unhandled(e);
        final axis = c.state.axisOf('axis') ?? KAxis.y;
        final encased = await tryEncase(
          c,
          e,
          (variant) => encasedCogwheelState(c.rt.blocks, c.level.stateAt, c.kpos, variant, large, axis),
        );
        return encased ?? unhandled(e);
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: AxisBlockDef(smallCog: !large, largeCog: large, dedicatedCog: true),
    placement: (ctx, placed, use, world) => placed.set('axis', cogwheelAxis(ctx, large: large).name),
  );
  return spec;
}

/// Builds a placement context for the placement of a block by [player] at [pos].
Future<PlacementContext?> placementContextFor(HookCtx c, Uuid player, BlockDirection? face, BlockPos pos) async {
  final p = c.server.getPlayerByUuid(id: player);
  if (p == null) return null;
  final record = c.rt.useRecords.matching(player.asString, pos);
  final clicked = record?.face ?? (face == null ? Dir.up : Dir.fromName(face.name) ?? Dir.up);
  return PlacementContext(
    pos: KPos(pos.x, pos.y, pos.z),
    clickedFace: clicked,
    nearestLooking: nearestLookingDirection(p.getYaw(), p.getPitch()),
    horizontal: horizontalDirection(p.getYaw()),
    sneaking: record?.sneaking ?? p.asEntity().isSneaking(),
    stateAt: c.level.stateAt,
    blocks: c.rt.blocks,
  );
}

// -- Encased shafts and cogwheels -----------------------------------------------------------------

KineticBlockSpec encasedShaftSpec(String variant) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    '${variant}_encased_shaft',
    blockEntityType: 'create:encased_shaft',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: buildKineticBehavior(() => block, specRef: () => spec),
  );
  spec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    placement: (ctx, placed, use, world) => placed.set('axis', encasedShaftAxis(ctx).name),
  );
  return spec;
}

KineticBlockSpec encasedCogwheelSpec(String variant, {required bool large}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    '${variant}_encased${large ? '_large' : ''}_cogwheel',
    blockEntityType: large ? 'create:encased_large_cogwheel' : 'create:encased_cogwheel',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      canPlace: (c, e) async {
        final player = e.player;
        if (player == null) return true;
        final pc = await placementContextFor(c, player, e.face, e.pos);
        if (pc == null) return true;
        return isValidCogwheelPosition(large, pc.stateAt, c.rt.blocks, pc.pos, encasedCogwheelAxis(pc));
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: EncasedCogDef(large: large),
    placement: (ctx, placed, use, world) => placed.set('axis', encasedCogwheelAxis(ctx).name),
  );
  return spec;
}

KineticBlockSpec gearboxSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'gearbox',
    blockEntityType: 'create:gearbox',
    behavior: buildKineticBehavior(() => block, specRef: () => spec),
  );
  spec = KineticBlockSpec(
    block,
    def: const GearboxDef(),
    // VerticalGearboxItem: the vertical gearbox turns horizontal next to shafts.
    placement: (ctx, placed, use, world) {
      if (use?.itemKey != 'create:vertical_gearbox') return placed.set('axis', 'y');
      KAxis? preferred;
      for (final side in Dir.horizontals) {
        final nPos = ctx.pos.relative(side);
        final nState = ctx.stateAt(nPos);
        final def = ctx.blocks.defFor(nState);
        if (def != null && def.hasShaftTowards(nState, side.opposite)) {
          if (preferred != null && preferred != side.axis) {
            preferred = null;
            break;
          } else {
            preferred = side.axis;
          }
        }
      }
      final axis = preferred == null ? ctx.horizontal.clockWise(KAxis.y).axis : (preferred == KAxis.x ? KAxis.z : KAxis.x);
      return placed.set('axis', axis.name);
    },
  );
  return spec;
}

// -- Gearshift and clutch -------------------------------------------------------------------------

KineticBlockSpec gearshiftSpec({required bool clutch}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  final key = clutch ? 'clutch' : 'gearshift';
  block = createBlockFromManifest(
    key,
    blockEntityType: 'create:$key',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      neighbor: (c, e) async {
        final be = c.be;
        if (be == null) return;
        final signal = await c.world.hasRedstoneNeighborSignal(c.pos);
        final state = c.level.stateAt(c.kpos);
        if (!state.isCreate(key)) return;
        final previouslyPowered = state.flag('powered');
        if (previouslyPowered == signal) return;
        if (clutch) {
          await c.setState(
            state.toggle('powered'),
            flags: const {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate},
          );
          _detachKinetics(c, reAttachNextTick: previouslyPowered);
        } else {
          _detachKinetics(c, reAttachNextTick: true);
          await c.setState(state.toggle('powered'), flags: const {BlockFlagsFlag.notifyListeners});
        }
      },
      scheduledTick: (c) {
        // GearshiftBlock.tick: attach again after the state change.
        c.be?.handleAdded();
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    placement: (ctx, placed, use, world) async {
      final axis = encasedShaftAxis(ctx);
      final powered = await world.hasRedstoneNeighborSignal(BlockPos(x: ctx.pos.x, y: ctx.pos.y, z: ctx.pos.z));
      return placed.setAll({'axis': axis.name, 'powered': '$powered'});
    },
  );
  return spec;
}

/// `GearshiftBlock.detachKinetics`.
void _detachKinetics(HookCtx c, {required bool reAttachNextTick}) {
  final be = c.be;
  if (be == null) return;
  be.detachKinetics();
  if (reAttachNextTick) {
    c.world.scheduleTick(c.pos, const Duration(milliseconds: 50), priority: TickPriority.extremelyHigh);
  }
}

// -- Chain drives ------------------------------------------------------------------------------------

KineticBlockSpec chainDriveSpec({required bool gearshift}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  final key = gearshift ? 'adjustable_chain_gearshift' : 'encased_chain_drive';
  block = createBlockFromManifest(
    key,
    blockEntityType: gearshift ? 'create:adjustable_chain_gearshift' : 'create:encased_shaft',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      updateShape: (c, e) {
        final neighbour = c.rt.states.decode(e.neighborStateId);
        final dir = Dir.fromName(e.direction.name)!;
        final updated = chainDriveUpdateShape(c.state, dir, neighbour, c.rt.blocks);
        if (updated == c.state) return null;
        return block.layout.indexOf({...block.definition.defaultState, ...updated.props});
      },
      neighbor: gearshift
          ? (c, e) async {
              final be = c.beOf<ChainGearshiftBlockEntity>();
              if (be != null) unawaited(be.neighbourChanged());
              final signal = await c.world.hasRedstoneNeighborSignal(c.pos);
              final state = c.level.stateAt(c.kpos);
              if (!state.isCreate(key)) return;
              if (state.flag('powered') != signal) {
                await c.setState(
                  state.toggle('powered'),
                  flags: const {BlockFlagsFlag.notifyListeners, BlockFlagsFlag.skipShapeUpdate},
                );
              }
            }
          : null,
      afterPlaced: gearshift
          ? (c, e) {
              final be = c.beOf<ChainGearshiftBlockEntity>();
              if (be != null) unawaited(be.neighbourChanged());
            }
          : null,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: gearshift ? const ChainGearshiftDef() : const AxisBlockDef(),
    placement: (ctx, placed, use, world) async {
      final placedAxis = ctx.nearestLooking.axis;
      final axis = ctx.sneaking ? placedAxis : (preferredAxis(ctx) ?? placedAxis);
      final base = placed.setAll({'axis': axis.name, 'part': 'none', 'axis_along_first': 'true'});
      var s = chainDriveSettle(base, ctx.pos, ctx.stateAt, ctx.blocks);
      if (gearshift) {
        final powered = await world.hasRedstoneNeighborSignal(BlockPos(x: ctx.pos.x, y: ctx.pos.y, z: ctx.pos.z));
        s = s.set('powered', '$powered');
      }
      return s;
    },
  );
  return spec;
}

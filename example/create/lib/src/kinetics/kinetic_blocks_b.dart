// Block definitions, part two: generators and the remaining kinetic blocks.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/blocks.dart';
import 'behavior_builder.dart';
import 'block_defs.dart';
import 'block_entities.dart';
import 'block_data.dart' show dyeColorNames;
import 'block_factory.dart';
import 'generators.dart';
import 'geometry.dart';
import 'kinetic_blocks_a.dart';
import 'placement_helper_host.dart';
import 'placement_helpers.dart';
import 'placement.dart';
import 'steam_engine.dart';
import 'water_wheel_logic.dart';

const List<String> dyeColors = dyeColorNames;

Future<String> _item(CustomBlockUseEventData e) async {
  try {
    return await e.item.getRegistryKey();
  } catch (_) {
    return 'minecraft:air';
  }
}

// -- Creative motor ---------------------------------------------------------------------

KineticBlockSpec creativeMotorSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'creative_motor',
    blockEntityType: 'create:motor',
    placement: [PlacementRule.clickedFace('facing')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const FacingBlockDef(hideStressImpact: true),
    placement: (ctx, placed, use, world) =>
        placed.set('facing', creativeMotorFacing(ctx).name),
  );
  return spec;
}

// -- Hand crank and valve handles ------------------------------------------------------------

KineticBlockSpec handCrankSpec() => _crankSpec('hand_crank');

KineticBlockSpec valveHandleSpec(String? color) => _crankSpec(
  color == null ? 'copper_valve_handle' : '${color}_valve_handle',
  valve: true,
  color: color,
);

KineticBlockSpec _crankSpec(String key, {bool valve = false, String? color}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    key,
    blockEntityType: valve ? 'create:valve_handle' : 'create:hand_crank',
    placement: [
      PlacementRule.clickedFace('facing'),
      PlacementRule.inWater('waterlogged'),
    ],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      updateShape: waterloggedUpdateShape,
      canPlace: (c, e) async {
        final player = e.player;
        if (player == null) return true;
        final pc = await placementContextFor(c, player, e.face, e.pos);
        if (pc == null) return true;
        // canSurvive: the block behind must have a collision shape.
        final facing = handCrankFacing(pc);
        final behind = pc.pos.relative(facing.opposite);
        final bs = c.world.getBlockState(
          pos: BlockPos(x: behind.x, y: behind.y, z: behind.z),
        );
        return bs.collisionShapes.isNotEmpty;
      },
      neighbor: (c, e) {
        // HandCrankBlock.neighborChanged: break when the supporting block is gone.
        final facing = c.state.dirOf('facing') ?? Dir.up;
        final behind = c.kpos.relative(facing.opposite);
        if (e.sourcePos.x != behind.x ||
            e.sourcePos.y != behind.y ||
            e.sourcePos.z != behind.z)
          return null;
        final bs = c.world.getBlockState(pos: e.sourcePos);
        if (bs.collisionShapes.isEmpty) c.level.destroyBlock(c.kpos);
      },
      use: (c, e) async {
        final player = e.player;
        if (player.isSpectator) return unhandled(e);
        final item = await _item(e);

        if (valve) {
          // ValveHandleBlock.onBlockActivated
          if (item == 'create:wrench' && e.sneaking) return unhandled(e);
          final held = _dyeColor(item);
          if (held != null && held != color) {
            final target = KState('create:${held}_valve_handle', {
              'facing': c.state['facing'] ?? 'north',
              'waterlogged': c.state['waterlogged'] ?? 'false',
            });
            await c.setState(target);
            return BlockUseResult.success;
          }
          final be = c.beOf<ValveHandleBlockEntity>();
          be?.activate(e.sneaking);
          return BlockUseResult.success;
        }

        final be = c.beOf<HandCrankBlockEntity>();
        be?.turn(e.sneaking);
        if (item != 'create:extendo_grip' && !player.isCreative) {
          final speed = (be?.rotationSpeed ?? 32).toDouble();
          player.setExhaustion(
            exhaustion:
                player.getExhaustion() +
                speed * c.rt.settings.crankHungerMultiplier,
          );
        }
        return BlockUseResult.success;
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const FacingBlockDef(shaftAtFront: false),
    placement: (ctx, placed, use, world) =>
        placed.set('facing', handCrankFacing(ctx).name),
  );
  return spec;
}

String? _dyeColor(String itemKey) {
  if (!itemKey.startsWith('minecraft:') || !itemKey.endsWith('_dye'))
    return null;
  final color = itemKey.substring(
    'minecraft:'.length,
    itemKey.length - '_dye'.length,
  );
  return dyeColors.contains(color) ? color : null;
}

// -- Water wheels ---------------------------------------------------------------------------------

final Set<String> _scheduledWheelTicks = {};

void _scheduleOnce(HookCtx c, KPos target) {
  final key = '${c.worldId}:${target.packed}';
  if (!_scheduledWheelTicks.add(key)) return;
  c.world.scheduleTick(
    BlockPos(x: target.x, y: target.y, z: target.z),
    const Duration(milliseconds: 50),
  );
}

KineticBlockSpec waterWheelSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'water_wheel',
    blockEntityType: 'create:water_wheel',
    placement: [PlacementRule.clickedFace('facing')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      canPlace: (c, e) async {
        final player = e.player;
        if (player == null) return true;
        final pc = await placementContextFor(c, player, e.face, e.pos);
        if (pc == null) return true;
        final facing = directionalFacing(pc);
        return waterWheelCanSurvive(
          pc.stateAt,
          pc.pos,
          KState('create:water_wheel', {'facing': facing.name}),
        );
      },
      use: (c, e) async {
        final item = await _item(e);
        final be = c.beOf<WaterWheelBlockEntity>();
        if (be != null && e.withItem && be.applyMaterialIfValid(item))
          return BlockUseResult.success;
        return unhandled(e);
      },
      neighbor: (c, e) => _scheduleOnce(c, c.kpos),
      afterPlaced: (c, e) => _scheduleOnce(c, c.kpos),
      scheduledTick: (c) {
        _scheduledWheelTicks.remove('${c.worldId}:${c.kpos.packed}');
        c.beOf<WaterWheelBlockEntity>()?.determineAndApplyFlowScore();
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const FacingAxisBlockDef(hideStressImpact: true),
    placement: (ctx, placed, use, world) =>
        placed.set('facing', directionalFacing(ctx).name),
  );
  return spec;
}

KineticBlockSpec largeWaterWheelSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'large_water_wheel',
    blockEntityType: 'create:large_water_wheel',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      canPlace: (c, e) async {
        final player = e.player;
        if (player == null) return true;
        final pc = await placementContextFor(c, player, e.face, e.pos);
        if (pc == null) return true;
        final axis = rotatedPillarAxis(pc);
        for (final p in largeWaterWheelFootprint(pc.pos, axis)) {
          final s = c.world.getBlockState(
            pos: BlockPos(x: p.x, y: p.y, z: p.z),
          );
          if (!s.replaceable) return false;
        }
        return true;
      },
      use: (c, e) async {
        final item = await _item(e);
        final be = c.beOf<WaterWheelBlockEntity>();
        if (be != null && e.withItem && be.applyMaterialIfValid(item))
          return BlockUseResult.success;
        return unhandled(e);
      },
      updateShape: (c, e) {
        final axis = c.state.axisOf('axis') ?? KAxis.y;
        if (Dir.fromName(e.direction.name) != axis.negative) return null;
        final isWheel = c.rt.states
            .decode(e.neighborStateId)
            .isCreate('large_water_wheel');
        if (isWheel == c.state.flag('extension')) return null;
        return block.layout.indexOf({
          ...block.definition.defaultState,
          ...c.state.set('extension', '$isWheel').props,
        });
      },
      afterPlaced: (c, e) => _scheduleOnce(c, c.kpos),
      scheduledTick: (c) async {
        _scheduledWheelTicks.remove('${c.worldId}:${c.kpos.packed}');
        final axis = c.state.axisOf('axis') ?? KAxis.y;
        final structureBlock = c.rt.states;
        for (final (p, facing) in largeWaterWheelStructure(c.kpos, axis)) {
          final bp = BlockPos(x: p.x, y: p.y, z: p.z);
          final occupied = c.level.stateAt(p);
          final required = KState('create:water_wheel_structure', {
            'facing': facing.name,
          });
          if (occupied == required) continue;
          final occ = c.world.getBlockState(pos: bp);
          if (!occ.replaceable && !occ.isAir) {
            await c.world.breakBlock(c.pos, drop: false);
            return;
          }
          final id = structureBlock.idOf(required);
          if (id != null)
            await c.world.setBlockState(
              pos: bp,
              state: id,
              updateFlags: BlockUpdateFlags.normal,
            );
        }
        c.beOf<WaterWheelBlockEntity>()?.determineAndApplyFlowScore();
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    placement: (ctx, placed, use, world) {
      final axis = rotatedPillarAxis(ctx);
      final negative = ctx
          .stateAt(ctx.pos.relative(axis.negative))
          .isCreate('large_water_wheel');
      return placed.setAll({'axis': axis.name, 'extension': '$negative'});
    },
  );
  return spec;
}

KineticBlockSpec waterWheelStructureSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  KPos masterOf(HookCtx c) =>
      waterWheelMaster(c.level.stateAt, c.kpos, c.state);
  block = createBlockFromManifest(
    'water_wheel_structure',
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      use: (c, e) async {
        if (!waterWheelStructureValid(
          c.level.stateAt,
          c.kpos,
          c.state,
          directlyAdjacent: false,
        ))
          return BlockUseResult.fail;
        final m = masterOf(c);
        final be = c.rt.store.at(c.worldId, BlockPos(x: m.x, y: m.y, z: m.z));
        if (be is! WaterWheelBlockEntity) return BlockUseResult.fail;
        if (e.withItem && be.applyMaterialIfValid(await _item(e)))
          return BlockUseResult.success;
        return unhandled(e);
      },
      scheduledTick: (c) async {
        _scheduledWheelTicks.remove('${c.worldId}:${c.kpos.packed}');
        if (!waterWheelStructureValid(
          c.level.stateAt,
          c.kpos,
          c.state,
          directlyAdjacent: false,
        )) {
          final air = c.rt.states.idOf(KState.air);
          if (air != null)
            await c.world.setBlockState(
              pos: c.pos,
              state: air,
              updateFlags: BlockUpdateFlags.normal,
            );
        }
      },
      updateShape: (c, e) {
        if (waterWheelStructureValid(
          c.level.stateAt,
          c.kpos,
          c.state,
          directlyAdjacent: false,
        )) {
          final m = masterOf(c);
          _scheduleOnce(c, m);
          return null;
        }
        _scheduleOnce(c, c.kpos);
        return null;
      },
      replaced: (c, e) async {
        // affectNeighborsAfterRemoval: the wheel goes with its structure.
        if (waterWheelStructureValid(
          c.level.stateAt,
          c.kpos,
          c.state,
          directlyAdjacent: false,
        )) {
          final m = masterOf(c);
          await c.world.breakBlock(
            BlockPos(x: m.x, y: m.y, z: m.z),
            drop: true,
          );
        }
      },
      willDestroy: (c, e) async {
        if (waterWheelStructureValid(
          c.level.stateAt,
          c.kpos,
          c.state,
          directlyAdjacent: false,
        )) {
          final m = masterOf(c);
          if (e.player.isCreative)
            await c.world.breakBlock(
              BlockPos(x: m.x, y: m.y, z: m.z),
              drop: false,
            );
        }
        return true;
      },
      cloneItem: (c, e) => ItemStacks.plain('create:large_water_wheel'),
    ),
  );
  spec = KineticBlockSpec(block);
  return spec;
}

// -- Flywheel, gauges, turntable, clocks, speed controller -----------------------------------------

KineticBlockSpec flywheelSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'flywheel',
    blockEntityType: 'create:flywheel',
    placement: [PlacementRule.clickedAxis('axis')],
    behavior: buildKineticBehavior(() => block, specRef: () => spec),
  );
  spec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    placement: (ctx, placed, use, world) =>
        placed.set('axis', rotatedPillarAxis(ctx).name),
  );
  return spec;
}

KineticBlockSpec gaugeSpec({required bool stress}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  final key = stress ? 'stressometer' : 'speedometer';
  block = createBlockFromManifest(
    key,
    blockEntityType: 'create:$key',
    placement: [PlacementRule.clickedFace('facing')],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      comparator: (c) => c.beOf<GaugeBlockEntity>()?.analogOutput ?? 0,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const DirectionalAxisBlockDef(),
    placement: (ctx, placed, use, world) {
      final g = gaugePlacement(ctx);
      return placed.setAll({
        'facing': g.facing.name,
        'axis_along_first': '${g.alongFirst}',
      });
    },
  );
  return spec;
}

KineticBlockSpec turntableSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'turntable',
    blockEntityType: 'create:turntable',
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      entityStep: (c, e) {
        // TurntableBlock.entityInside, the server side: players rotate on the client.
        if (e.entityType == 'minecraft:player') return;
        if (e.entityPos.$2 < c.pos.y + .5) return;
        final be = c.be;
        if (be == null) return;
        final speed = be.speed * 3 / 10;
        if (speed == 0) return;
        final entity = c.world.getEntityById(id: e.entityId);
        if (entity == null) return;
        try {
          if (!entity.isOnGround()) return;
          if (entity.getVelocity().$2 > 0) return;
          // Java also resets the head/body rotation and the no-action time; the
          // host only exposes yaw/pitch and the on-ground flag.
          if (entity.isLiving()) entity.setOnGround(onGround: false);
          entity.setRotation(
            yaw: entity.getYaw() - speed,
            pitch: entity.getPitch(),
          );
        } finally {
          entity.dispose();
        }
      },
    ),
  );
  spec = KineticBlockSpec(block, def: const TurntableDef());
  return spec;
}

KineticBlockSpec cuckooClockSpec({required bool mysterious}) {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    mysterious ? 'mysterious_cuckoo_clock' : 'cuckoo_clock',
    blockEntityType: 'create:cuckoo_clock',
    placement: [PlacementRule.horizontalFacing('facing', opposite: true)],
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const CuckooClockDef(),
    placement: (ctx, placed, use, world) =>
        placed.set('facing', cuckooClockFacing(ctx).name),
  );
  return spec;
}

KineticBlockSpec speedControllerSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'rotation_speed_controller',
    blockEntityType: 'create:rotation_speed_controller',
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      use: (c, e) async {
        // SpeedControllerBlock.useItemOn: a large cogwheel goes on top.
        if (!e.withItem || await _item(e) != 'create:large_cogwheel')
          return unhandled(e);
        final cogBlock = c.rt.kineticBlocks['create:large_cogwheel'];
        if (cogBlock == null) return unhandled(e);
        final offset = speedControllerCogOffset(
          helperWorldFor(c.rt, c.worldId, c.world),
          c.kpos,
          c.state,
        );
        if (!offset.success) return unhandled(e);
        final placed = await placeOffset(
          c.rt,
          c.world,
          c.worldId,
          offset,
          cogBlock,
          e.player,
          e.hand,
        );
        return placed ? BlockUseResult.success : unhandled(e);
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const AxisBlockDef(),
    placement: (ctx, placed, use, world) =>
        placed.set('axis', speedControllerAxis(ctx).name),
  );
  return spec;
}

// -- Sequenced gearshift ---------------------------------------------------------------------------------

KineticBlockSpec sequencedGearshiftSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'sequenced_gearshift',
    blockEntityType: 'create:sequenced_gearshift',
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      comparator: (c) => c.state.intValue('state'),
      neighbor: (c, e) => _scheduleOnce(c, c.kpos),
      scheduledTick: (c) async {
        _scheduledWheelTicks.remove('${c.worldId}:${c.kpos.packed}');
        final previouslyPowered = c.state.intValue('state') != 0;
        final isPowered = await c.world.hasRedstoneNeighborSignal(c.pos);
        await c.beOf<SequencedGearshiftBlockEntity>()?.onRedstoneUpdate(
          isPowered,
          previouslyPowered,
        );
      },
      use: (c, e) async {
        final item = await _item(e);
        if (item == 'create:wrench') return unhandled(e);
        final def = c.rt.blocks.defOf(item);
        if (def != null &&
            def.hasShaftTowards(c.state, Dir.fromName(e.face.name)!))
          return unhandled(e);
        return BlockUseResult.success;
      },
    ),
  );
  spec = KineticBlockSpec(
    block,
    def: const SequencedGearshiftDef(),
    placement: (ctx, placed, use, world) {
      final preferred = preferredAxis(ctx);
      final axis = (preferred != null && !ctx.sneaking)
          ? preferred
          : ctx.nearestLooking.axis;
      return placed.setAll({
        'vertical': '${axis.isVertical}',
        'axis': axis.isVertical ? ctx.horizontal.axis.name : axis.name,
      });
    },
  );
  return spec;
}

// -- Powered shaft and steam engine ------------------------------------------------------------------------------

KineticBlockSpec poweredShaftSpec() {
  late final CreateBlock block;
  late final KineticBlockSpec spec;
  block = createBlockFromManifest(
    'powered_shaft',
    blockEntityType: 'create:powered_shaft',
    behavior: buildKineticBehavior(
      () => block,
      specRef: () => spec,
      pathfindable: false,
      updateShape: waterloggedUpdateShape,
      use: (c, e) async {
        if (e.sneaking) return unhandled(e);
        return await shaftPlacementHelper(c, e) ?? unhandled(e);
      },
      scheduledTick: (c) async {
        if (!poweredShaftStillValid(c.state, c.kpos, c.level.stateAt)) {
          await c.setState(
            KState('create:shaft', {
              'axis': c.state['axis'] ?? 'y',
              'waterlogged': c.state['waterlogged'] ?? 'false',
            }),
          );
        }
      },
      cloneItem: (c, e) => ItemStacks.plain('create:shaft'),
    ),
  );
  spec = KineticBlockSpec(block, def: const AxisBlockDef());
  return spec;
}

KineticBlockSpec steamEngineSpec() => steamEngineBlockSpec();

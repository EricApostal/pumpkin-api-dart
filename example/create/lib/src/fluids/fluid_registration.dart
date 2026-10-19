// `EncasingRegistry` and `WrenchRegistry` hooks of the fluid blocks: copper casing turns a fluid
// or glass pipe into the encased pipe, and the wrench converts between the pipe variants and
// toggles a tank's windows. Registered from the module's `onServerLoaded`, because the decoration
// and equipment modules (which provide the registries) load after this one.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/block_state.dart';
import '../api/blocks.dart' show setBlockState, toDirection;
import '../api/wrenchable.dart';
import '../common/direction.dart';
import '../core/block_entity.dart';
import '../decoration/bracketed_behaviour.dart';
import '../decoration/encasing.dart';
import '../processing/common/stack.dart';
import '../processing/host/stack_host.dart';
import 'fluid_runtime.dart';
import 'fluid_tank.dart';
import 'fluid_transport_behaviour.dart';
import 'pipe_blocks.dart';
import 'pipe_node.dart';
import 'pipe_state_logic.dart';

/// The item that encases fluid pipes (`AllBlocks.COPPER_CASING`).
const String copperCasingKey = 'create:copper_casing';

const String _fluidPipeKey = 'create:fluid_pipe';
const String _glassPipeKey = 'create:glass_fluid_pipe';
const String _encasedPipeKey = 'create:encased_fluid_pipe';

/// `EncasingRegistry.addVariant` for the fluid and glass pipes.
void registerFluidEncasing(EncasingRegistry encasing) {
  encasing.addVariant(
    _fluidPipeKey,
    EncasedVariant(
      encasedKey: _encasedPipeKey,
      casingItemKey: copperCasingKey,
      handleEncasing: (c) => _encasePipe(c.world, c.pos, c.state, sixWay: true),
    ),
  );
  encasing.addVariant(
    _glassPipeKey,
    EncasedVariant(
      encasedKey: _encasedPipeKey,
      casingItemKey: copperCasingKey,
      handleEncasing: (c) =>
          _encasePipe(c.world, c.pos, c.state, sixWay: false),
    ),
  );
}

/// The wrench handlers of the fluid blocks.
void registerFluidWrench(WrenchRegistry wrench) {
  wrench.register(
    _fluidPipeKey,
    CallbackWrenchable(
      beforeWrenched: (c) async =>
          await _removeBracket(c) ? WrenchResult.success : null,
      onWrenchedOverride: (c) async => _fluidPipeToGlass(c),
    ),
  );
  wrench.register(
    _glassPipeKey,
    CallbackWrenchable(
      beforeWrenched: (c) async =>
          await _removeBracket(c) ? WrenchResult.success : null,
      onWrenchedOverride: (c) async => _glassToFluidPipe(c),
    ),
  );
  wrench.register(
    _encasedPipeKey,
    CallbackWrenchable(onWrenchedOverride: (c) async => _encasedToFluidPipe(c)),
  );
  for (final tank in const [
    'create:fluid_tank',
    'create:creative_fluid_tank',
  ]) {
    wrench.register(
      tank,
      CallbackWrenchable(
        onWrenchedOverride: (c) async {
          final be = _blockEntityAt(c);
          if (be is FluidTankBlockEntity) be.toggleWindows();
          return WrenchResult.success;
        },
      ),
    );
  }
  wrench.registerDefault(const [
    'create:smart_fluid_pipe',
    'create:spout',
    'create:item_drain',
  ]);
}

Future<void> _encasePipe(
  World world,
  BlockPos pos,
  BState state, {
  required bool sixWay,
}) async {
  final props = <String, String>{
    for (final d in Direction.values) d.serializedName: 'false',
  };
  if (sixWay) {
    for (final d in Direction.values) {
      props[d.serializedName] = state.flag(d.serializedName) ? 'true' : 'false';
    }
  } else {
    final axis = state.axisOf('axis') ?? Axis.y;
    for (final d in Direction.values) {
      props[d.serializedName] = d.axis == axis ? 'true' : 'false';
    }
  }
  await _switchPipe(world, pos, BState(_encasedPipeKey, props));
}

Future<WrenchResult> _fluidPipeToGlass(WrenchContext c) async {
  final state = BState(c.blockKey, c.properties);
  final axis = PipeBlocks.straightPipeAxis(state) ?? _closestAxis(c);
  if (toDirection(c.face).axis == axis) return WrenchResult.pass;
  final glass = BState(_glassPipeKey, {
    'axis': axis.name,
    'alt': 'false',
    'waterlogged': state['waterlogged'] ?? 'false',
  });
  await _switchPipe(c.world, c.pos, glass);
  return WrenchResult.success;
}

Future<WrenchResult> _glassToFluidPipe(WrenchContext c) async {
  final runtime = FluidsRuntime.instance;
  final worldId = runtime.worlds.touch(c.world);
  final level = runtime.levelOf(worldId);
  if (level == null) return WrenchResult.pass;
  final state = BState(c.blockKey, c.properties);
  final pipe = PipeStateLogic.toRegularPipe(
    level,
    (c.pos.x, c.pos.y, c.pos.z),
    state,
    _pipeDefault(),
  );
  await _switchPipe(
    c.world,
    c.pos,
    pipe.setValue('waterlogged', state['waterlogged'] ?? 'false'),
  );
  return WrenchResult.success;
}

Future<WrenchResult> _encasedToFluidPipe(WrenchContext c) async {
  final runtime = FluidsRuntime.instance;
  final worldId = runtime.worlds.touch(c.world);
  final level = runtime.levelOf(worldId);
  if (level == null) return WrenchResult.pass;
  final state = BState(c.blockKey, c.properties);
  var pipe = _pipeDefault();
  for (final d in Direction.values) {
    pipe = pipe.setFlag(d.serializedName, state.flag(d.serializedName));
  }
  // `EncasedPipeBlock.onWrenched`: re-evaluate the pipe from its first open side.
  var first = Direction.up;
  for (final d in Direction.values) {
    if (pipe.flag(d.serializedName)) {
      first = d;
      break;
    }
  }
  final updated = PipeStateLogic.updateBlockState(pipe, first, null, level, (
    c.pos.x,
    c.pos.y,
    c.pos.z,
  ));
  await _switchPipe(c.world, c.pos, updated);
  return WrenchResult.success;
}

/// `FluidPipeBlock.defaultBlockState()`.
BState _pipeDefault() => BState(_fluidPipeKey, {
  for (final d in Direction.values) d.serializedName: 'false',
  'waterlogged': 'false',
});

/// Changes the pipe block, keeping the flows across the block entity replacement
/// (`FluidTransportBehaviour.cacheFlows` / `loadFlows`).
Future<void> _switchPipe(World world, BlockPos pos, BState target) async {
  final runtime = FluidsRuntime.instance;
  final worldId = runtime.worlds.touch(world);
  final p = (pos.x, pos.y, pos.z);
  final old = runtime.store
      .at(worldId, pos)
      ?.getBehaviour<FluidTransportBehaviour>();
  PipeFlowTransfer.cacheFlows(worldId, p, old);
  await setBlockState(world, p, target);
  final next = runtime.store
      .at(worldId, pos)
      ?.getBehaviour<FluidTransportBehaviour>();
  PipeFlowTransfer.loadFlows(worldId, p, next);
}

/// `IWrenchableWithBracket.onWrenched`: a bracket comes off before the pipe changes.
Future<bool> _removeBracket(WrenchContext c) async {
  final be = _blockEntityAt(c);
  final bracket = be?.getBehaviour<BracketedBlockEntityBehaviour>();
  final removed = await bracket?.removeBracket();
  if (removed == null) return false;
  final stack = await HostStacks.write(PStack(removed.key, 1));
  if (stack != null) {
    await c.world.dropItem((c.pos.x + .5, c.pos.y + .5, c.pos.z + .5), stack);
  }
  return true;
}

CreateBlockEntity? _blockEntityAt(WrenchContext c) {
  final runtime = FluidsRuntime.instance;
  return runtime.store.at(runtime.worlds.touch(c.world), c.pos);
}

/// `FluidPipeBlock.onWrenched`: the axis of the face whose centre is closest to the click,
/// ignoring the clicked face's own axis.
Axis _closestAxis(WrenchContext c) {
  final cursor = c.cursor;
  var closest = double.infinity;
  var axis = Axis.y;
  for (final d in Direction.values) {
    if (d.axis == toDirection(c.face).axis) continue;
    final dx = .5 + d.stepX * .5 - cursor.$1;
    final dy = .5 + d.stepY * .5 - cursor.$2;
    final dz = .5 + d.stepZ * .5 - cursor.$3;
    final distance = dx * dx + dy * dy + dz * dz;
    if (distance < closest) {
      closest = distance;
      axis = d.axis;
    }
  }
  return axis;
}

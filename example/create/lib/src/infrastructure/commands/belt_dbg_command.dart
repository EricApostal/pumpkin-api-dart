// TEMPORARY (belt animation investigation): build a powered belt run and put an item on it.
//
// DELETE BEFORE REPORTING: this file, its `registerBeltDbgCommands` call and its import in
// `infrastructure_module.dart`.
//
// Why it exists: the host's own commands cannot build a belt run.
//  * `setblock`/`fill` cannot express a plugin block state: `part` and `slope` are not vanilla
//    property names, so the host drops them
//    (`pumpkin-command/src/argument_types/block.rs:126-131`) and every belt ends up at its default
//    state, `part=start`.
//  * a run of `part=start` blocks survives only if the whole run exists before the first tick
//    (`BeltBlock.initBelt` walks back from each segment; a segment whose forward walk stops after
//    one block is "broken" and destroyed). `fill` writes the run in one go but creates **no**
//    plugin block entities at all (run-beltanim3: four `data get block 2 -60 0` on a filled belt
//    answered "The target block is not a block entity" while the block probes at the same position
//    were true), and a command line is one tick per command, so `setblock` puts the head down
//    alone and the run is destroyed as it is built.
//  * so the run has to be built by the plugin, through `BeltConnectorItem.createBelts`
//    (`belt_connector_item.dart:107`), which writes the whole run as one batch, creates the block
//    entities and runs `initBelt`.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../common/host_bridge.dart';
import '../../conveyance/belt/belt_block_entity.dart';
import '../../conveyance/belt/belt_connector_item.dart';
import '../../conveyance/items/item_data.dart';
import '../../conveyance/runtime.dart';
import '../../core/registry.dart';
import 'create_commands.dart' show InfraCommandState;

/// Registers `/create beltdbg` (see the file comment).
void registerBeltDbgCommands(CreateRegistry registry, InfraCommandState st) {
  registry.command(
    'beltdbg',
    (c) => c
      ..describe('DEBUG: belt animation probe (temporary)')
      ..sub(
        'build',
        description: 'Builds a belt run along +x between two shafts, with a creative motor',
        build: (b) => b.arg(
          'from',
          ArgumentTypes.blockPos,
          build: (f) => f.arg(
            'to',
            ArgumentTypes.blockPos,
            runs: (ctx) => _build(ctx, st),
          ),
        ),
      )
      ..sub(
        'item',
        description: 'Puts one item on the belt segment at a position',
        build: (i) => i.arg(
          'pos',
          ArgumentTypes.blockPos,
          runs: (ctx) => _item(ctx, st),
        ),
      ),
    description: 'DEBUG: belt animation probe (temporary)',
  );
}

World _world(CommandContext ctx) =>
    ctx.sender.world() ?? (throw CommandException('This command needs a world'));

ConveyanceRuntime _runtime() =>
    ConveyanceRuntime.loaded ? ConveyanceRuntime.i : (throw CommandException('Create is not loaded'));

/// `create beltdbg build <from> <to>`: a shaft with a block entity at each end (the run is along
/// +x, so their axis is z), a creative motor outside the first shaft, then
/// `BeltConnectorItem.createBelts`, which writes the run in one batch and runs `initBelt`.
Future<void> _build(CommandContext ctx, InfraCommandState st) async {
  final world = _world(ctx);
  final worldId = st.worlds.touch(world);
  final rt = _runtime();
  final from = ctx.blockPos('from').toPos();
  final to = ctx.blockPos('to').toPos();
  for (final p in [from, to]) {
    await setBlockState(world, p, const BState('create:shaft', {'axis': 'z'}));
    rt.store.createAt(world, p.toBlockPos(), 'create:simple_kinetic');
  }
  // `CreativeMotorBlock.hasShaftTowards(face) == (face == FACING)`: the shaft is on the side
  // FACING points to, and `creativeMotorFacing` sets FACING to the side its neighbour is on, so a
  // motor at z - 1 next to the shaft at z faces south (+z).
  final motor = (from.$1, from.$2, from.$3 - 1);
  await setBlockState(world, motor, const BState('create:creative_motor', {'facing': 'south'}));
  rt.store.createAt(world, motor.toBlockPos(), 'create:motor');
  await createBelts(rt, world, worldId, from, to);
  st.log.info('BELTDBG build $from -> $to motor=$motor');
}

/// `create beltdbg item <pos>`: one stack into the segment handler at [pos].
Future<void> _item(CommandContext ctx, InfraCommandState st) async {
  final world = _world(ctx);
  final worldId = st.worlds.touch(world);
  final pos = ctx.blockPos('pos').toPos();
  final segment = _runtime().typedAt<BeltBlockEntity>(worldId, pos);
  if (segment == null) throw CommandException('No belt block entity at $pos');
  final handler = segment.itemHandler;
  if (handler == null) throw CommandException('The belt at $pos has no item handler');
  final left = await handler.insert(0, ItemValue('minecraft:stone', 8));
  st.log.info('BELTDBG item at $pos: left=${left.key}x${left.count}');
}
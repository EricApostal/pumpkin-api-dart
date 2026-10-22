// TEMPORARY probe (delete after the investigation): does a sail item still
// follow Create's placement rules and the sail row-placement helper?
//
// Run with a server that has create.wasm loaded, then `/sailprobe run`.
import 'package:pumpkin_api/pumpkin_api.dart';

void main() => runPlugin(SailProbe());

final class SailProbe extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'sail_probe',
    version: '0.0.1',
    permissions: [Permissions.fakePlayers],
  );

  @override
  void onLoad(Context context) {
    final command = Command.create(names: ['sailprobe'], description: 'sail placement probe');
    final action = CommandNode.argument(name: 'action', type: ArgumentTypes.word)
      ..execute((sender, server, args) async {
        final key = args.string('action');
        try {
          for (final line in await probe(server, key)) {
            logger.info('SP $key $line');
          }
        } on Object catch (e) {
          logger.info('SP $key FAIL: $e');
        }
        return 1;
      });
    command.then(node: action);
    context.registerCommand(command: command, permission: 'sail_probe:sailprobe');
  }
}

Future<List<String>> probe(Server server, String action) async {
  final world =
      server.getWorldByName(name: 'minecraft:overworld') ??
      server.getWorldByName(name: 'world') ??
      (throw StateError('no overworld'));
  final out = <String>[];
  final stone = BlockRegistry.resolveState('minecraft:stone')!;
  final air = BlockRegistry.resolveState('minecraft:air')!;
  final sailEast = BlockRegistry.resolveState('create:white_sail', {'facing': 'east'})!;
  final bot = FakePlayers.create(world, 'SailProbe');

  Future<void> set((int, int, int) p, int state) => world.setBlockState(
    pos: BlockPos(x: p.$1, y: p.$2, z: p.$3),
    state: state,
    updateFlags: {BlockFlagsFlag.notifyListeners},
  );

  String at((int, int, int) p) {
    final id = world.getBlockStateId(pos: BlockPos(x: p.$1, y: p.$2, z: p.$3));
    final name = BlockRegistry.fromStateId(id)?.name ?? '?';
    final props = BlockRegistry.stateFromId(id)?.propertyMap ?? const {};
    return '$name${props.isEmpty ? '' : props}';
  }

  Future<void> hold(String key) => bot.setItemInHand(
    hand: Hand.right,
    stack: ItemStack.create(registryKey: key, count: 1),
  );

  String held() {
    final stack = bot.getItemInHand(hand: Hand.right);
    if (stack == null) return 'empty';
    final key = stack.getRegistryKey();
    final count = stack.getCount();
    stack.dispose();
    return '$key x$count';
  }

  // Registry numbering: what the host calls these entries.
  final shaftBlock = BlockRegistry.of('create:shaft');
  final sailBlock = BlockRegistry.of('create:white_sail');
  out.add(
    'ids shaft.block=${shaftBlock?.id} shaft.defaultState=${BlockRegistry.resolveState('create:shaft')} '
    'white_sail.block=${sailBlock?.id} '
    'states=${[for (final f in ['down', 'up', 'north', 'south', 'west', 'east']) '$f:${BlockRegistry.resolveState('create:white_sail', {'facing': f})}']} '
    'item.white_sail=${ItemRegistries.host.idOf('create:white_sail')} '
    'item.crafting_blueprint=${ItemRegistries.host.idOf('create:crafting_blueprint')} '
    'item.stone=${ItemRegistries.host.idOf('minecraft:stone')} '
    'blocks=${BlockRegistry.count} states=${BlockRegistry.stateCount} '
    'vanilla_items=${ItemRegistries.host.vanillaCount} '
    'plugin_items=${ItemRegistries.host.registeredItems.length}',
  );

  if (action != 'run' && action != 'engine' && action != 'feed' && action != 'symrow') {
    FakePlayers.remove(bot);
    return out;
  }

  // 0. Control: a vanilla block item placed by the same fake player.
  await set((0, 100, 0), stone);
  await set((0, 101, 0), air);
  FakePlayerActions(bot).moveTo(world, (1.5, 101.0, 0.5), yaw: 0, pitch: 90);
  await hold('minecraft:stone');
  final controlChanged = await bot.useItemOnBlock(
    BlockPos(x: 0, y: 100, z: 0),
    BlockDirection.up,
    cursor: (0.5, 0.5, 0.5),
  );
  out.add('control_place changed=$controlChanged at(0,101,0)=${at((0, 101, 0))} held=${held()}');

  // 1. Placement orientation: look straight down and place a sail on a stone top.
  await set((4, 100, 4), stone);
  await set((4, 101, 4), air);
  FakePlayerActions(bot).moveTo(world, (5.5, 101.0, 4.5), yaw: 0, pitch: 90);
  await hold('create:white_sail');
  final heldBefore = held();
  final placed = await bot.useItemOnBlock(
    BlockPos(x: 4, y: 100, z: 4),
    BlockDirection.up,
    cursor: (0.5, 0.5, 0.5),
  );
  out.add(
    'look_down placed=$placed held_before=$heldBefore held_after=${held()} '
    'clicked(4,100,4)=${at((4, 100, 4))} at(4,101,4)=${at((4, 101, 4))} (java: facing=up)',
  );

  // 2. Row placement: click a sail that faces east while looking south.
  await set((8, 100, 8), stone);
  await set((8, 101, 8), sailEast);
  await set((8, 102, 8), air);
  FakePlayerActions(bot).moveTo(world, (9.5, 100.9, 8.5), yaw: 0, pitch: 0);
  await hold('create:white_sail');
  final row = await bot.useItemOnBlock(
    BlockPos(x: 8, y: 101, z: 8),
    BlockDirection.up,
    cursor: (0.5, 0.5, 0.1),
  );
  out.add(
    'row placed=$row clicked=${at((8, 101, 8))} above=${at((8, 102, 8))} east=${at((9, 101, 8))} '
    'north=${at((8, 101, 7))} held_after=${held()} '
    '(java: a sail with facing=east where the run grew)',
  );

  if (action == 'symrow') {
    // 5. The symmetric sail's own row placement (`SymmetricSailPlacementHelper`):
    // a `y` sail, clicked near its north edge with a sail item.
    final sailY = BlockRegistry.resolveState('simulated:white_symmetric_sail', {'axis': 'y'})!;
    await set((16, 100, 16), stone);
    await set((16, 101, 16), sailY);
    await set((16, 101, 15), air);
    await set((16, 101, 17), air);
    FakePlayerActions(bot).moveTo(world, (17.5, 100.9, 16.5), yaw: 0, pitch: 0);
    await hold('simulated:white_symmetric_sail');
    final symRow = await bot.useItemOnBlock(
      BlockPos(x: 16, y: 101, z: 16),
      BlockDirection.up,
      cursor: (0.5, 0.5, 0.1),
    );
    out.add(
      'symrow placed=$symRow clicked=${at((16, 101, 16))} north=${at((16, 101, 15))} '
      'south=${at((16, 101, 17))} held_after=${held()} '
      '(java: a sail where the sheet grew, axis=y)',
    );
    FakePlayers.remove(bot);
    return out;
  }

  if (action == 'engine') {
    // 3. The portable engine: place it on stone.
    await set((12, 100, 12), stone);
    await set((12, 101, 12), air);
    FakePlayerActions(bot).moveTo(world, (13.5, 101.0, 12.5), yaw: 0, pitch: 90);
    await hold('simulated:white_portable_engine');
    final enginePlaced = await bot.useItemOnBlock(
      BlockPos(x: 12, y: 100, z: 12),
      BlockDirection.up,
      cursor: (0.5, 0.5, 0.5),
    );
    out.add('engine placed=$enginePlaced at(12,101,12)=${at((12, 101, 12))}');
    FakePlayers.remove(bot);
    return out;
  }

  if (action == 'feed') {
    // 4. Feed the engine (a separate call, so the block entity that was placed is
    // the one the host is ticking: a click in the placing tick is a race the host
    // wins by re-announcing the entity).
    FakePlayerActions(bot).moveTo(world, (13.5, 101.0, 12.5), yaw: 0, pitch: 90);
    await hold('minecraft:coal');
    final fed = await bot.useItemOnBlock(
      BlockPos(x: 12, y: 101, z: 12),
      BlockDirection.up,
      cursor: (0.5, 0.5, 0.5),
    );
    out.add('engine fed=$fed at(12,101,12)=${at((12, 101, 12))} held_after=${held()}');
    FakePlayers.remove(bot);
    return out;
  }

  FakePlayers.remove(bot);
  return out;
}
// The `/create` command tree (`AllCommands.register`) and Catnip's `/catnip config` and
// `/catnip util flySpeed`. Entity arguments are UUIDs or player names (the host does not hand
// entity selectors to plugins), everything else follows the Java commands.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/infra.dart';
import '../../api/payloads.dart';
import '../../common/binary_nbt.dart';
import '../../common/host_bridge.dart';
import '../../common/pos.dart';
import '../../common/bounds.dart';
import '../../core/registry.dart';
import '../../core/services.dart';
import '../../core/state_layouts.dart';
import '../../core/worlds.dart';
import '../../trains/track/track_host.dart' show readConnectingFrom;
import '../config/config_service.dart';
import 'command_parsing.dart';
import 'railway_report.dart';

/// What the commands need at run time. The module fills it in `onLoad`; the commands are declared
/// earlier (in `register`).
final class InfraCommandState {
  late CreateServices services;
  late ServerConfigService config;
  late Worlds worlds;
  late DebugInfoRegistry debug;
  late Logger log;
}

/// The server side `DebugInformation`.
final class DebugInfoRegistry implements DebugInformation {
  final List<DebugInfoSection> _server = [];

  @override
  void registerServerInfo(DebugInfoSection section) => _server.add(section);

  @override
  List<DebugInfoSection> get serverInfo => List.unmodifiable(_server);
}

/// Registers `create` (alias `c`) and `catnip`.
void registerInfrastructureCommands(CreateRegistry registry, InfraCommandState st) {
  registry.command(
    'create',
    (c) => _buildCreate(c, st),
    description: "Create's utility commands",
    aliases: ['c'],
    permission: const CommandPermission('create:command.create', description: 'Use /create'),
  );
  registry.command(
    'catnip',
    (c) => _buildCatnip(c, st),
    description: "Catnip's config and utility commands",
    permission: const CommandPermission('create:command.catnip', description: 'Use /catnip'),
  );
}

CommandPermission _op(String node, String description) => CommandPermission.op(node, description: description);

void _buildCreate(CommandBuilder c, InfraCommandState st) {
  c.describe("Create's utility commands");
  c.runs((ctx) => ctx.reply('/create <trains|debuginfo|highlight|passenger|coupling|clone|train|glue|util|config>'));

  // -- general purpose ----------------------------------------------------------
  c.sub(
    'trains',
    description: 'Summary of track networks and trains near you',
    permission: _op('create:command.trains', 'Use /create trains'),
    runs: (ctx) => _trains(ctx, st),
  );
  c.sub(
    'debuginfo',
    description: 'Copies debug information to your clipboard',
    build: (s) => s
      ..requirePlayer()
      ..runs((ctx) => _debugInfo(ctx, st)),
  );
  c.sub(
    'highlight',
    description: 'Highlights a block, or the cause of a failed contraption assembly',
    build: (s) => s
      ..runs((ctx) => _highlightAssembly(ctx, st))
      ..arg(
        'pos',
        ArgumentTypes.blockPos,
        runs: (ctx) => _highlight(ctx, st, ctx.blockPos('pos'), [ctx.player]),
        build: (a) => a.arg('players', ArgumentTypes.players, runs: (ctx) {
          return _highlight(ctx, st, ctx.blockPos('pos'), ctx.players('players'));
        }),
      ),
  );
  c.sub(
    'passenger',
    description: 'Seats an entity on another',
    permission: _op('create:command.passenger', 'Use /create passenger'),
    build: (s) => s.arg(
      'rider',
      ArgumentTypes.word,
      build: (r) => r.arg(
        'vehicle',
        ArgumentTypes.word,
        runs: (ctx) => _passenger(ctx, st, 0),
        build: (v) => v.arg('seatIndex', ArgumentTypes.integer(min: 0), runs: (ctx) => _passenger(ctx, st, ctx.integer('seatIndex'))),
      ),
    ),
  );
  c.sub(
    'coupling',
    description: 'Couples or decouples minecarts',
    permission: _op('create:command.coupling', 'Use /create coupling'),
    build: (s) {
      s.sub(
        'add',
        build: (a) => a.arg(
          'cart1',
          ArgumentTypes.word,
          build: (b) => b.arg('cart2', ArgumentTypes.word, runs: (ctx) => _couplingAdd(ctx, st)),
        ),
      );
      s.sub(
        'remove',
        build: (a) => a.arg(
          'cart1',
          ArgumentTypes.word,
          build: (b) => b.arg('cart2', ArgumentTypes.word, runs: (ctx) => _couplingRemove(ctx, st)),
        ),
      );
      s.sub('removeAll', build: (a) => a.arg('cart', ArgumentTypes.word, runs: (ctx) => _couplingRemoveAll(ctx, st)));
    },
  );
  c.sub(
    'clone',
    description: 'Clones all blocks as well as super glue from the specified area to the target destination',
    permission: _op('create:command.clone', 'Use /create clone'),
    runs: (ctx) => ctx.reply('Clones all blocks as well as super glue from the specified area to the target destination'),
    build: (s) => s.arg(
      'begin',
      ArgumentTypes.blockPos,
      build: (b) => b.arg(
        'end',
        ArgumentTypes.blockPos,
        build: (e) => e.arg(
          'destination',
          ArgumentTypes.blockPos,
          runs: (ctx) => _clone(ctx, st, true),
          build: (d) => d.sub('skipBlocks', runs: (ctx) => _clone(ctx, st, false)),
        ),
      ),
    ),
  );
  c.sub(
    'train',
    description: 'Removes or teleports to a train',
    permission: _op('create:command.train', 'Use /create train'),
    build: (s) {
      s.sub('remove', build: (a) => a.arg('train', ArgumentTypes.word, runs: (ctx) => _trainRemove(ctx, st)));
      s.sub(
        'tp',
        build: (a) => a
          ..requirePlayer()
          ..arg('train', ArgumentTypes.word, runs: (ctx) => _trainTeleport(ctx, st)),
      );
    },
  );
  c.sub(
    'glue',
    description: 'Places super glue between two positions',
    permission: _op('create:command.glue', 'Use /create glue'),
    build: (s) => s.arg(
      'from',
      ArgumentTypes.blockPos,
      build: (f) => f.arg('to', ArgumentTypes.blockPos, runs: (ctx) => _glue(ctx, st)),
    ),
  );

  // TEMPORARY (track placement investigation): drive the item flow headlessly.
  c.sub(
    'trackdbg',
    description: 'DEBUG: click a track with a fake player and report the placement',
    build: (s) => s.arg(
      'from',
      ArgumentTypes.blockPos,
      build: (f) => f.arg(
        'to',
        ArgumentTypes.blockPos,
        runs: (ctx) => _trackDbg(ctx, st),
      ),
    ),
  );

  // -- utility ------------------------------------------------------------------
  c.sub(
    'util',
    aliases: ['u'],
    description: 'Utility commands',
    build: (u) {
      u.sub(
        'replaceInCommandBlocks',
        description: 'Replaces text in the command blocks of an area',
        permission: _op('create:command.replace_in_command_blocks', 'Use /create util replaceInCommandBlocks'),
        build: (r) => r.arg(
          'begin',
          ArgumentTypes.blockPos,
          build: (b) => b.arg(
            'end',
            ArgumentTypes.blockPos,
            build: (e) => e.arg(
              'toReplace',
              ArgumentTypes.string,
              build: (t) => t.arg('replaceWith', ArgumentTypes.string, runs: (ctx) => _replaceInCommandBlocks(ctx, st)),
            ),
          ),
        ),
      );
      // `/c util flySpeed` of Catnip joins the shortcut in Java.
      _buildFlySpeed(u, st);
    },
  );

  // The Catnip config commands are reachable through the shortcut `/c config ...` in Java.
  _buildConfig(c, st);
}

void _buildCatnip(CommandBuilder c, InfraCommandState st) {
  c.describe("Catnip's commands");
  _buildConfig(c, st);
  c.sub('util', aliases: ['u'], build: (u) => _buildFlySpeed(u, st));
}

// ---------------------------------------------------------------------------- helpers

PayloadBus? _bus(InfraCommandState st) => st.services.find<PayloadBus>();

PayloadBus _requireBus(InfraCommandState st) =>
    _bus(st) ?? (throw CommandException('The payload bus is not available.'));

T _hook<T extends Object>(InfraCommandState st, String what) =>
    st.services.find<T>() ?? (throw CommandException('$what is not available: that part of Create is not installed.'));

World _worldOf(CommandContext ctx) =>
    ctx.sender.world() ?? (throw CommandException('This command needs a world, run it as a player or from a command block.'));

/// Finds an entity by [ref] in any world; players by name.
Entity? _resolveEntity(CommandContext ctx, EntityRef ref) {
  switch (ref) {
    case PlayerName(:final name):
      final p = ctx.server.getPlayerByName(name: name);
      return p?.asEntity();
    case EntityUuid(:final uuid):
      final id = Uuids.tryParse(uuid);
      if (id == null) return null;
      for (final w in ctx.server.getAllWorlds()) {
        final e = w.getEntityByUuid(id: id);
        if (e != null) return e;
      }
      return null;
  }
}

Entity _entityArg(CommandContext ctx, String key) {
  final EntityRef ref;
  try {
    ref = EntityRef.parse(ctx.string(key));
  } on ArgumentParseException catch (e) {
    throw CommandException(e.message);
  }
  return _resolveEntity(ctx, ref) ?? (throw CommandException('No entity was found for `${ctx.string(key)}`.'));
}

Text _line(String s, int rgb) => Text(s).rgb((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);

// ---------------------------------------------------------------------------- trains

void _trains(CommandContext ctx, InfraCommandState st) {
  final hooks = _hook<RailwayCommandHooks>(st, 'Trains');
  final world = _worldOf(ctx);
  final pos = ctx.sender.position() ?? (0.0, 0.0, 0.0);
  final summary = hooks.summarize(world.getId(), pos);
  for (final line in railwayReport(summary)) {
    switch (line) {
      case TextLine(:final text, :final color):
        ctx.sender.send(_line(text, color));
      case TeleportButton():
        ctx.sender.send(
          _line('├─', darkBlue).add(
            _line('[', darkBlue)
                .add(_line('Teleport', orange))
                .add(_line(']', darkBlue))
                .runCommand(line.command)
                .hover('Click to teleport to ${line.trainName}'),
          ),
        );
      case DeleteButton():
        ctx.sender.send(
          _line('└─', blue).add(
            _line('[', blue)
                .add(_line('Remove', orange))
                .add(_line(']', blue))
                .runCommand(line.command)
                .hover('Click to remove ${line.trainName}'),
          ),
        );
    }
  }
}

void _trainRemove(CommandContext ctx, InfraCommandState st) {
  final hooks = _hook<RailwayCommandHooks>(st, 'Trains');
  final String id;
  try {
    id = parseUuid(ctx.string('train'));
  } on ArgumentParseException catch (e) {
    throw CommandException(e.message);
  }
  final train = hooks.findTrain(id);
  if (train == null || !hooks.removeTrain(id)) {
    ctx.replyError('No Train with id ${shortId(id)}[...] was found');
    return;
  }
  ctx.reply("Train '${train.name}' removed successfully");
}

Future<void> _trainTeleport(CommandContext ctx, InfraCommandState st) async {
  final hooks = _hook<RailwayCommandHooks>(st, 'Trains');
  final String id;
  try {
    id = parseUuid(ctx.string('train'));
  } on ArgumentParseException catch (e) {
    throw CommandException(e.message);
  }
  final player = ctx.player;
  final mode = player.getGamemode();
  if (mode != GameMode.creative && mode != GameMode.spectator) {
    ctx.replyError('Can only teleport to train when in Creative or Spectator Mode!');
    return;
  }
  final train = hooks.findTrain(id);
  if (train == null) {
    ctx.replyError('No Train with id ${shortId(id)}[...] was found');
    return;
  }
  if (train.presence.isEmpty) {
    ctx.replyError('Unable to teleport to Train. No valid location found');
    return;
  }
  final target = train.presence.first;
  World? world;
  for (final w in ctx.server.getAllWorlds()) {
    if (w.getDimension() == target.dimension) {
      world = w;
      break;
    }
  }
  if (world == null) {
    ctx.replyError('Unable to teleport to Train. No valid location found');
    return;
  }
  final yaw = player.getYaw(), pitch = player.getPitch();
  final entity = player.asEntity();
  await entity.teleport(pos: (target.position.$1.toDouble(), target.position.$2 + 5.0, target.position.$3.toDouble()), worldRef: world);
  entity.setRotation(yaw: yaw, pitch: pitch);
  ctx.reply("Teleported to Train '${train.name}' successfully");
}

// ---------------------------------------------------------------------------- debug info

void _debugInfo(CommandContext ctx, InfraCommandState st) {
  final player = ctx.player;
  ctx.reply('Collecting debug information...');
  final text = printDebugInfo('Server', player.getName(), st.debug.serverInfo);
  _requireBus(st).sendClientbound('create:server_debug_info', player, {
    'serverInfo': text.length > 32767 ? text.substring(0, 32767) : text,
  });
}

// ---------------------------------------------------------------------------- highlight

Future<void> _highlight(CommandContext ctx, InfraCommandState st, BlockPos pos, List<Player> targets) async {
  final world = _worldOf(ctx);
  if (!world.isLoaded(pos: pos)) throw CommandException('That position is not loaded');
  final bus = _requireBus(st);
  for (final p in targets) {
    bus.sendClientbound('create:block_highlight', p, {'pos': (pos.x, pos.y, pos.z)});
  }
}

void _highlightAssembly(CommandContext ctx, InfraCommandState st) {
  final player = ctx.player;
  void miss() => ctx.reply('Try looking at a Block that has failed to assemble a Contraption and try again.');
  final hit = player.asEntity().rayTraceBlock(maxDistance: player.asEntity().asLiving()?.getAttributeValue(attr: Attribute.blockInteractionRange) ?? 4.5, includeFluids: false);
  if (hit == null) return miss();
  final hooks = st.services.find<AssemblyExceptionHooks>();
  final world = _worldOf(ctx);
  final exception = hooks?.lastAssemblyException(world, hit.pos.toPos());
  if (exception == null) return miss();
  final p = exception.position;
  if (p == null) {
    ctx.reply("Can't highlight a specific position for this issue");
    return;
  }
  _requireBus(st).sendClientbound('create:block_highlight', player, {'pos': p});
}

// ---------------------------------------------------------------------------- passenger / coupling

Future<void> _passenger(CommandContext ctx, InfraCommandState st, int index) async {
  final rider = _entityArg(ctx, 'rider');
  final vehicle = _entityArg(ctx, 'vehicle');
  if (rider.getId() == vehicle.getId()) return;
  final hooks = st.services.find<PassengerCommandHooks>();
  if (hooks != null) {
    if (hooks.isContraptionEntity(rider)) return;
    if (await hooks.trySeat(vehicle, rider, index)) return;
  }
  await vehicle.addPassenger(passenger: rider);
}

Future<(World, int, int)> _twoCarts(CommandContext ctx, String k1, String k2) async {
  final cart1 = _entityArg(ctx, k1);
  final cart2 = _entityArg(ctx, k2);
  for (final e in [cart1, cart2]) {
    if (!_isMinecart(e)) throw CommandException('Only Minecarts can be coupled');
  }
  final w1 = cart1.getWorld(), w2 = cart2.getWorld();
  if (w1.getId() != w2.getId()) throw CommandException('Minecarts have to be in the same Dimension');
  return (w1, cart1.getId(), cart2.getId());
}

bool _isMinecart(Entity e) {
  final key = e.getType()?.name;
  return key != null && key.toLowerCase().contains('minecart');
}

Future<void> _couplingAdd(CommandContext ctx, InfraCommandState st) async {
  final hooks = _hook<MinecartCouplingHooks>(st, 'Minecart couplings');
  final (world, a, b) = await _twoCarts(ctx, 'cart1', 'cart2');
  await hooks.couple(world, a, b, source: ctx.playerOrNull);
}

Future<void> _couplingRemove(CommandContext ctx, InfraCommandState st) async {
  final hooks = _hook<MinecartCouplingHooks>(st, 'Minecart couplings');
  final (world, a, b) = await _twoCarts(ctx, 'cart1', 'cart2');
  switch (await hooks.remove(world, a, b)) {
    case CouplingRemoval.noCouplings:
      ctx.reply('Minecart has no Couplings Attached');
    case CouplingRemoval.notCoupled:
      ctx.reply('The specified Carts are not coupled');
    case CouplingRemoval.removed:
      break;
  }
}

Future<void> _couplingRemoveAll(CommandContext ctx, InfraCommandState st) async {
  final hooks = _hook<MinecartCouplingHooks>(st, 'Minecart couplings');
  final cart = _entityArg(ctx, 'cart');
  if (!_isMinecart(cart)) throw CommandException('Only Minecarts can be coupled');
  final count = await hooks.removeAll(cart.getWorld(), cart.getId());
  if (count == 0) {
    ctx.reply('Minecart has no Couplings Attached');
    return;
  }
  ctx.reply('Removed $count couplings from the Minecart');
}

// ---------------------------------------------------------------------------- glue / clone

Future<void> _glue(CommandContext ctx, InfraCommandState st) async {
  final hooks = _hook<GlueCommandHooks>(st, 'Super glue');
  final world = _worldOf(ctx);
  final from = ctx.blockPos('from'), to = ctx.blockPos('to');
  _requireLoaded(world, [from, to]);
  await hooks.placeGlue(world, from.toPos(), to.toPos());
}

void _requireLoaded(World world, List<BlockPos> positions) {
  for (final p in positions) {
    if (!world.isLoaded(pos: p)) throw CommandException('That position is not loaded');
  }
}

Future<void> _clone(CommandContext ctx, InfraCommandState st, bool cloneBlocks) async {
  final world = _worldOf(ctx);
  final begin = ctx.blockPos('begin').toPos();
  final end = ctx.blockPos('end').toPos();
  final destination = ctx.blockPos('destination').toPos();
  final source = BlockBounds.fromCorners(begin, end);
  final size = (source.xSpan - 1, source.ySpan - 1, source.zSpan - 1);
  final destEnd = destination + size;
  final volume = source.xSpan * source.ySpan * source.zSpan;
  final limit = world.getGameRuleInt(GameRule.maxBlockModifications) ?? 0;
  if (volume > limit) throw CommandException('Too many blocks in the specified area (maximum $limit, specified $volume)');
  if (!world.isAreaLoaded(min: begin.toBlockPos(), max: end.toBlockPos()) ||
      !world.isAreaLoaded(min: destination.toBlockPos(), max: destEnd.toBlockPos())) {
    throw CommandException('That position is not loaded');
  }
  final offset = destination - source.minPos;
  var blockPastes = 0;
  if (cloneBlocks) blockPastes = await cloneBlocksTo(world, source, offset);
  var gluePastes = 0;
  final glue = st.services.find<GlueCommandHooks>();
  if (glue != null) gluePastes = await glue.cloneGlue(world, source, offset);
  if (cloneBlocks) ctx.reply('Successfully cloned $blockPastes Blocks');
  ctx.reply('Successfully applied glue $gluePastes times');
}

/// `CloneCommand.cloneBlocks`: copies every block (with its block entity) of [source] to the area
/// moved by [offset]. All blocks are read first, so the areas may overlap. Scheduled block ticks
/// are not copied (the host has no API for them). Returns the number of blocks written.
Future<int> cloneBlocksTo(World world, BlockBounds source, Pos offset) async {
  final changes = <BlockPlacementChange>[];
  final barriers = <BlockPlacementChange>[];
  final barrier = BlockRegistry.resolveState('minecraft:barrier') ?? 0;
  // z outermost, then y, then x, like the Java loops.
  for (var z = source.minZ; z <= source.maxZ; z++) {
    for (var y = source.minY; y <= source.maxY; y++) {
      for (var x = source.minX; x <= source.maxX; x++) {
        final from = (x, y, z);
        final to = from + offset;
        final bp = from.toBlockPos();
        final state = world.getBlockStateId(pos: bp);
        final nbt = world.getBlockEntityNbt(pos: bp);
        barriers.add(BlockPlacementChange(to.toBlockPos(), barrier));
        changes.add(BlockPlacementChange(to.toBlockPos(), state, blockEntityNbt: nbt));
      }
    }
  }
  // The target block entities lose their contents (Clearable.tryClear) by being replaced first.
  await world.placeBlocks(barriers.reversed.toList(), flags: BlockUpdateFlags.clientsOnly);
  return world.placeBlocks(changes, flags: BlockUpdateFlags.normal);
}

// ---------------------------------------------------------------------------- command blocks

const Set<String> _commandBlocks = {
  'minecraft:command_block',
  'minecraft:chain_command_block',
  'minecraft:repeating_command_block',
};

Future<void> _replaceInCommandBlocks(CommandContext ctx, InfraCommandState st) async {
  final world = _worldOf(ctx);
  final from = ctx.blockPos('begin').toPos(), to = ctx.blockPos('end').toPos();
  _requireLoaded(world, [from.toBlockPos(), to.toBlockPos()]);
  final toReplace = ctx.string('toReplace');
  final replaceWith = ctx.string('replaceWith');
  RegExp regex;
  try {
    regex = RegExp(toReplace);
  } on FormatException catch (e) {
    throw CommandException('Invalid regular expression: ${e.message}');
  }
  var blocks = 0;
  for (final pos in from.boxTo(to)) {
    final bp = pos.toBlockPos();
    if (!_commandBlocks.contains(world.getBlock(pos: bp).name)) continue;
    final raw = world.getBlockEntityNbt(pos: bp);
    if (raw == null) continue;
    final parsed = BinaryNbt.read(raw);
    if (parsed == null || parsed.root.kind != NbtKind.compound) continue;
    final map = parsed.root.asCompound;
    final commandTag = map['Command'];
    if (commandTag == null || commandTag.kind != NbtKind.string) continue;
    final command = commandTag.value as String;
    if (command.contains(toReplace)) blocks++;
    final updated = command.replaceAll(regex, replaceWith);
    if (updated == command) continue;
    final newMap = {...map, 'Command': NbtValue.string(updated)};
    final result = world.setBlockEntityNbt(pos: bp, nbtData: BinaryNbt.write(NbtValue.compound(newMap), name: parsed.name));
    if (result case ErrorResult(:final value)) st.log.warn('Could not update the command block at ${shortPos(pos)}: $value');
  }
  if (blocks == 0) {
    ctx.reply('Couldn\'t find "$toReplace" anywhere.');
    return;
  }
  ctx.reply('Replaced occurrences in $blocks blocks.');
}

// ---------------------------------------------------------------------------- catnip

void _buildConfig(CommandBuilder c, InfraCommandState st) {
  c.sub(
    'config',
    description: 'Opens or changes a config',
    build: (s) {
      s.requirePlayer();
      s.runs((ctx) => _openConfig(ctx, st, EitherValue.left('catnip')));
      s.arg(
        'target',
        ArgumentTypes.word,
        runs: (ctx) => _openConfigTarget(ctx, st),
        build: (t) => t.arg(
          'path',
          ArgumentTypes.word,
          runs: (ctx) => _openConfigValue(ctx, st),
          build: (p) => p.sub(
            'set',
            description: 'Changes the value (server operators with permission level 4)',
            build: (set) => set.arg('value', ArgumentTypes.string, runs: (ctx) => _setConfigValue(ctx, st)),
          ),
        ),
      );
    },
  );
}

void _openConfig(CommandContext ctx, InfraCommandState st, EitherValue target) {
  _requireBus(st).sendClientbound('catnip:open_config_screen', ctx.player, {'modOrConfigOrValueId': target});
}

void _openConfigTarget(CommandContext ctx, InfraCommandState st) {
  final target = ctx.string('target');
  if (target.contains(':')) {
    final CatnipConfigId id;
    try {
      id = CatnipConfigId.parse(target);
    } on ArgumentParseException catch (e) {
      throw CommandException(e.message);
    }
    _openConfig(ctx, st, EitherValue.right(EitherValue.left(_configIdFields(id))));
  } else {
    _openConfig(ctx, st, EitherValue.left(target));
  }
}

Map<String, Object?> _configIdFields(CatnipConfigId id) => {'modId': id.modId, 'side': id.side.index};

(CatnipConfigId, CatnipConfigPath) _valueId(CommandContext ctx) {
  try {
    return (CatnipConfigId.parse(ctx.string('target')), CatnipConfigPath.parse(ctx.string('path')));
  } on ArgumentParseException catch (e) {
    throw CommandException(e.message);
  }
}

void _openConfigValue(CommandContext ctx, InfraCommandState st) {
  final (id, path) = _valueId(ctx);
  _openConfig(
    ctx,
    st,
    EitherValue.right(EitherValue.right({'config': _configIdFields(id), 'path': path.components})),
  );
}

Future<void> _setConfigValue(CommandContext ctx, InfraCommandState st) async {
  if (!ctx.sender.hasPermissionLevel(level: PermissionLevel2.four)) {
    throw CommandException('You do not have permission to change configs.');
  }
  final (id, path) = _valueId(ctx);
  final value = ctx.string('value');
  if (id.side == CatnipConfigSide.client) {
    _requireBus(st).sendClientbound('catnip:set_config_value', ctx.player, {
      'id': {'config': _configIdFields(id), 'path': path.components},
      'value': value,
    });
    ctx.reply('Requested the config change on your client');
    return;
  }
  final error = st.config.setFromText(id, path, value);
  if (error != null) throw CommandException('Failed to set the config value: $error');
  ctx.reply('Set $id/$path to $value');
}

void _buildFlySpeed(CommandBuilder u, InfraCommandState st) {
  u.sub(
    'flySpeed',
    description: "Changes a player's flying speed",
    permission: _op('create:command.fly_speed', 'Use /catnip util flySpeed'),
    build: (f) {
      f.arg(
        'speed',
        ArgumentTypes.number(min: 0),
        runs: (ctx) => _flySpeed(ctx, ctx.player, ctx.number('speed')),
        build: (a) => a.arg('target', ArgumentTypes.player, runs: (ctx) async {
          for (final p in ctx.targetPlayers('target')) {
            await _flySpeed(ctx, p, ctx.number('speed'));
          }
        }),
      );
      f.sub(
        'reset',
        runs: (ctx) => _flySpeed(ctx, ctx.player, 0.05),
        build: (r) => r.arg('target', ArgumentTypes.player, runs: (ctx) async {
          for (final p in ctx.targetPlayers('target')) {
            await _flySpeed(ctx, p, 0.05);
          }
        }),
      );
    },
  );
}

Future<void> _flySpeed(CommandContext ctx, Player player, double speed) async {
  player.setFlySpeed(speed: speed);
  ctx.reply("[Catnip]: Set ${player.getName()}'s fly speed to $speed");
}

// TEMPORARY (track placement investigation): the whole click flow of the track item with a fake
// player, then a report of the blocks it left behind. Remove once the placement is proven.
Future<void> _trackDbg(CommandContext ctx, InfraCommandState st) async {
  final worlds = ctx.server.getAllWorlds();
  if (worlds.isEmpty) throw CommandException('No worlds are loaded');
  final world = ctx.sender.world() ?? worlds.first;
  final a = ctx.blockPos('from').toPos();
  final b = ctx.blockPos('to').toPos();

  await setBlockState(world, a.below, const BState('minecraft:stone'));
  await setBlockState(world, b.below, const BState('minecraft:stone'));
  await setBlockState(
    world,
    a,
    BState('create:track', {
      'shape': 'zo',
      'turn': 'false',
      'waterlogged': 'false',
    }),
  );
  await setBlockState(world, b, BState.air);
  await setBlockState(world, (a.$1, a.$2 + 1, a.$3), BState.air);

  final bot = FakePlayers.create(world, 'TrackDbgBot');
  try {
    await bot.setGamemode(mode: GameMode.creative);
    FakePlayerActions(bot).moveTo(world, (a.$1 + 0.5, a.$2.toDouble(), a.$3 - 2.5), yaw: 0, pitch: 0);
    await bot.give(ItemStack.create(registryKey: 'create:track', count: 64));
    bot.getInventory().setSelectedSlot(slot: 0);
    st.log.info('TRACKDBG before: A=${_dbgState(world, a)} B=${_dbgState(world, b)}');

    await bot.useItemOnBlock(a.toBlockPos(), BlockDirection.up);
    final held = bot.getItemInHand(hand: Hand.right);
    final from = held == null ? null : readConnectingFrom(held);
    st.log.info('TRACKDBG click1: held=${held == null ? null : await held.getRegistryKey()} connectingFrom=$from');

    // The second click must be within the block interaction range of the bot.
    FakePlayerActions(bot).moveTo(
      world,
      (b.$1 + 0.5, b.$2.toDouble(), b.$3 - 2.5),
      yaw: 0,
      pitch: 0,
    );
    try {
      await bot.useItemOnBlock(b.below.toBlockPos(), BlockDirection.up);
    } catch (e, s) {
      st.log.info('TRACKDBG click2 threw: $e\n$s');
    }
    final held2 = bot.getItemInHand(hand: Hand.right);
    st.log.info(
      'TRACKDBG click2: held=${held2 == null ? null : await held2.getRegistryKey()} '
      'connectingFrom=${held2 == null ? null : readConnectingFrom(held2)}',
    );
  } finally {
    FakePlayers.remove(bot);
  }

  final report = [
    for (var i = 0; i <= (b.$3 - a.$3).abs() + 1; i++)
      (a.$1, a.$2, a.$3 + (b.$3 > a.$3 ? i : -i)),
  ];
  for (final p in report) {
    ctx.reply('$p -> ${_dbgState(world, p)}');
  }
}

String _dbgState(World world, Pos p) {
  final id = world.getBlockStateId(pos: p.toBlockPos());
  return 'id=$id info=${BlockStates.info(id)} layout=${PluginStateLayouts.valuesAt(id)}';
}

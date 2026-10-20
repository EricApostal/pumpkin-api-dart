// `dev.ryanhcode.sable.command.SableCommand`: the root `/sable` tree.
//
// ```
// /sable name …            (SableSubLevelCommands)
// /sable teleport …        (SableSubLevelCommands)
// /sable remove …          (SableSubLevelCommands)
// /sable physics …         (SablePhysicsCommands)
// /sable spawn …           (SableSpawnCommands)
// /sable assemble …        (SableAssembleCommands)
// /sable storage …         (SableStorageCommands)
// /sable debug joint …     (SableJointCommands)
// /sable debug config …    (SableConfigCommands)
// /sable paused [true|false]
// /sable forceload <add|query|remove> [sub_level]
// /sable info <sub_level>
// /sable engage_gizmo
// /sable debug udp_test
// ```
//
// The Java root requires permission level 2 (gamemasters); the plugin's
// `CommandPermission.op` does the same.
//
// Pure: no host imports beyond the model.
import 'package:pumpkin_api/pumpkin_api.dart'
    show ArgumentTypes, CommandBuilder, CommandContext, CommandException, CommandPermission;

import '../api/command/sable_command_helper.dart';
import '../api/command/sable_command_state.dart';
import '../api/sub_level_ticket.dart';
import '../math/vector.dart';
import '../model/server_sub_level.dart';
import '../model/server_sub_level_container.dart';
import '../storage/holding/saved_pointer.dart';
import '../system/physics_system.dart';
import 'command_support.dart';
import 'sable_assemble_commands.dart';
import 'sable_config_commands.dart';
import 'sable_joint_commands.dart';
import 'sable_physics_commands.dart';
import 'sable_spawn_commands.dart';
import 'sable_storage_commands.dart';
import 'sable_sub_level_commands.dart';

/// The permission node of `/sable` (`Commands.LEVEL_GAMEMASTERS`).
final CommandPermission sableCommandPermission = CommandPermission.op(
  'sable:command.sable',
  description: 'Use /sable',
);

/// Registers the whole `/sable` tree under [root].
void registerSableCommands(CommandBuilder root, SableCommandState state) {
  root.describe('Sable sub-level management');
  root.runs((ctx) => ctx.reply(
    '/sable <name|teleport|remove|physics|spawn|assemble|storage|debug|paused|forceload|info>',
  ));

  registerSubLevelCommands(root, state);
  registerPhysicsCommands(root, state);
  registerSpawnCommands(root, state);
  registerAssembleCommands(root, state);
  registerStorageCommands(root, state);

  root.sub('debug', build: (debug) {
    registerJointCommands(debug, state);
    registerConfigCommands(debug, state);
    debug.sub('udp_test', runs: (ctx) => _udpTest(ctx));
  });

  root.sub(
    'paused',
    description: 'Toggles or sets whether physics is paused',
    runs: (ctx) => _togglePaused(ctx, state),
    build: (paused) => paused.arg(
      'paused',
      ArgumentTypes.boolean,
      runs: (ctx) => _setPaused(ctx, state, ctx.boolean('paused')),
    ),
  );

  root.sub(
    'forceload',
    description: 'Force-loads sub-levels',
    build: (forceload) {
      forceload.sub(
        'add',
        build: (add) => add.arg(
          'sub_level',
          ArgumentTypes.word,
          runs: (ctx) => _forceload(ctx, state, true),
        ),
      );
      forceload.sub('query', runs: (ctx) => _forceloadQuery(ctx, state));
      forceload.sub(
        'remove',
        build: (remove) => remove.arg(
          'sub_level',
          ArgumentTypes.word,
          runs: (ctx) => _forceload(ctx, state, false),
        ),
      );
    },
  );

  root.sub(
    'info',
    description: 'Prints the pose, mass and velocity of sub-levels',
    build: (info) => info.arg(
      'sub_level',
      ArgumentTypes.word,
      runs: (ctx) => _info(ctx, state),
    ),
  );

  root.sub(
    'engage_gizmo',
    description: 'Enters the physics gizmo (pauses physics)',
    runs: (ctx) => throw CommandException(
      'HOST GAP: /sable engage_gizmo sends ClientboundEnterGizmoPacket through '
      'Veil to the real Sable client; the plugin has no gizmo payload channel, '
      'so the client cannot enter the gizmo. Physics was left running.',
    ),
  );
}

int _udpTest(CommandContext ctx) => throw CommandException(
  'HOST GAP: /sable debug udp_test sends a SableUDPEchoPacket over Sable\'s UDP '
  'socket; the plugin has no UDP transport, so there is no server to send on.',
);

int _togglePaused(CommandContext ctx, SableCommandState state) {
  final physics = _physics(ctx, state);
  physics.isPaused = !physics.isPaused;
  ctx.reply('Physics paused: ${physics.isPaused}.');
  return 1;
}

int _setPaused(CommandContext ctx, SableCommandState state, bool paused) {
  final physics = _physics(ctx, state);
  physics.isPaused = paused;
  ctx.reply('Physics paused: $paused.');
  return 1;
}

int _forceloadQuery(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  final tickets = container.collectForceLoadTickets();

  var subLevelCount = 0;
  var ticketCount = 0;
  for (final entry in tickets.entries) {
    subLevelCount++;
    ticketCount += entry.value.length;
  }

  if (ticketCount == 0) {
    ctx.replyError('No sub-levels are force-loaded in ${container.level.dimensionId}.');
    return 0;
  }

  ctx.reply(
    '$ticketCount ticket${ticketCount == 1 ? '' : 's'} on $subLevelCount '
    'sub-level${subLevelCount == 1 ? '' : 's'} in ${container.level.dimensionId}.',
  );
  for (final entry in tickets.entries) {
    final subLevel = entry.key;
    ctx.reply('${SableCommandHelper.displayName(subLevel)} (${subLevel.uniqueId})');
    for (final ticket in entry.value) {
      ctx.reply('  ${ticket.toCompactString()}');
    }
  }
  return ticketCount;
}

int _forceload(CommandContext ctx, SableCommandState state, bool add) {
  final container = containerOf(ctx, state);
  final subLevels = selectedSubLevels(ctx, state, 'sub_level', multiple: true);

  var count = 0;
  for (final subLevel in subLevels) {
    final changed = add
        ? container.addForceLoadTicket(subLevel, SubLevelLoadingTicketType.commandForced, unitKey)
        : container.removeForceLoadTicket(subLevel, SubLevelLoadingTicketType.commandForced, unitKey);
    if (changed) count++;
  }

  ctx.reply(
    '${add ? 'Force-loaded' : 'Released'} $count sub-level${count == 1 ? '' : 's'}.',
  );
  return count;
}

int _info(CommandContext ctx, SableCommandState state) {
  final container = containerOf(ctx, state);
  final subLevels = selectedSubLevels(ctx, state, 'sub_level', multiple: true);
  if (subLevels.isEmpty) throw CommandException(SableCommandError.noSubLevels.message);

  ctx.reply('${subLevels.length} sub-level${subLevels.length == 1 ? '' : 's'}:');
  for (final subLevel in subLevels) {
    _printInfo(ctx, container, subLevel);
  }
  return subLevels.length;
}

void _printInfo(
  CommandContext ctx,
  ServerSubLevelContainer container,
  ServerSubLevel subLevel,
) {
  final pose = subLevel.logicalPose;
  final position = pose.position();
  final orientation = pose.orientation();
  final pointer = subLevel.getLastSerializationPointer();

  ctx.reply('${SableCommandHelper.displayName(subLevel)} (${subLevel.uniqueId})');
  ctx.reply(
    '  position ${_fmt(position.x)}, ${_fmt(position.y)}, ${_fmt(position.z)}'
    '  [${pointer == null ? 'not saved yet' : pointer.toString()}]',
  );
  ctx.reply(
    '  ${SableCommandHelper.teleportSuggestion(container.level.dimensionId, position.x, position.y, position.z)}',
  );
  ctx.reply(
    '  orientation ${_fmt(orientation.x)}, ${_fmt(orientation.y)}, '
    '${_fmt(orientation.z)}, ${_fmt(orientation.w)}',
  );

  final mass = subLevel.massTracker;
  ctx.reply('  mass ${mass == null ? 'not built yet' : _fmt(_massOf(mass))}');

  final physics = container.physics;
  if (physics is SubLevelPhysicsSystem) {
    final handle = physics.getPhysicsHandle(subLevel);
    final linear = handle.getLinearVelocity(Vector3d());
    final angular = handle.getAngularVelocity(Vector3d());
    ctx.reply('  linear velocity ${_fmt(linear.x)}, ${_fmt(linear.y)}, ${_fmt(linear.z)}');
    ctx.reply('  angular velocity ${_fmt(angular.x)}, ${_fmt(angular.y)}, ${_fmt(angular.z)}');
  } else {
    ctx.reply('  velocity unknown: no physics system');
  }
}

double _massOf(Object massTracker) {
  final inverse = (massTracker as dynamic).getInverseMass() as double;
  return inverse == 0.0 ? 0.0 : 1.0 / inverse;
}

SubLevelPhysicsSystem _physics(CommandContext ctx, SableCommandState state) {
  try {
    return SableCommandHelper.requireSubLevelPhysicsSystem(containerOf(ctx, state));
  } on StateError catch (error) {
    throw CommandException(error.message);
  }
}

/// The key of the `COMMAND_FORCED` ticket (`Unit.INSTANCE`).
const Object unitKey = Unit.instance;

/// A stand-in for Java's `Unit`.
final class Unit {
  const Unit._();

  static const Unit instance = Unit._();
}

String _fmt(double value) => value.toStringAsFixed(2);

/// The saved pointer type is re-exported for the command's hover text.
typedef SubLevelPointer = GlobalSavedSubLevelPointer;

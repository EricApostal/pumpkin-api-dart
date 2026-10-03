import 'package:dart_mappable/dart_mappable.dart' show MapperException;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../lib/src/model.dart';

/// Permission nodes. Everything is allowed by default except what changes the
/// server's shared places, which is for operators.
abstract final class Perm {
  static const home = 'teleport:command.home';
  static const setHome = 'teleport:command.sethome';
  static const delHome = 'teleport:command.delhome';
  static const homes = 'teleport:command.homes';
  static const warp = 'teleport:command.warp';
  static const warps = 'teleport:command.warps';
  static const setWarp = 'teleport:command.setwarp';
  static const delWarp = 'teleport:command.delwarp';
  static const spawn = 'teleport:command.spawn';
  static const setSpawn = 'teleport:command.setspawn';
  static const tpa = 'teleport:command.tpa';
  static const bypassCooldown = 'teleport:bypass.cooldown';
  static const unlimitedHomes = 'teleport:homes.unlimited';
}

void main() => runPlugin(TeleportPlugin());

final class TeleportPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'teleport',
    version: '1.0.0',
    description: 'Homes, warps, spawn and teleport requests.',
    permissions: [Permissions.fsWriteData],
  );

  late DataFolder _files;
  var _config = const TeleportConfig();
  var _homes = HomeBook();
  var _warps = WarpBook();
  Location? _spawn;

  /// Last seen names of the players with homes, to keep `homes.json` readable.
  final Map<String, String> _names = {};

  late TpaRequests _requests;
  final _cooldowns = Cooldowns();

  @override
  void onLoad(Context context) {
    _files = context.files;
    _loadData();
    _requests = TpaRequests(timeout: _config.requestTimeout);

    _registerPermissions(context);
    _registerHomeCommands(context);
    _registerWarpCommands(context);
    _registerSpawnCommands(context);
    _registerTpaCommands(context);

    context.listen(Events.playerLeave, (server, event) {
      _requests.removeAllFor(_uuidOf(event.player));
    });
    logger.info(
      'Teleport loaded: max ${_config.maxHomes} homes, '
      '${_warps.names.length} warps, '
      '${_spawn == null ? 'no' : 'a'} custom spawn.',
    );
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  /// Reads [file] and decodes it with [decode], or returns `null` if it
  /// doesn't exist or can't be used.
  T? _read<T>(String file, T Function(String json) decode) {
    try {
      return decode(_files.readAsString(file));
    } on FileException catch (e) {
      if (!e.isNotFound) logger.error('Could not read $file: $e');
    } on MapperException catch (e) {
      logger.error('$file is not valid, ignoring it: $e');
    }
    return null;
  }

  void _write(String file, String json) {
    try {
      _files.writeAsString(file, json);
    } on FileException catch (e) {
      logger.error('Could not save $file: $e');
    }
  }

  void _loadData() {
    final config = _read('config.json', TeleportConfigMapper.fromJson);
    if (config == null) {
      _write('config.json', _config.toJson());
    } else {
      _config = config;
    }

    final homes = _read('homes.json', HomesFileMapper.fromJson);
    if (homes != null) {
      _homes = HomeBook.fromFile(homes);
      for (final MapEntry(key: uuid, value: player) in homes.players.entries) {
        _names[uuid] = player.name;
      }
    }
    final warps = _read('warps.json', WarpsFileMapper.fromJson);
    if (warps != null) _warps = WarpBook.fromFile(warps);
    _spawn = _read('spawn.json', LocationMapper.fromJson);
  }

  void _saveHomes() => _write('homes.json', _homes.toFile(_names).toJson());
  void _saveWarps() => _write('warps.json', _warps.toFile().toJson());

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _registerPermissions(Context context) {
    void register(String node, String description, PermissionDefault default_) {
      final result = context.registerPermission(
        permission: Permission(
          node: node,
          description: description,
          default_: default_,
          children: const [],
        ),
      );
      if (result case ErrorResult(:final value)) {
        logger.warn('Could not register $node: $value');
      }
    }

    const allow = PermissionDefaultAllow();
    const op = PermissionDefaultOp(PermissionLevel.two);
    register(Perm.home, 'Teleport to your homes with /home', allow);
    register(Perm.setHome, 'Set homes with /sethome', allow);
    register(Perm.delHome, 'Delete your homes with /delhome', allow);
    register(Perm.homes, 'List your homes with /homes', allow);
    register(Perm.warp, 'Teleport to warps with /warp', allow);
    register(Perm.warps, 'List warps with /warps', allow);
    register(Perm.setWarp, 'Create warps with /setwarp', op);
    register(Perm.delWarp, 'Delete warps with /delwarp', op);
    register(Perm.spawn, 'Teleport to the spawn with /spawn', allow);
    register(Perm.setSpawn, 'Move the spawn with /setspawn', op);
    register(Perm.tpa, 'Request and answer teleports with /tpa', allow);
    register(Perm.bypassCooldown, 'Teleport without waiting', op);
    register(Perm.unlimitedHomes, 'Have more homes than the limit', op);
  }

  void _say(CommandSender sender, String legacyText) {
    sender.sendMessage(text: TextComponent.fromLegacyString(input: legacyText));
  }

  void _tell(Player player, String legacyText) {
    player.sendSystemMessage(
      text: TextComponent.fromLegacyString(input: legacyText),
      overlay: false,
    );
  }

  Player _playerOf(CommandSender sender) =>
      sender.asPlayer() ??
      (throw CommandException('Only players can use this command.'));

  String _uuidOf(Player player) => player.asEntity().getUuid().asString;

  Location _locationOf(Player player) {
    final (x, y, z) = player.getPosition();
    return Location(
      world: player.getWorld().getName(),
      x: x,
      y: y,
      z: z,
      yaw: player.getYaw(),
      pitch: player.getPitch(),
    );
  }

  /// Fails with a message if [player] has to wait before teleporting again.
  void _checkCooldown(CommandSender sender, Server server, Player player) {
    if (_config.cooldown == Duration.zero) return;
    if (sender.hasPermission(server: server, node: Perm.bypassCooldown)) return;
    final left = _cooldowns.remaining(_uuidOf(player), _config.cooldown);
    if (left != null) {
      final seconds = (left.inMilliseconds / 1000).ceil();
      throw CommandException(
        'Wait $seconds more second(s) before teleporting.',
      );
    }
  }

  void _teleport(Server server, Player player, Location target) {
    final world = server.getWorldByName(name: target.world);
    if (world == null) {
      throw CommandException('The world ${target.world} is not loaded.');
    }
    player.teleport(
      position: (target.x, target.y, target.z),
      yaw: target.yaw,
      pitch: target.pitch,
      world: world,
    );
    _cooldowns.mark(_uuidOf(player));
  }

  String _validName(String name) {
    if (!isValidName(name)) {
      throw CommandException(
        'Names can have letters, digits, _ and -, up to 32 characters.',
      );
    }
    return name;
  }

  /// Registers `/names` (optionally with a word argument) as one command.
  void _command(
    Context context, {
    required List<String> names,
    required String description,
    required String permission,
    CommandHandler? run,
    String? argument,
    CommandArgumentType? argumentType,
    CommandHandler? runWithArgument,
    SuggestionHandler? suggest,
  }) {
    final command = Command.create(names: names, description: description);
    if (run != null) command.execute(run);
    if (argument != null) {
      final node = CommandNode.argument(
        name: argument,
        type: argumentType ?? ArgumentTypes.word,
      )..execute(runWithArgument!);
      if (suggest != null) node.suggest(suggest);
      command.then(node: node);
    }
    context.registerCommand(command: command, permission: permission);
  }

  /// Suggestions from [options] that start with what was typed so far.
  SuggestionHandler _suggestions(
    List<String> Function(CommandSender sender) options,
  ) {
    return (sender, server, request) {
      final typed = request.remaining.toLowerCase();
      return CommandSuggestions(
        start: request.start,
        length: request.remaining.length,
        values: [
          for (final option in options(sender))
            if (option.toLowerCase().startsWith(typed))
              CommandCommandSuggestion(value: option, tooltip: null),
        ],
      );
    };
  }

  // ---------------------------------------------------------------------------
  // Homes
  // ---------------------------------------------------------------------------

  List<String> _homeNames(CommandSender sender) {
    final player = sender.asPlayer();
    if (player == null) return const [];
    return _homes.of(_uuidOf(player)).keys.toList()..sort();
  }

  void _registerHomeCommands(Context context) {
    _command(
      context,
      names: ['sethome'],
      description: 'Sets a home at your position',
      permission: Perm.setHome,
      run: (sender, server, args) => _setHome(sender, server, 'home'),
      argument: 'name',
      runWithArgument: (sender, server, args) =>
          _setHome(sender, server, args.string('name')),
    );

    _command(
      context,
      names: ['home'],
      description: 'Teleports you to a home',
      permission: Perm.home,
      run: (sender, server, args) => _goHome(sender, server, null),
      argument: 'name',
      runWithArgument: (sender, server, args) =>
          _goHome(sender, server, args.string('name')),
      suggest: _suggestions(_homeNames),
    );

    _command(
      context,
      names: ['delhome'],
      description: 'Deletes one of your homes',
      permission: Perm.delHome,
      argument: 'name',
      runWithArgument: (sender, server, args) {
        final player = _playerOf(sender);
        final name = args.string('name');
        if (!_homes.remove(_uuidOf(player), name)) {
          throw CommandException('You have no home called $name.');
        }
        _saveHomes();
        _say(sender, '§eDeleted home §f$name§e.');
        return 1;
      },
      suggest: _suggestions(_homeNames),
    );

    _command(
      context,
      names: ['homes'],
      description: 'Lists your homes',
      permission: Perm.homes,
      run: (sender, server, args) {
        final player = _playerOf(sender);
        final homes = _homes.of(_uuidOf(player));
        if (homes.isEmpty) {
          _say(sender, '§eYou have no homes. Set one with /sethome.');
          return 1;
        }
        _say(sender, '§eYour homes (${homes.length}/${_config.maxHomes}):');
        for (final name in homes.keys.toList()..sort()) {
          _say(sender, '§7- §f$name §7(${homes[name]!.describe()})');
        }
        return 1;
      },
    );
  }

  int _setHome(CommandSender sender, Server server, String name) {
    final player = _playerOf(sender);
    final uuid = _uuidOf(player);
    _validName(name);

    final replacing = _homes.has(uuid, name);
    final unlimited = sender.hasPermission(
      server: server,
      node: Perm.unlimitedHomes,
    );
    if (!replacing && !unlimited && _homes.count(uuid) >= _config.maxHomes) {
      throw CommandException(
        'You can only have ${_config.maxHomes} homes. Delete one with /delhome.',
      );
    }

    _homes.set(uuid, name, _locationOf(player));
    _names[uuid] = player.getName();
    _saveHomes();
    _say(sender, '§a${replacing ? 'Moved' : 'Set'} home §f$name§a.');
    return 1;
  }

  int _goHome(CommandSender sender, Server server, String? name) {
    final player = _playerOf(sender);
    final uuid = _uuidOf(player);
    final homes = _homes.of(uuid);
    if (homes.isEmpty) {
      throw CommandException('You have no homes. Set one with /sethome.');
    }

    final String chosen;
    if (name != null) {
      chosen = name;
    } else if (homes.containsKey('home')) {
      chosen = 'home';
    } else if (homes.length == 1) {
      chosen = homes.keys.single;
    } else {
      throw CommandException(
        'Which home? You have: ${(homes.keys.toList()..sort()).join(', ')}',
      );
    }

    final target = _homes.get(uuid, chosen);
    if (target == null) {
      throw CommandException('You have no home called $chosen.');
    }
    _checkCooldown(sender, server, player);
    _teleport(server, player, target);
    _say(sender, '§aTeleported to home §f$chosen§a.');
    return 1;
  }

  // ---------------------------------------------------------------------------
  // Warps
  // ---------------------------------------------------------------------------

  void _registerWarpCommands(Context context) {
    List<String> warpNames(CommandSender sender) => _warps.names;

    _command(
      context,
      names: ['warp'],
      description: 'Teleports you to a warp',
      permission: Perm.warp,
      argument: 'name',
      runWithArgument: (sender, server, args) {
        final player = _playerOf(sender);
        final name = args.string('name');
        final target = _warps.get(name);
        if (target == null)
          throw CommandException('There is no warp called $name.');
        _checkCooldown(sender, server, player);
        _teleport(server, player, target);
        _say(sender, '§aWarped to §f$name§a.');
        return 1;
      },
      suggest: _suggestions(warpNames),
    );

    _command(
      context,
      names: ['warps'],
      description: 'Lists the warps',
      permission: Perm.warps,
      run: (sender, server, args) {
        final names = _warps.names;
        _say(
          sender,
          names.isEmpty
              ? '§eThere are no warps yet.'
              : '§eWarps (${names.length}): §f${names.join('§7, §f')}',
        );
        return 1;
      },
    );

    _command(
      context,
      names: ['setwarp'],
      description: 'Creates or moves a warp at your position',
      permission: Perm.setWarp,
      argument: 'name',
      runWithArgument: (sender, server, args) {
        final player = _playerOf(sender);
        final name = _validName(args.string('name'));
        final replacing = _warps.get(name) != null;
        _warps.set(name, _locationOf(player));
        _saveWarps();
        _say(sender, '§a${replacing ? 'Moved' : 'Created'} warp §f$name§a.');
        return 1;
      },
      suggest: _suggestions(warpNames),
    );

    _command(
      context,
      names: ['delwarp'],
      description: 'Deletes a warp',
      permission: Perm.delWarp,
      argument: 'name',
      runWithArgument: (sender, server, args) {
        final name = args.string('name');
        if (!_warps.remove(name)) {
          throw CommandException('There is no warp called $name.');
        }
        _saveWarps();
        _say(sender, '§eDeleted warp §f$name§e.');
        return 1;
      },
      suggest: _suggestions(warpNames),
    );
  }

  // ---------------------------------------------------------------------------
  // Spawn
  // ---------------------------------------------------------------------------

  void _registerSpawnCommands(Context context) {
    _command(
      context,
      names: ['spawn'],
      description: 'Teleports you to the spawn',
      permission: Perm.spawn,
      run: (sender, server, args) {
        final player = _playerOf(sender);
        _checkCooldown(sender, server, player);
        _teleport(server, player, _spawnLocation(server));
        _say(sender, '§aTeleported to the spawn.');
        return 1;
      },
    );

    _command(
      context,
      names: ['setspawn'],
      description: 'Makes your position the spawn',
      permission: Perm.setSpawn,
      run: (sender, server, args) {
        final player = _playerOf(sender);
        final location = _locationOf(player);
        _spawn = location;
        _write('spawn.json', location.toJson());
        _say(sender, '§aSpawn set to §f${location.describe()}§a.');
        return 1;
      },
    );
  }

  /// The spawn set with /setspawn, or else the overworld's own spawn.
  Location _spawnLocation(Server server) {
    final custom = _spawn;
    if (custom != null) return custom;

    final world =
        server.getWorldByName(name: 'minecraft:overworld') ??
        (server.getAllWorlds().isEmpty
            ? throw CommandException('There is no world to spawn in.')
            : server.getAllWorlds().first);
    final spawn = world.getSpawnLocation();
    return Location(
      world: world.getName(),
      x: spawn.pos.x + 0.5,
      y: spawn.pos.y.toDouble(),
      z: spawn.pos.z + 0.5,
      yaw: spawn.yaw,
      pitch: spawn.pitch,
    );
  }

  // ---------------------------------------------------------------------------
  // Teleport requests
  // ---------------------------------------------------------------------------

  void _registerTpaCommands(Context context) {
    List<String> requesters(CommandSender sender) {
      final player = sender.asPlayer();
      if (player == null) return const [];
      return [for (final r in _requests.incoming(_uuidOf(player))) r.fromName];
    }

    for (final (name, kind, description) in [
      ('tpa', TpaKind.to, 'Asks to teleport to a player'),
      ('tpahere', TpaKind.here, 'Asks a player to teleport to you'),
    ]) {
      _command(
        context,
        names: [name],
        description: description,
        permission: Perm.tpa,
        argument: 'player',
        argumentType: ArgumentTypes.players,
        runWithArgument: (sender, server, args) =>
            _request(sender, server, args.players('player'), kind),
      );
    }

    _command(
      context,
      names: ['tpaccept', 'tpyes'],
      description: 'Accepts a teleport request',
      permission: Perm.tpa,
      run: (sender, server, args) => _accept(sender, server, null),
      argument: 'player',
      runWithArgument: (sender, server, args) =>
          _accept(sender, server, args.string('player')),
      suggest: _suggestions(requesters),
    );

    _command(
      context,
      names: ['tpdeny', 'tpno'],
      description: 'Declines a teleport request',
      permission: Perm.tpa,
      run: (sender, server, args) => _deny(sender, server, null),
      argument: 'player',
      runWithArgument: (sender, server, args) =>
          _deny(sender, server, args.string('player')),
      suggest: _suggestions(requesters),
    );

    _command(
      context,
      names: ['tpcancel'],
      description: 'Cancels your open teleport request',
      permission: Perm.tpa,
      run: (sender, server, args) {
        final player = _playerOf(sender);
        final request = _requests.outgoing(_uuidOf(player));
        if (request == null)
          throw CommandException('You have no open request.');
        _requests.remove(request);
        _say(sender, '§eCancelled your teleport request.');
        return 1;
      },
    );
  }

  int _request(
    CommandSender sender,
    Server server,
    List<Player> targets,
    TpaKind kind,
  ) {
    final player = _playerOf(sender);
    if (targets.isEmpty) throw CommandException('No player found.');
    final target = targets.first;
    final from = _uuidOf(player);
    final to = _uuidOf(target);
    if (from == to) throw CommandException('You can\'t teleport to yourself.');

    _requests.create(
      fromUuid: from,
      fromName: player.getName(),
      toUuid: to,
      kind: kind,
    );
    final seconds = _config.requestTimeout.inSeconds;
    _say(sender, '§aRequest sent to §f${target.getName()}§a.');
    _tell(
      target,
      kind == TpaKind.to
          ? '§f${player.getName()} §ewants to teleport to you.'
          : '§f${player.getName()} §easks you to teleport to them.',
    );
    _tell(
      target,
      '§eType §a/tpaccept §eor §c/tpdeny §e(expires in ${seconds}s).',
    );
    return 1;
  }

  /// The request [sender] answers, or throws.
  TpaRequest _pendingFor(Player player, String? fromName) {
    final request = _requests.pending(_uuidOf(player), fromName: fromName);
    if (request == null) {
      throw CommandException(
        fromName == null
            ? 'You have no teleport requests.'
            : 'You have no request from $fromName.',
      );
    }
    return request;
  }

  int _accept(CommandSender sender, Server server, String? fromName) {
    final player = _playerOf(sender);
    final request = _pendingFor(player, fromName);
    final requester = server.getPlayerByUuid(id: Uuids.parse(request.fromUuid));
    _requests.remove(request);
    if (requester == null) {
      throw CommandException('${request.fromName} is no longer online.');
    }

    // The player who moves is the one who has to wait.
    final mover = request.kind == TpaKind.to ? requester : player;
    final destination = request.kind == TpaKind.to ? player : requester;
    if (!sender.hasPermission(server: server, node: Perm.bypassCooldown)) {
      final left = _cooldowns.remaining(_uuidOf(mover), _config.cooldown);
      if (left != null) {
        _tell(
          requester,
          '§cThe teleport failed: ${mover.getName()} has to wait.',
        );
        throw CommandException(
          '${mover.getName()} has to wait before teleporting.',
        );
      }
    }

    _teleport(server, mover, _locationOf(destination));
    _say(sender, '§aTeleport request accepted.');
    _tell(requester, '§f${player.getName()} §aaccepted your request.');
    return 1;
  }

  int _deny(CommandSender sender, Server server, String? fromName) {
    final player = _playerOf(sender);
    final request = _pendingFor(player, fromName);
    _requests.remove(request);
    _say(sender, '§eDeclined the request from §f${request.fromName}§e.');
    final requester = server.getPlayerByUuid(id: Uuids.parse(request.fromUuid));
    if (requester != null) {
      _tell(requester, '§f${player.getName()} §cdeclined your request.');
    }
    return 1;
  }
}

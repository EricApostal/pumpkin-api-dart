// The `/cc` command: the debug interface to the computers until the real
// client can drive them. It creates computers, powers them, types into them
// and shows their terminals in chat.
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show VanillaRegistries;

import '../machine/computer.dart';
import '../machine/peripherals.dart';
import '../machine/side.dart';
import '../protocol/blocks.dart';
import '../protocol/channels.dart';
import '../protocol/registries.dart';
import 'chat_view.dart';
import 'keys.dart';
import 'network.dart';
import 'records.dart';
import 'service.dart';

abstract final class CcPermissions {
  /// Create and use your own computers.
  static const String use = 'cc_tweaked:command.use';

  /// Use anyone's computers and see server details.
  static const String admin = 'cc_tweaked:command.admin';
}

/// Registers `/cc`.
void registerCommands(Context context, CcService service, CcNetwork network) {
  final commands = _Commands(service, network);
  commands.register(context);
}

final class _Commands {
  final CcService service;
  final CcNetwork network;

  _Commands(this.service, this.network);

  static const List<String> _sides = ['top', 'bottom', 'left', 'right', 'front', 'back'];

  void register(Context context) {
    context.command(
      'cc',
      description: 'CC: Tweaked computers',
      permission: const CommandPermission(CcPermissions.use, description: 'Use /cc'),
      (c) => c
        ..runs(_help)
        ..sub('help', description: 'List the subcommands', runs: _help)
        ..sub(
          'new',
          description: 'Create a computer',
          build: (s) => s.arg(
            'kind',
            ArgumentTypes.oneOf(['normal', 'advanced']),
            optional: true,
            runs: _new,
          ),
        )
        ..sub('list', description: 'List your computers', runs: _list)
        ..sub('info', description: 'Details of a computer', build: (s) => _id(s, _info))
        ..sub('on', description: 'Turn a computer on', build: (s) => _id(s, _on))
        ..sub('off', description: 'Shut a computer down', build: (s) => _id(s, _off))
        ..sub('reboot', description: 'Reboot a computer', build: (s) => _id(s, _reboot))
        ..sub('terminate', description: 'Send Ctrl+T to a computer', build: (s) => _id(s, _terminate))
        ..sub('term', description: 'Show its screen', build: (s) => _id(s, _term))
        ..sub(
          'type',
          description: 'Type text into a computer',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg('text', ArgumentTypes.greedyString, runs: (ctx) => _type(ctx, enter: false)),
          ),
        )
        ..sub(
          'run',
          description: 'Type a line and press enter',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg('text', ArgumentTypes.greedyString, runs: (ctx) => _type(ctx, enter: true)),
          ),
        )
        ..sub(
          'key',
          description: 'Press a key (enter, backspace, up, a, f1, ...)',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg('key', ArgumentTypes.word, runs: _key),
          ),
        )
        ..sub(
          'label',
          description: 'Show or set the label',
          build: (s) => _id(
            s,
            _label,
            build: (a) => a.arg('label', ArgumentTypes.greedyString, runs: _label),
          ),
        )
        ..sub('remove', description: 'Delete a computer and its files', build: (s) => _id(s, _remove))
        ..sub(
          'redstone',
          description: 'Set a redstone input of a computer',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg(
              'side',
              ArgumentTypes.oneOf(_sides),
              build: (b) => b.arg('level', ArgumentTypes.integer(min: 0, max: 15), runs: _redstone),
            ),
          ),
        )
        ..sub(
          'attach',
          description: 'Attach a monitor or modem to a side',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg(
              'side',
              ArgumentTypes.oneOf(_sides),
              build: (b) => b
                ..sub(
                  'monitor',
                  build: (m) => m.arg(
                    'width',
                    ArgumentTypes.integer(min: 1, max: 32),
                    build: (w) => w.arg('height', ArgumentTypes.integer(min: 1, max: 32), runs: _attachMonitor),
                  ),
                )
                ..sub('modem', runs: _attachModem),
            ),
          ),
        )
        ..sub(
          'detach',
          description: 'Detach what is on a side',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg('side', ArgumentTypes.oneOf(_sides), runs: _detach),
          ),
        )
        ..sub(
          'monitor',
          description: 'Show the screen of an attached monitor',
          build: (s) => _id(
            s,
            null,
            build: (a) => a.arg('side', ArgumentTypes.oneOf(_sides), runs: _monitor),
          ),
        )
        ..sub('open', description: 'Open the real CC: Tweaked GUI (needs host support)', build: (s) => _id(s, _open))
        ..sub(
          'status',
          description: 'Server details',
          permission: CommandPermission.op(CcPermissions.admin, description: 'Use every computer and see server details'),
          runs: _status,
        )
        ..sub(
          'registry',
          description: 'What CC adds to the registries',
          permission: const CommandPermission(CcPermissions.admin),
          runs: _registry,
        ),
    );
  }

  /// Adds the `<id>` argument to [node]. [runs] runs for `<command> <id>`.
  void _id(
    CommandBuilder node,
    CommandBody? runs, {
    void Function(CommandBuilder id)? build,
  }) {
    node.arg(
      'id',
      ArgumentTypes.integer(min: 0),
      suggestsWith: (s) => [for (final r in service.records) '${r.id}'],
      runs: runs,
      build: build,
    );
  }

  // -- Helpers ----------------------------------------------------------------

  String _owner(CommandContext ctx) => ctx.isPlayer ? ctx.player.getId().asString : 'console';

  bool _isAdmin(CommandContext ctx) => ctx.hasPermission(CcPermissions.admin);

  Computer _computer(CommandContext ctx) {
    final id = ctx.integer('id');
    final record = service.record(id);
    // A computer in an unloaded chunk has no machine: bring it up for the command.
    final computer = service.computer(id) ?? service.resume(id);
    if (record == null || computer == null) ctx.fail('There is no computer #$id.');
    if (!_isAdmin(ctx) && ctx.isPlayer && record.owner != _owner(ctx)) {
      ctx.fail('Computer #$id belongs to ${record.ownerName}.');
    }
    return computer;
  }

  Computer _runningComputer(CommandContext ctx) {
    final computer = _computer(ctx);
    if (!computer.isOn) ctx.fail('Computer #${computer.id} is off. Turn it on with /cc on ${computer.id}.');
    return computer;
  }

  void _say(CommandContext ctx, String message) => ctx.sender.send(message);

  ComputerSide _side(CommandContext ctx) => ComputerSide.parse(ctx.string('side'))!;

  String _describe(Computer computer) {
    final label = computer.label;
    return '#${computer.id}${label == null ? '' : ' "${MessageFormat.escape(label)}"'}';
  }

  // -- Subcommands ------------------------------------------------------------

  void _help(CommandContext ctx) {
    _say(ctx, '&6CC: Tweaked computers &7(debug interface)');
    for (final line in const [
      '/cc new [normal|advanced] - create a computer',
      '/cc list | info <id> | label <id> [text] | remove <id>',
      '/cc on|off|reboot|terminate <id>',
      '/cc term <id> - show the screen in chat',
      '/cc type <id> <text> | run <id> <text> | key <id> <key>',
      '/cc attach <id> <side> monitor <w> <h> | modem; detach; monitor',
      '/cc redstone <id> <side> <0-15> - set an input',
    ]) {
      _say(ctx, '&e$line');
    }
  }

  void _new(CommandContext ctx) {
    final owner = _owner(ctx);
    final limit = service.pluginConfig.maxComputersPerPlayer;
    if (ctx.isPlayer && limit > 0 && !_isAdmin(ctx) && service.countOwnedBy(owner) >= limit) {
      ctx.fail('You can own at most $limit computers.');
    }
    final family = ctx.stringOrNull('kind') == 'normal' ? ComputerFamily.normal : ComputerFamily.advanced;
    final computer = service.create(family: family, owner: owner, ownerName: ctx.senderName);
    computer.turnOn();
    _say(ctx, '&aCreated ${family.name} computer #${computer.id} and turned it on.');
    _say(ctx, '&7Show its screen with &e/cc term ${computer.id}&7.');
    if (!service.hasRom) {
      _say(ctx, '&7No CC: Tweaked jar found: it runs the minimal built-in BIOS.');
    }
  }

  void _list(CommandContext ctx) {
    final all = service.records
        .where((r) => _isAdmin(ctx) || !ctx.isPlayer || r.owner == _owner(ctx))
        .toList();
    if (all.isEmpty) {
      _say(ctx, '&eNo computers. Create one with /cc new.');
      return;
    }
    for (final record in all) {
      final computer = service.computer(record.id);
      final owner = _isAdmin(ctx) ? ' &7(${record.ownerName})' : '';
      final where = record.location == null ? '' : ' at ${record.location}';
      if (computer == null) {
        _say(ctx, '&f#${record.id}${record.label == null ? '' : ' "${MessageFormat.escape(record.label!)}"'} &7- ${record.family.name}, not loaded$where$owner');
      } else {
        _say(ctx, '&f${_describe(computer)} &7- ${record.family.name}, ${computer.state.name}$where$owner');
      }
    }
  }

  void _info(CommandContext ctx) {
    final computer = _computer(ctx);
    final record = service.record(computer.id)!;
    _say(ctx, '&6Computer ${_describe(computer)}');
    _say(ctx, '&7Family: &f${computer.family.name} &7State: &f${computer.state.name} &7Owner: &f${record.ownerName}');
    final fs = computer.fileSystem;
    if (fs != null) {
      _say(ctx, '&7Disk: &f${fs.freeSpace('')} &7bytes free of &f${fs.capacity('') ?? 0}');
    }
    final attached = [
      for (final side in ComputerSide.values)
        if (computer.peripheralOn(side) case final peripheral?) '${side.luaName}: ${peripheral.type}',
    ];
    if (attached.isNotEmpty) _say(ctx, '&7Peripherals: &f${attached.join(', ')}');
  }

  void _on(CommandContext ctx) {
    final computer = _computer(ctx);
    computer.turnOn();
    _say(ctx, '&aTurning on ${_describe(computer)}.');
  }

  void _off(CommandContext ctx) {
    final computer = _computer(ctx);
    computer.shutdown();
    _say(ctx, '&eShutting down ${_describe(computer)}.');
  }

  void _reboot(CommandContext ctx) {
    final computer = _computer(ctx);
    computer.reboot();
    _say(ctx, '&eRebooting ${_describe(computer)}.');
  }

  void _terminate(CommandContext ctx) {
    _runningComputer(ctx).queueEvent('terminate', const []);
    _say(ctx, '&eSent the terminate event.');
  }

  void _term(CommandContext ctx) {
    final computer = _computer(ctx);
    _say(ctx, '&8--- &7Computer ${_describe(computer)} &8(${computer.state.name}) ---');
    for (final line in renderTerminal(computer.terminal)) {
      _say(ctx, line.isEmpty ? '&r ' : line);
    }
    _say(ctx, '&8---');
  }

  void _type(CommandContext ctx, {required bool enter}) {
    final computer = _runningComputer(ctx);
    final input = computer.createInput();
    for (final unit in ctx.string('text').codeUnits) {
      input.charTyped(unit > 255 ? 63 : unit);
    }
    if (enter) {
      input
        ..keyDown(257)
        ..keyUp(257);
    }
  }

  void _key(CommandContext ctx) {
    final computer = _runningComputer(ctx);
    final name = ctx.string('key');
    final code = keyCodeOf(name);
    if (code == null) ctx.fail('Unknown key "$name".');
    computer.createInput()
      ..keyDown(code)
      ..keyUp(code);
  }

  void _label(CommandContext ctx) {
    final computer = _computer(ctx);
    final text = ctx.stringOrNull('label');
    if (text != null) {
      computer.label = text.isEmpty ? null : text;
      _say(ctx, '&aLabel set.');
    }
    final label = computer.label;
    _say(ctx, label == null ? '&7No label.' : '&7Label: &f${MessageFormat.escape(label)}');
  }

  void _remove(CommandContext ctx) {
    final computer = _computer(ctx);
    final id = computer.id;
    network.close(ctx.isPlayer ? ctx.player.getId().asString : '');
    service.remove(id);
    _say(ctx, '&eRemoved computer #$id and its files.');
  }

  void _redstone(CommandContext ctx) {
    final computer = _computer(ctx);
    final level = ctx.integer('level');
    computer.redstone.setInput(_side(ctx), level, 0);
    _say(ctx, '&aSet the ${ctx.string('side')} input of ${_describe(computer)} to $level.');
  }

  void _attachMonitor(CommandContext ctx) {
    final computer = _computer(ctx);
    service.attach(
      computer.id,
      _side(ctx),
      PeripheralSpec('monitor', width: ctx.integer('width'), height: ctx.integer('height')),
    );
    _say(ctx, '&aAttached a monitor to the ${ctx.string('side')} of ${_describe(computer)}.');
  }

  void _attachModem(CommandContext ctx) {
    final computer = _computer(ctx);
    service.attach(computer.id, _side(ctx), const PeripheralSpec('modem'));
    _say(ctx, '&aAttached a wireless modem to the ${ctx.string('side')} of ${_describe(computer)}.');
  }

  void _detach(CommandContext ctx) {
    final computer = _computer(ctx);
    service.detach(computer.id, _side(ctx));
    _say(ctx, '&eDetached the ${ctx.string('side')} of ${_describe(computer)}.');
  }

  void _monitor(CommandContext ctx) {
    final computer = _computer(ctx);
    final peripheral = service.peripheral(computer.id, _side(ctx));
    if (peripheral is! MonitorPeripheral) {
      ctx.fail('There is no monitor on the ${ctx.string('side')} of that computer.');
    }
    _say(ctx, '&8--- &7Monitor ${ctx.string('side')} of ${_describe(computer)} &8---');
    for (final line in renderTerminal(peripheral.terminal)) {
      _say(ctx, line.isEmpty ? '&r ' : line);
    }
  }

  void _open(CommandContext ctx) {
    final computer = _computer(ctx);
    if (!service.pluginConfig.neoForge) {
      ctx.fail(
        'The CC: Tweaked GUI needs the NeoForge handshake: set "neoforge": true in config.json '
        'and see docs/host-requirements.md for what the server software must support.',
      );
    }
    final int? containerId;
    try {
      containerId = network.open(ctx.player, computer);
    } on PluginRegistryException catch (e) {
      ctx.fail('The host could not open the menu: ${e.message}');
    }
    if (containerId == null) {
      ctx.fail('Your connection did not complete the NeoForge handshake with CC: Tweaked\'s channels, so it cannot show the GUI.');
    }
    _say(ctx, '&aOpened the GUI of ${_describe(computer)} (container $containerId).');
  }

  void _status(CommandContext ctx) {
    final image = service.image;
    _say(ctx, '&6CC: Tweaked server side (cc_tweaked 0.1.0)');
    _say(ctx, '&7OS image: &f${image.source}');
    _say(ctx, '&7Mod version: &f${image.modVersion ?? 'unknown'} &7NeoForge sync: &f${service.pluginConfig.neoForge ? 'enabled' : 'disabled'}');
    final computers = service.manager.computers;
    _say(ctx, '&7Computers: &f${computers.length} &7(on: &f${computers.where((c) => c.isOn).length}&7) Open GUIs: &f${network.sessionCount}');
    final config = service.config;
    _say(
      ctx,
      '&7Slice: &f${config.sliceMicros ~/ 1000}ms&7, tick budget: &f${config.tickBudgetMicros ~/ 1000}ms&7, '
      'timeout: &f${config.timeoutMicros ~/ 1000000}s',
    );
  }

  void _registry(CommandContext ctx) {
    _say(ctx, '&6What CC: Tweaked adds to the registries');
    for (final entry in CcRegistries.additions.entries) {
      final vanilla = VanillaRegistries.require(entry.key).length;
      _say(ctx, '&7${entry.key}: &f$vanilla &7vanilla + &f${entry.value.length} &7(first modded id &f$vanilla&7)');
    }
    _say(ctx, '&7computercraft:recipe_function: &f${CcRegistries.recipeFunctions.length} &7(mod registry)');
    _say(ctx, '&7Datapack registries: &f${CcRegistries.turtleUpgrades.length} &7turtle and &f${CcRegistries.pocketUpgrades.length} &7pocket upgrades');
    final registered = BlockRegistries.host.registeredBlocks;
    _say(
      ctx,
      '&7Block states (client): &f${CcBlockCatalog.totalStates} &7in &f${CcBlockCatalog.all.length} &7blocks; '
      'registered on the host: &f${registered.fold<int>(0, (sum, b) => sum + b.stateCount)} &7in &f${registered.length}',
    );
    _say(ctx, '&7Play channels: &f${CcChannels.serverbound.length} &7serverbound, &f${CcChannels.clientbound.length} &7clientbound');
  }
}

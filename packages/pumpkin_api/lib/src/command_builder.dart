import 'dart:async';
import 'dart:core' as core;
import 'dart:core';

import 'package:wasm_components/wasm_components.dart' show ErrorResult;

import 'bindings.g.dart';
import 'command_context.dart';
import 'command_help.dart';
import 'commands.dart';
import 'logger.dart';

/// A command handler that takes a [CommandContext]. Return nothing (success),
/// or an `int` result code (`return 7;`). May be `async`, see [CommandContext] for the rules
/// about using the context after an `await`.
typedef CommandBody = FutureOr<void> Function(CommandContext ctx);

/// Wraps command handlers: runs before and/or after `next`, or throws a
/// [CommandException] to refuse. See [Guards].
typedef CommandMiddleware =
    FutureOr<int> Function(CommandContext ctx, FutureOr<int> Function() next);

/// Computes tab completions from a [SuggestionContext].
typedef SuggestionSource = Iterable<String> Function(SuggestionContext ctx);

/// The namespace (plugin name) used for the permission node of a command
/// registered without an explicit `permission:`, giving
/// `<namespace>:command.<name>`. Set it once in `onLoad`
/// (`commandNamespace = info.name`), or always pass `permission:`.
String? commandNamespace;

/// Everything the plugin registered through [CommandBuilderContext.command],
/// used by [CommandBuilderContext.registerHelp].
final CommandRegistry commandRegistry = CommandRegistry();

/// A permission node together with how it is registered with the server.
///
/// ```dart
/// const CommandPermission('teleport:command.warp',
///     description: 'Teleport to warps');
/// CommandPermission.op('teleport:command.setwarp',
///     description: 'Create warps');
/// ```
final class CommandPermission {
  /// The full node, `<plugin>:<name>`.
  final String node;

  /// What the permission allows.
  final String description;

  /// Who has the permission when nobody set it explicitly.
  final PermissionDefault default_;

  /// Allowed for [default_] (everyone unless given otherwise).
  const CommandPermission(
    this.node, {
    this.description = '',
    this.default_ = const PermissionDefaultAllow(),
  });

  /// Everyone has it.
  const CommandPermission.everyone(this.node, {this.description = ''})
    : default_ = const PermissionDefaultAllow();

  /// Operators of at least [level] have it (`two` by default, the level of
  /// the game-moderation commands).
  CommandPermission.op(
    this.node, {
    this.description = '',
    PermissionLevel level = PermissionLevel.two,
  }) : default_ = PermissionDefaultOp(level);

  /// Nobody has it unless it is granted explicitly.
  const CommandPermission.deny(this.node, {this.description = ''})
    : default_ = const PermissionDefaultDeny();
}

/// Ready-made [CommandMiddleware]s. Add them with `CommandBuilder.guard`, or
/// the shorthand methods `requirePlayer`, `requirePermission` and `cooldown`.
abstract final class Guards {
  /// Only players may run it.
  static CommandMiddleware requirePlayer() => (ctx, next) {
    if (!ctx.isPlayer) {
      throw CommandException('Only players can use this command.');
    }
    return next();
  };

  /// Only senders with the permission [node] may run it (the console always
  /// may).
  static CommandMiddleware requirePermission(String node) => (ctx, next) {
    if (!ctx.hasPermission(node)) {
      throw CommandException("You don't have permission to do that.");
    }
    return next();
  };

  /// Each sender must wait [duration] between successful runs. The console is
  /// exempt, and so are senders with the permission [bypass].
  ///
  /// A run that fails (throws) doesn't start the cooldown. Pass [tracker] to
  /// share one across commands or to control the clock in tests.
  static CommandMiddleware cooldown(
    Duration duration, {
    String? bypass,
    CooldownTracker? tracker,
  }) {
    final cooldowns = tracker ?? CooldownTracker();
    return (ctx, next) {
      if (ctx.isConsole || (bypass != null && ctx.hasPermission(bypass))) {
        return next();
      }
      final key = ctx.senderName;
      final wait = cooldowns.remaining(key, duration);
      if (wait != null) {
        throw CommandException(
          'Please wait ${formatDuration(wait)} before using this again.',
        );
      }
      cooldowns.mark(key);
      final FutureOr<int> result;
      try {
        result = next();
      } catch (_) {
        cooldowns.clear(key);
        rethrow;
      }
      if (result is Future<int>) {
        return result.then(
          (code) => code,
          onError: (Object error, StackTrace stack) {
            cooldowns.clear(key);
            core.Error.throwWithStackTrace(error, stack);
          },
        );
      }
      return result;
    };
  }
}

/// Applies [middleware] around [body], outermost first. The body's result
/// becomes the command's result code (`int`, else `1`).
///
/// The builder does this for you; it's public to guard handlers you register
/// yourself.
CommandHandler guardedHandler(
  CommandBody body,
  List<CommandMiddleware> middleware, {
  String Function()? usage,
}) {
  return (sender, server, args) {
    final ctx = CommandContext(
      sender: sender,
      server: server,
      args: args,
      usage: usage,
    );
    return runGuarded(ctx, body, middleware);
  };
}

/// Runs [body] for [ctx] inside [middleware].
FutureOr<int> runGuarded(
  CommandContext ctx,
  CommandBody body,
  List<CommandMiddleware> middleware,
) {
  FutureOr<int> run() {
    final Object? result = body(ctx) as Object?;
    if (result is Future) return result.then(_resultCode);
    return _resultCode(result);
  }

  FutureOr<int> at(int index) => index == middleware.length
      ? run()
      : middleware[index](ctx, () => at(index + 1));
  return at(0);
}

int _resultCode(Object? result) => result is int ? result : 1;

/// Builds a command: what it runs, its subcommands and arguments.
///
/// You get one from [CommandBuilderContext.command] (the command itself) and
/// from `sub`/`arg` (a node under it). Use cascades:
///
/// ```dart
/// context.command('home', description: 'Go home', permission: 'teleport:home',
///     (c) => c
///       ..runs((ctx) => goHome(ctx.player, 'home'))               // /home
///       ..arg('name', ArgumentTypes.word, optional: true,          // /home [name]
///           suggestsWith: (s) => homeNames(s.senderName),
///           runs: (ctx) => goHome(ctx.player, ctx.stringOrNull('name') ?? 'home'))
///       ..sub('set', description: 'Save a home', build: (s) => s          // /home set <name>
///         ..arg('name', ArgumentTypes.word, runs: (ctx) => setHome(ctx))));
/// ```
final class CommandBuilder {
  /// The node as plain data, for usage and help text.
  final SpecNode spec;

  final List<CommandPermission> _permissions;
  final List<CommandBuilder> _children = [];
  final List<CommandMiddleware> _middleware = [];
  final ArgType? _type;
  final CommandArgumentType? _wire;
  CommandBody? _body;
  CommandHandler? _raw;
  List<String> _suggestValues = const [];
  SuggestionSource? _suggestSource;

  CommandBuilder._(
    this.spec,
    this._permissions, {
    ArgType? type,
    CommandArgumentType? wire,
  }) : _type = type, // ignore: prefer_initializing_formals
       _wire = wire; // ignore: prefer_initializing_formals

  /// Runs [handler] when the command ends at this node.
  ///
  /// ```dart
  /// c.runs((ctx) => ctx.reply('Hello, ${ctx.senderName}!'));
  /// ```
  void runs(CommandBody handler) {
    _body = handler;
    _raw = null;
    spec.runnable = true;
  }

  /// Like [runs], for a handler in the older `(sender, server, args)` style.
  /// Guards and argument checks still apply.
  void runsRaw(CommandHandler handler) {
    _raw = handler;
    _body = null;
    spec.runnable = true;
  }

  /// Adds the literal subcommand [name], run as `/command name`.
  ///
  /// [aliases] are other words for it. [permission] (a node string or a
  /// [CommandPermission]) is registered and required for this subcommand and
  /// everything under it. [runs] runs when the command ends here, [build]
  /// configures the rest (more subcommands, arguments).
  void sub(
    String name, {
    String? description,
    List<String> aliases = const [],
    Object? permission,
    CommandBody? runs,
    void Function(CommandBuilder sub)? build,
  }) {
    final node = SpecNode(
      name,
      SpecKind.literal,
      description: description,
      aliases: aliases,
    );
    final child = CommandBuilder._(node, _permissions);
    _attach(child, permission, description ?? 'Use /… $name');
    if (runs != null) child.runs(runs);
    build?.call(child);
  }

  /// Adds the argument [name] of [type] (a `CommandArgumentType` from
  /// [ArgumentTypes], or an [ArgType] like [ArgumentTypes.oneOf]).
  ///
  /// With [optional], the command also runs without the argument, using the
  /// same [runs] handler (read it with `ctx.stringOrNull(name)`).
  /// [suggests] is a fixed list for tab completion, [suggestsWith] computes
  /// it per sender. [build] configures what comes after the argument.
  void arg(
    String name,
    Object type, {
    CommandBody? runs,
    List<String>? suggests,
    SuggestionSource? suggestsWith,
    bool optional = false,
    Object? permission,
    void Function(CommandBuilder arg)? build,
  }) {
    final ArgType? richType = type is ArgType ? type : null;
    final wire = switch (type) {
      ArgType(:final wire) => wire,
      CommandArgumentType() => type,
      _ => throw ArgumentError.value(
        type,
        'type',
        'must be a CommandArgumentType or an ArgType',
      ),
    };
    final node = SpecNode(
      name,
      SpecKind.argument,
      label: richType?.label,
      optional: optional,
    );
    final child = CommandBuilder._(
      node,
      _permissions,
      type: richType,
      wire: wire,
    );
    child._suggestValues = [...?richType?.choices, ...?suggests];
    child._suggestSource = suggestsWith;
    _attach(child, permission, 'Use $name');
    if (runs != null) child.runs(runs);
    build?.call(child);
  }

  /// Requires a player (not the console or a command block) for this node and
  /// everything under it.
  void requirePlayer() => _middleware.add(Guards.requirePlayer());

  /// Requires the permission [node] (checked when it runs) for this node and
  /// everything under it. Not registered; see `permission:` on [sub] to also
  /// register it.
  void requirePermission(String node) =>
      _middleware.add(Guards.requirePermission(node));

  /// Rate limits this node and everything under it per sender, see
  /// [Guards.cooldown].
  void cooldown(Duration duration, {String? bypass}) =>
      _middleware.add(Guards.cooldown(duration, bypass: bypass));

  /// Wraps this node's handlers (and those of everything under it) in
  /// [middleware]. Guards declared first are outermost.
  void guard(CommandMiddleware middleware) => _middleware.add(middleware);

  /// Sets what this node is for, shown in help.
  void describe(String description) => spec.description = description;

  /// How the command is used, one line per way to run it. Only complete once
  /// the whole command is built.
  List<String> get usage {
    var root = spec;
    while (root.parent != null) {
      root = root.parent!;
    }
    return usageLines(root, from: spec);
  }

  void _attach(CommandBuilder child, Object? permission, String description) {
    final perm = _toPermission(permission, description);
    if (perm != null) {
      child.spec.permission = perm.node;
      _permissions.add(perm);
      child._middleware.add(Guards.requirePermission(perm.node));
    }
    spec.add(child.spec);
    _children.add(child);
  }

  // -- Building --------------------------------------------------------------

  /// The handler run when the command ends at this node: its own, or that of
  /// an optional argument below it.
  _Runner? _runner(List<CommandMiddleware> chain, List<CommandBuilder> path) {
    if (_body != null || _raw != null) {
      return _Runner(_body, _raw, chain, path);
    }
    for (final child in _children) {
      if (child.spec.optional && child.spec.runnable) {
        // The argument is absent: use its handler, without its own checks.
        return child._runner(chain, path);
      }
    }
    return null;
  }

  /// Marks specs runnable that run through an optional argument, so usage
  /// text is right.
  void _syncSpec() {
    for (final child in _children) {
      child._syncSpec();
    }
    if (!spec.runnable) {
      spec.runnable = _children.any((c) => c.spec.optional && c.spec.runnable);
    }
  }

  CommandNode _node(
    String name,
    List<CommandMiddleware> inherited,
    List<CommandBuilder> parentPath,
  ) {
    final path = [...parentPath, this];
    final chain = [...inherited, ..._middleware];
    final node = spec.kind == SpecKind.argument
        ? CommandNode.argument(name: name, type: _wire!)
        : CommandNode.literal(name: name);
    final runner = _runner(chain, path);
    if (runner != null) {
      node.executeWithHandlerId(
        handlerId: commandHandlers.add(runner.handler(this)),
      );
    }
    if (spec.kind == SpecKind.argument &&
        (_suggestValues.isNotEmpty || _suggestSource != null)) {
      node.suggestWithHandlerId(
        handlerId: suggestionHandlers.add(
          _suggestionHandler(_suggestValues, _suggestSource),
        ),
      );
    }
    for (final child in _children) {
      for (final childName in [child.spec.name, ...child.spec.aliases]) {
        node.then(node: child._node(childName, chain, path));
      }
    }
    return node;
  }
}

/// A handler plus the middleware and argument checks around it.
final class _Runner {
  final CommandBody? body;
  final CommandHandler? raw;
  final List<CommandMiddleware> chain;
  final List<CommandBuilder> path;

  _Runner(this.body, this.raw, this.chain, this.path);

  CommandHandler handler(CommandBuilder owner) {
    final checks = [
      for (final node in path)
        if (node._type?.validate != null)
          (node.spec.name, node._type!.validate!),
    ];
    var root = owner.spec;
    while (root.parent != null) {
      root = root.parent!;
    }
    final raw = this.raw;
    final body = this.body;
    final CommandBody run = raw != null
        ? (ctx) => raw(ctx.sender, ctx.server, ctx.args)
        : body!;
    // Checks run innermost: after the guards, right before the handler.
    CommandBody checked = run;
    if (checks.isNotEmpty) {
      checked = (ctx) {
        for (final (key, validate) in checks) {
          final text = ctx.args.stringOrNull(key);
          if (text != null) ctx.normalize(key, validate(text));
        }
        return run(ctx);
      };
    }
    return guardedHandler(
      checked,
      chain,
      usage: () => usageLines(root, from: owner.spec).join('\n'),
    );
  }
}

SuggestionHandler _suggestionHandler(
  List<String> fixed,
  SuggestionSource? source,
) {
  return (sender, server, request) {
    final ctx = SuggestionContext(
      sender: sender,
      server: server,
      request: request,
    );
    final matches = filterSuggestions([
      ...fixed,
      ...?source?.call(ctx),
    ], request.remaining);
    return CommandSuggestions(
      start: request.start,
      length: request.remaining.length,
      values: [
        for (final value in matches)
          CommandCommandSuggestion(value: value, tooltip: null),
      ],
    );
  };
}

CommandPermission? _toPermission(Object? permission, String description) {
  return switch (permission) {
    null => null,
    CommandPermission() => permission,
    String() => CommandPermission(permission, description: description),
    _ => throw ArgumentError.value(
      permission,
      'permission',
      'must be a node String or a CommandPermission',
    ),
  };
}

final Set<String> _registeredPermissions = {};

/// Builder-based registration of commands, permissions and help.
extension CommandBuilderContext on Context {
  /// Registers the command [name] (with [aliases]) and its permission.
  ///
  /// [permission] is a node like `'teleport:command.home'` (allowed for
  /// everyone) or a [CommandPermission] with a description and a default
  /// (`CommandPermission.op(...)` for operators only). The permission is
  /// registered with the server, an "already registered" error is logged as a
  /// warning. Without [permission], the node is `<commandNamespace>:command.<name>`
  /// and [commandNamespace] must be set.
  ///
  /// [build] describes what the command does, see [CommandBuilder]. The
  /// command is listed by [registerHelp] unless [help] is `false`.
  ///
  /// ```dart
  /// context.command('warp', description: 'Teleport to a warp',
  ///     permission: 'teleport:command.warp',
  ///     (c) => c
  ///       ..arg('name', ArgumentTypes.word,
  ///           suggestsWith: (s) => warpNames, runs: (ctx) => go(ctx))
  ///       ..sub('set', permission: CommandPermission.op(
  ///             'teleport:command.setwarp', description: 'Create warps'),
  ///           build: (s) => s..arg('name', ArgumentTypes.word, runs: setWarp)));
  /// ```
  void command(
    String name,
    void Function(CommandBuilder c) build, {
    String description = '',
    List<String> aliases = const [],
    Object? permission,
    bool help = true,
  }) {
    final perm =
        _toPermission(permission, 'Use /$name') ??
        _defaultPermission(name, description);
    final root = SpecNode(
      name,
      SpecKind.root,
      description: description,
      aliases: aliases,
      permission: perm.node,
    );
    final permissions = <CommandPermission>[perm];
    final builder = CommandBuilder._(root, permissions);
    build(builder);
    builder._syncSpec();

    for (final p in permissions) {
      registerCommandPermission(p);
    }
    final command = Command.create(
      names: [name, ...aliases],
      description: description,
    );
    final runner = builder._runner(builder._middleware, [builder]);
    if (runner != null) {
      command.executeWithHandlerId(
        handlerId: commandHandlers.add(runner.handler(builder)),
      );
    }
    for (final child in builder._children) {
      for (final childName in [child.spec.name, ...child.spec.aliases]) {
        command.then(
          node: child._node(childName, builder._middleware, [builder]),
        );
      }
    }
    registerCommand(command: command, permission: perm.node);
    if (help) commandRegistry.add(root);
  }

  /// Registers [permission] with the server. Already registered nodes only
  /// log a warning. Returns whether it is registered now.
  bool registerCommandPermission(CommandPermission permission) {
    if (!permission.node.contains(':')) {
      logger.warn(
        'Permission "${permission.node}" is not registered: nodes must look '
        'like <plugin>:<name>.',
      );
      return false;
    }
    if (!_registeredPermissions.add(permission.node)) return true;
    final result = registerPermission(
      permission: Permission(
        node: permission.node,
        description: permission.description,
        default_: permission.default_,
        children: const [],
      ),
    );
    if (result case ErrorResult(:final value)) {
      logger.warn('Could not register permission ${permission.node}: $value');
      return false;
    }
    return true;
  }

  /// Registers `/<name>` (and `/<name> help [command]`) listing the commands
  /// registered through [command], each with its usage and description. Only
  /// lines the sender may use are shown.
  ///
  /// Call it after the commands it should list.
  ///
  /// ```dart
  /// context.registerHelp('teleport', aliases: ['tp'],
  ///     permission: 'teleport:command.help');
  /// ```
  void registerHelp(
    String name, {
    String description = 'Lists the commands of this plugin',
    List<String> aliases = const [],
    Object? permission,
    String? title,
  }) {
    FutureOr<void> show(CommandContext ctx) {
      final wanted = ctx.stringOrNull('command');
      final lines = helpLines(
        commandRegistry,
        command: wanted,
        hidden: {name, ...aliases},
        canUse: (nodes) => nodes.every(
          (node) => !node.contains(':') || ctx.hasPermission(node),
        ),
      );
      if (lines.isEmpty) {
        ctx.reply(
          wanted == null ? 'No commands.' : 'No command called "$wanted".',
        );
      } else {
        ctx.reply(title ?? 'Commands:');
        ctx.replyLines(lines);
      }
    }

    command(
      name,
      description: description,
      aliases: aliases,
      permission: permission,
      help: false,
      (c) => c
        ..runs(show)
        ..sub(
          'help',
          description: description,
          runs: show,
          build: (h) => h.arg(
            'command',
            ArgumentTypes.word,
            optional: true,
            runs: show,
            suggestsWith: (_) => [
              for (final root in commandRegistry.roots) root.name,
            ],
          ),
        ),
    );
  }
}

CommandPermission _defaultPermission(String name, String description) {
  final namespace = commandNamespace;
  if (namespace == null) {
    throw ArgumentError(
      'Command "$name" has no permission: pass permission: or set '
      'commandNamespace once in onLoad.',
    );
  }
  return CommandPermission(
    '$namespace:command.$name',
    description: description.isEmpty ? 'Use /$name' : 'Use /$name: $description',
  );
}

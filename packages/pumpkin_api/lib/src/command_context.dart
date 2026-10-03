import 'bindings.g.dart';
import 'command_help.dart';
import 'commands.dart';

/// Everything a command handler needs: who ran it, the server, and the typed
/// arguments.
///
/// ```dart
/// context.command('heal', description: 'Heal a player', (c) => c
///   ..runs((ctx) => ctx.player.setHealth(20))
///   ..arg('target', ArgumentTypes.player, runs: (ctx) {
///     for (final p in ctx.players('target')) {
///       p.setHealth(20);
///     }
///     ctx.reply('Healed.');
///   }));
/// ```
///
/// Like [sender] and [server], the context is only valid until the handler
/// first yields (before its first `await`): read what you need from it first.
final class CommandContext {
  /// Who ran the command: a player, the console, a command block, ...
  final CommandSender sender;

  /// The server the command ran on.
  final Server server;

  /// The raw arguments, for argument types the typed accessors don't cover.
  final ConsumedArgs args;

  final String Function()? _usage;

  /// Values replaced after validation, e.g. a choice spelled as declared.
  final Map<String, String> _normalized = {};

  Player? _player;

  CommandContext({
    required this.sender,
    required this.server,
    required this.args,
    String Function()? usage,
  }) : _usage = usage; // ignore: prefer_initializing_formals

  // -- Sender ----------------------------------------------------------------

  /// The name of the sender (`Server` for the console).
  String get senderName => sender.getName();

  /// Whether a player ran the command.
  bool get isPlayer => sender.isPlayer();

  /// Whether the console ran the command.
  bool get isConsole => sender.isConsole();

  /// The player who ran the command.
  ///
  /// Throws `CommandException('Only players can use this command.')` for any
  /// other sender. The handle is owned by this callback, don't keep it past
  /// the handler's first `await` (use `keep()` or store the UUID instead).
  Player get player {
    return _player ??=
        sender.asPlayer() ??
        (throw CommandException('Only players can use this command.'));
  }

  /// The player who ran the command, or `null` for other senders.
  Player? get playerOrNull => isPlayer ? player : null;

  /// Whether the sender has the permission [node]. The console always does.
  bool hasPermission(String node) =>
      sender.hasPermission(server: server, node: node);

  // -- Replies ---------------------------------------------------------------

  /// Sends [message] back to the sender.
  void reply(String message) => sender.reply(message);

  /// Sends each of [lines] as its own message.
  void replyLines(Iterable<String> lines) {
    for (final line in lines) {
      sender.reply(line);
    }
  }

  /// Sends [message] back as an error (red, without failing the command).
  void replyError(String message) =>
      sender.sendError(text: TextComponent.text(plain: message));

  /// Fails the command with [message]. Never returns.
  Never fail(String message) => throw CommandException(message);

  /// How the command is used, one line per way to run it, e.g. `/home [name]`.
  /// Empty when the context wasn't made by the command builder.
  String get usage => _usage == null ? '' : _usage();

  /// Fails the command with its usage, optionally saying what [problem] was
  /// wrong. Never returns.
  ///
  /// ```dart
  /// if (amount <= 0) ctx.failUsage('The amount must be positive.');
  /// ```
  Never failUsage([String? problem]) {
    final text = _usage == null ? '' : _usage();
    throw UsageException(
      text.isEmpty ? const [] : text.split('\n'),
      problem,
    );
  }

  // -- Arguments -------------------------------------------------------------

  /// A text, word or choice argument. Fails the command if it is missing.
  String string(String key) =>
      stringOrNull(key) ??
      (throw CommandException('Argument "$key" is missing.'));

  /// A text argument, or `null` if it wasn't typed.
  String? stringOrNull(String key) =>
      _normalized[key] ?? args.stringOrNull(key);

  /// A whole number argument.
  int integer(String key) => args.integer(key);

  /// A whole number argument, or `null` if it wasn't typed.
  int? integerOrNull(String key) => args.integerOrNull(key);

  /// A decimal number argument (whole numbers work too).
  double number(String key) => args.number(key);

  /// A decimal number argument, or `null` if it wasn't typed.
  double? numberOrNull(String key) => args.numberOrNull(key);

  /// A `true`/`false` argument.
  bool boolean(String key) => args.boolean(key);

  /// A `true`/`false` argument, or `null` if it wasn't typed.
  bool? booleanOrNull(String key) => args.booleanOrNull(key);

  /// A block position argument.
  BlockPos blockPos(String key) => args.blockPos(key);

  /// A block position argument, or `null` if it wasn't typed.
  BlockPos? blockPosOrNull(String key) => args.blockPosOrNull(key);

  /// A duration argument ([ArgumentTypes.duration]): `10s`, `5m`, `1h30m`.
  Duration duration(String key) => parseDurationOrThrow(string(key));

  /// A duration argument, or `null` if it wasn't typed.
  Duration? durationOrNull(String key) {
    final text = stringOrNull(key);
    return text == null ? null : parseDurationOrThrow(text);
  }

  /// The players matched by a player argument. May be empty, see
  /// [targetPlayers] to fail then.
  List<Player> players(String key) => args.players(key);

  /// The players matched by a player argument, or `null` if it wasn't typed.
  List<Player>? playersOrNull(String key) => args.playersOrNull(key);

  /// The players matched by a player argument, failing with
  /// `No player was found.` when none match.
  List<Player> targetPlayers(String key) {
    final found = players(key);
    if (found.isEmpty) throw CommandException('No player was found.');
    return found;
  }

  /// The single player matched by a player argument ([ArgumentTypes.player]).
  /// Fails when none, or more than one, match.
  Player targetPlayer(String key) {
    final found = targetPlayers(key);
    if (found.length > 1) {
      throw CommandException('Only one player is allowed, but several matched.');
    }
    return found.single;
  }

  /// Like [targetPlayer], or `null` if the argument wasn't typed.
  Player? targetPlayerOrNull(String key) {
    final found = playersOrNull(key);
    if (found == null) return null;
    if (found.isEmpty) throw CommandException('No player was found.');
    if (found.length > 1) {
      throw CommandException('Only one player is allowed, but several matched.');
    }
    return found.single;
  }

  /// Records the checked form of the argument [key], read by [string]. Used by
  /// the builder; not needed in handlers.
  void normalize(String key, String value) => _normalized[key] = value;
}

/// What a suggestion callback gets when the sender presses Tab.
///
/// ```dart
/// c.arg('home', ArgumentTypes.word,
///     suggestsWith: (s) => homesOf(s.senderName));
/// ```
final class SuggestionContext {
  final CommandSender sender;
  final Server server;

  /// The raw request from the host: the whole input and the cursor.
  final SuggestionRequest request;

  const SuggestionContext({
    required this.sender,
    required this.server,
    required this.request,
  });

  /// What was typed so far for the argument being completed.
  String get typed => request.remaining;

  /// The name of the sender.
  String get senderName => sender.getName();

  /// Whether a player is typing.
  bool get isPlayer => sender.isPlayer();

  /// The player typing, or `null` for other senders. The handle is only valid
  /// during the callback.
  Player? get player => sender.asPlayer();

  /// Whether the sender has the permission [node].
  bool hasPermission(String node) =>
      sender.hasPermission(server: server, node: node);
}

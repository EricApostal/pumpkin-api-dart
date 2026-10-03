import 'dart:async';

import 'package:wasm_components/wasm_components.dart' show OkResult;

import 'bindings.g.dart';
import 'command_help.dart';
import 'registry.dart';

export 'command_help.dart' show CommandException, UsageException;

/// Runs when a command is executed. Return the command's result code, `1`
/// for success by convention, or throw a [CommandException] to report a
/// failure to the sender.
///
/// The handler may be `async`. The server can't wait for it though, so a
/// handler that is still running after its first `await` reports success
/// right away, and any error it hits later is logged. Don't use [sender] or
/// [server] after an `await`: they are only valid until the handler first
/// yields.
typedef CommandHandler =
    FutureOr<int> Function(
      CommandSender sender,
      Server server,
      ConsumedArgs args,
    );

/// Computes tab completions for an argument.
typedef SuggestionHandler =
    CommandSuggestions Function(
      CommandSender sender,
      Server server,
      SuggestionRequest request,
    );

final commandHandlers = HandlerRegistry<CommandHandler>();
final suggestionHandlers = HandlerRegistry<SuggestionHandler>();

/// An argument type that carries more than the wire type: a label for usage
/// text, fixed choices for tab completion and a check of what was typed.
///
/// Made by [ArgumentTypes.oneOf] and [ArgumentTypes.duration]. Pass it to
/// `CommandBuilder.arg` (the raw `CommandNode.argument` only takes a plain
/// `CommandArgumentType`, use [wire] there).
final class ArgType {
  /// What the host parses.
  final CommandArgumentType wire;

  /// Replaces the argument name in usage text, e.g. `red|green`.
  final String? label;

  /// Values offered by tab completion.
  final List<String> choices;

  /// Checks the raw text before the handler runs. Returns the text to use
  /// (e.g. normalized case) or throws a [CommandException].
  final String Function(String raw)? validate;

  const ArgType(
    this.wire, {
    this.label,
    this.choices = const [],
    this.validate,
  });
}

/// Shortcuts for the argument types of a command.
abstract final class ArgumentTypes {
  /// A single word, without spaces.
  static const word = CommandArgumentTypeString(StringType.singleWord);

  /// A word, or text in quotes.
  static const string = CommandArgumentTypeString(StringType.quotable);

  /// All the remaining text of the command.
  static const greedyString = CommandArgumentTypeString(StringType.greedy);

  static const boolean = CommandArgumentTypeBool();

  /// One or more online players, matched by name or selector.
  static const players = CommandArgumentTypePlayers();

  static const blockPos = CommandArgumentTypeBlockPos();

  /// A whole number, optionally limited to `[min, max]`.
  static CommandArgumentType integer({int? min, int? max}) =>
      CommandArgumentTypeInteger((min, max));

  /// A decimal number, optionally limited to `[min, max]`.
  static CommandArgumentType number({double? min, double? max}) =>
      CommandArgumentTypeDouble((min, max));

  /// One online player (or a selector like `@p`). Read it with
  /// `CommandContext.targetPlayer`; `players` is the same host type, for
  /// commands that accept several.
  static const player = CommandArgumentTypePlayers();

  /// One of [choices], matched ignoring case. Tab completion offers the
  /// choices, anything else is rejected with a message that lists them.
  /// `CommandContext.string` returns the choice spelled as in [choices].
  ///
  /// ```dart
  /// c.arg('mode', ArgumentTypes.oneOf(['survival', 'creative']),
  ///     runs: (ctx) => ctx.reply('Mode: ${ctx.string('mode')}'));
  /// ```
  static ArgType oneOf(List<String> choices) => ArgType(
    word,
    label: choices.length <= 6 ? choices.join('|') : null,
    choices: List.unmodifiable(choices),
    validate: (raw) => matchChoice(raw, choices),
  );

  /// One of the values of an enum, by name: `ArgumentTypes.enumValues(GameMode.values)`.
  static ArgType enumValues(List<Enum> values) =>
      oneOf([for (final value in values) value.name]);

  /// A duration word like `10s`, `5m`, `1h30m`, see [parseDuration]. Read it
  /// with `CommandContext.duration`.
  static final ArgType duration = ArgType(
    word,
    label: 'duration',
    choices: const ['10s', '30s', '1m', '5m', '10m', '1h', '1d'],
    validate: (raw) {
      parseDurationOrThrow(raw);
      return raw;
    },
  );
}

extension CommandExecute on Command {
  /// Runs [handler] when the command is executed without further arguments.
  void execute(CommandHandler handler) {
    executeWithHandlerId(handlerId: commandHandlers.add(handler));
  }
}

extension CommandNodeExecute on CommandNode {
  /// Runs [handler] when this node is the last one in the executed command.
  void execute(CommandHandler handler) {
    executeWithHandlerId(handlerId: commandHandlers.add(handler));
  }

  /// Provides tab completions for this argument.
  void suggest(SuggestionHandler handler) {
    suggestWithHandlerId(handlerId: suggestionHandlers.add(handler));
  }
}

extension CommandSenderApi on CommandSender {
  /// Sends a plain text message back to whoever ran the command.
  void reply(String message) {
    sendMessage(text: TextComponent.text(plain: message));
  }
}

/// Typed access to the arguments of an executed command. Looking up an
/// argument that is missing or of a different type fails the command with a
/// [CommandException].
extension ConsumedArgsApi on ConsumedArgs {
  Arg operator [](String key) => getValue(key: key);

  String string(String key) => switch (this[key]) {
    ArgSimple(:final value) => value,
    ArgMsg(:final value) => value,
    _ => throw _wrongType(key, 'text'),
  };

  bool boolean(String key) => switch (this[key]) {
    ArgBool(:final value) => value,
    _ => throw _wrongType(key, 'a boolean'),
  };

  int integer(String key) => switch (this[key]) {
    ArgNum(value: OkResult(value: NumberInt32(:final value))) => value,
    ArgNum(value: OkResult(value: NumberInt64(:final value))) => value,
    _ => throw _wrongType(key, 'an integer'),
  };

  double number(String key) => switch (this[key]) {
    ArgNum(value: OkResult(value: NumberFloat64(:final value))) => value,
    ArgNum(value: OkResult(value: NumberFloat32(:final value))) => value,
    ArgNum(value: OkResult(value: NumberInt32(:final value))) => value + 0.0,
    ArgNum(value: OkResult(value: NumberInt64(:final value))) => value + 0.0,
    _ => throw _wrongType(key, 'a number'),
  };

  List<Player> players(String key) => switch (this[key]) {
    ArgPlayers(:final value) => value,
    _ => throw _wrongType(key, 'a player selector'),
  };

  BlockPos blockPos(String key) => switch (this[key]) {
    ArgBlockPos(:final value) => value,
    _ => throw _wrongType(key, 'a block position'),
  };

  /// Like [string], or `null` when the argument wasn't typed. (The host
  /// reports an argument that is missing as empty text.)
  String? stringOrNull(String key) => switch (this[key]) {
    ArgSimple(:final value) => value.isEmpty ? null : value,
    ArgMsg(:final value) => value.isEmpty ? null : value,
    _ => null,
  };

  /// Like [boolean], or `null` when it wasn't typed.
  bool? booleanOrNull(String key) => switch (this[key]) {
    ArgBool(:final value) => value,
    _ => null,
  };

  /// Like [integer], or `null` when it wasn't typed.
  int? integerOrNull(String key) => switch (this[key]) {
    ArgNum(value: OkResult(value: NumberInt32(:final value))) => value,
    ArgNum(value: OkResult(value: NumberInt64(:final value))) => value,
    _ => null,
  };

  /// Like [number], or `null` when it wasn't typed.
  double? numberOrNull(String key) => switch (this[key]) {
    ArgNum(value: OkResult(value: NumberFloat64(:final value))) => value,
    ArgNum(value: OkResult(value: NumberFloat32(:final value))) => value,
    ArgNum(value: OkResult(value: NumberInt32(:final value))) => value + 0.0,
    ArgNum(value: OkResult(value: NumberInt64(:final value))) => value + 0.0,
    _ => null,
  };

  /// Like [players], or `null` when it wasn't typed.
  List<Player>? playersOrNull(String key) => switch (this[key]) {
    ArgPlayers(:final value) => value,
    _ => null,
  };

  /// Like [blockPos], or `null` when it wasn't typed.
  BlockPos? blockPosOrNull(String key) => switch (this[key]) {
    ArgBlockPos(:final value) => value,
    _ => null,
  };

  static CommandException _wrongType(String key, String expected) =>
      CommandException('Argument "$key" is missing or is not $expected');
}

/// Maps an exception thrown by a command handler to the error reported to the
/// host.
CommandError commandErrorFor(Object error) {
  final message = error is CommandException ? error.message : '$error';
  return CommandErrorCommandFailed(TextComponent.text(plain: message));
}

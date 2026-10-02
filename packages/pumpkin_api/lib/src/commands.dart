import 'package:wasm_components/wasm_components.dart' show Option, OkResult;

import 'bindings.g.dart';
import 'registry.dart';

/// Runs when a command is executed. Return the command's result code, `1`
/// for success by convention, or throw a [CommandException] to report a
/// failure to the sender.
typedef CommandHandler =
    int Function(CommandSender sender, Server server, ConsumedArgs args);

/// Computes tab completions for an argument.
typedef SuggestionHandler =
    CommandSuggestions Function(
      CommandSender sender,
      Server server,
      SuggestionRequest request,
    );

final commandHandlers = HandlerRegistry<CommandHandler>();
final suggestionHandlers = HandlerRegistry<SuggestionHandler>();

/// Thrown from a [CommandHandler] to tell the sender the command failed.
final class CommandException implements Exception {
  final String message;

  CommandException(this.message);

  @override
  String toString() => 'CommandException: $message';
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
      CommandArgumentTypeInteger((_option(min), _option(max)));

  /// A decimal number, optionally limited to `[min, max]`.
  static CommandArgumentType number({double? min, double? max}) =>
      CommandArgumentTypeDouble((_option(min), _option(max)));

  static Option<T> _option<T>(T? value) =>
      value == null ? Option.none : Option.some(value);
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

  static CommandException _wrongType(String key, String expected) =>
      CommandException('Argument "$key" is missing or is not $expected');
}

/// Maps an exception thrown by a command handler to the error reported to the
/// host.
CommandError commandErrorFor(Object error) {
  final message = error is CommandException ? error.message : '$error';
  return CommandErrorCommandFailed(TextComponent.text(plain: message));
}

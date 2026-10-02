import 'package:pumpkin_api/pumpkin_api.dart';

const _permissionNode = 'hello_plugin:command.hello';

/// Handler ids routed back to us through `handleCommand` / `handleTask`.
const _handlerBare = 0;
const _handlerWithMessage = 1;
const _taskStartup = 100;

void _log(String message) {
  logging.log(level: Level.info, message: message);
}

void main() => runPlugin(HelloPlugin());

final class HelloPlugin extends Plugin {
  @override
  PluginMetadata get metadata => const PluginMetadata(
    name: 'hello_plugin',
    version: '0.1.0',
    authors: ['Eric'],
    description: 'Example plugin: a /hello command, a permission and a task.',
    dependencies: [],
    permissions: [],
  );

  @override
  Result<void, String> onLoad(Context context) {
    _log('Hello plugin loading...');

    final registered = context.registerPermission(
      permission: const Permission(
        node: _permissionNode,
        description: 'Allows running /hello',
        default_: PermissionDefaultAllow(),
        children: [],
      ),
    );
    if (registered case ErrorResult(:final value)) {
      return Result.error('failed to register permission: $value');
    }

    // /hello [message...]
    final message = CommandNode.argument(
      name: 'message',
      type: const CommandArgumentTypeString(StringType.greedy),
    );
    message.executeWithHandlerId(handlerId: _handlerWithMessage);

    final command = Command.create(
      names: ['hello'],
      description: 'Says hello from the Dart plugin',
    );
    command.executeWithHandlerId(handlerId: _handlerBare);
    command.then(node: message);
    context.registerCommand(command: command, permission: _permissionNode);

    final taskId = scheduler.scheduleDelayedTask(
      handlerId: _taskStartup,
      delayTicks: 100, // ~5 seconds
    );

    _log('Registered /hello; scheduled startup task #$taskId');
    return const Result.ok(null);
  }

  @override
  Result<void, String> onUnload(Context context) {
    _log('Hello plugin unloading.');
    return const Result.ok(null);
  }

  @override
  Result<int, CommandError> handleCommand(
    int commandId,
    CommandSender sender,
    Server server,
    ConsumedArgs args,
  ) {
    switch (commandId) {
      case _handlerBare:
        sender.sendMessage(
          text: TextComponent.text(
            plain:
                'Hello ${sender.getName()} from Dart! '
                '${server.getPlayerCount()} player(s) online. '
                'Try /hello <message>.',
          ),
        );
        return const Result.ok(1);
      case _handlerWithMessage:
        final value = switch (args.getValue(key: 'message')) {
          ArgSimple(:final value) => value,
          ArgMsg(:final value) => value,
          final other => '<unexpected argument: $other>',
        };
        sender.sendMessage(
          text: TextComponent.text(plain: 'Dart echoes: $value'),
        );
        return const Result.ok(1);
    }
    return const Result.error(CommandErrorInvalidRequirement());
  }

  @override
  void handleTask(int handlerId, Server server) {
    if (handlerId == _taskStartup) {
      _log('Scheduled task fired ~5s after load.');
    }
  }
}

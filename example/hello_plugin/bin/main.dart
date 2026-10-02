import 'package:pumpkin_api/pumpkin_api.dart';

const _permission = 'hello_plugin:command.hello';

void main() => runPlugin(HelloPlugin());

final class HelloPlugin extends Plugin {
  @override
  PluginInfo get info => const PluginInfo(
    name: 'hello_plugin',
    version: '0.1.0',
    authors: ['Eric'],
    description: 'Example plugin: a /hello command, events and a task.',
  );

  @override
  void onLoad(Context context) {
    logger.info('Hello plugin loading...');

    final registered = context.registerPermission(
      permission: const Permission(
        node: _permission,
        description: 'Allows running /hello',
        default_: PermissionDefaultAllow(),
        children: [],
      ),
    );
    if (registered case ErrorResult(:final value)) {
      throw StateError('failed to register permission: $value');
    }

    // /hello             -> greets the sender
    // /hello <message>   -> echoes the message
    final command = Command.create(
      names: ['hello'],
      description: 'Says hello from the Dart plugin',
    )..execute(_greet);

    final message = CommandNode.argument(
      name: 'message',
      type: ArgumentTypes.greedyString,
    )..execute(_echo);
    command.then(node: message);

    context.registerCommand(command: command, permission: _permission);

    // Greet players as they join.
    context.listen(Events.playerJoin, (server, event) {
      logger.info('${event.player.getName()} joined the server');
    });

    // Runs once, five seconds (100 ticks) after the plugin loads.
    context.runLater(100, (server) {
      logger.info('${server.getPlayerCount()} player(s) online.');
    });
  }

  int _greet(CommandSender sender, Server server, ConsumedArgs args) {
    sender.reply(
      'Hello ${sender.getName()} from Dart! '
      '${server.getPlayerCount()} player(s) online. Try /hello <message>.',
    );
    return 1;
  }

  int _echo(CommandSender sender, Server server, ConsumedArgs args) {
    final message = args.string('message');
    if (message.trim().isEmpty) throw CommandException('Say something!');
    sender.reply('Dart echoes: $message');
    return 1;
  }

  @override
  void onUnload(Context context) => logger.info('Hello plugin unloading.');
}

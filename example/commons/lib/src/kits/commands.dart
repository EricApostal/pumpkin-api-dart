import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/permissions.dart';
import '../core/storage.dart';
import 'inventory.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';
import 'ui.dart';

/// The permission of a command, registered with the node's default.
CommandPermission _commandPermission(PermNode node) =>
    switch (node.defaultFor) {
      PermDefault.everyone => CommandPermission(
        node.node,
        description: node.description,
      ),
      PermDefault.op => CommandPermission.op(
        node.node,
        description: node.description,
      ),
      PermDefault.nobody => CommandPermission.deny(
        node.node,
        description: node.description,
      ),
    };

/// Registers `/kit`: the menu, `/kit <name>`, `/kit preview|list <name>` and
/// the admin subcommands `create`, `delete` and `reload`.
///
/// [onKitsChanged] runs after the set of kits changed (create, delete,
/// reload); the module uses it to register the permissions of new kits.
void registerKitCommands(
  Context context, {
  required KitService kits,
  required KitsUi ui,
  required KitTexts texts,
  required StorageBackend backend,
  required void Function() onKitsChanged,
  required Logger log,
}) {
  final commands = _KitCommands(kits, ui, texts, backend, onKitsChanged, log);
  commands.register(context);
}

final class _KitCommands {
  final KitService kits;
  final KitsUi ui;
  final KitTexts texts;
  final StorageBackend backend;
  final void Function() onKitsChanged;
  final Logger log;

  _KitCommands(
    this.kits,
    this.ui,
    this.texts,
    this.backend,
    this.onKitsChanged,
    this.log,
  );

  /// The kits [s]'s sender may claim, for tab completion.
  Iterable<String> _claimable(SuggestionContext s) => [
    for (final kit in kits.kits)
      if (s.hasPermission(kit.permission)) kit.name,
  ];

  Iterable<String> _all(SuggestionContext _) => [
    for (final k in kits.kits) k.name,
  ];

  void register(Context context) {
    context.command(
      'kit',
      description: 'Open the kit menu or claim a kit',
      aliases: ['kits'],
      permission: _commandPermission(KitPerms.use),
      (c) => c
        ..runs(_openMenu)
        ..sub('list', description: 'List the kits and their state', runs: _list)
        ..sub(
          'preview',
          description: 'Look into a kit without claiming it',
          build: (s) => s.arg(
            'name',
            ArgumentTypes.word,
            suggestsWith: _all,
            runs: _preview,
          ),
        )
        ..sub(
          'create',
          description: 'Save the items in your inventory as a kit',
          permission: _commandPermission(KitPerms.admin),
          build: (s) => s.arg('name', ArgumentTypes.word, runs: _create),
        )
        ..sub(
          'delete',
          description: 'Delete a kit',
          permission: _commandPermission(KitPerms.admin),
          build: (s) => s.arg(
            'name',
            ArgumentTypes.word,
            suggestsWith: _all,
            runs: _delete,
          ),
        )
        ..sub(
          'reload',
          description: 'Reload the kit files',
          permission: _commandPermission(KitPerms.admin),
          runs: _reload,
        )
        ..arg(
          'name',
          ArgumentTypes.word,
          suggestsWith: _claimable,
          runs: _claim,
        ),
    );
  }

  // -- Helpers ----------------------------------------------------------------

  /// Fails the command with the message [key], shown without colors.
  Never _fail(String text) =>
      throw CommandException(MessageFormat.stripColors(text));

  Kit _kit(String name) =>
      kits.kit(name) ??
      _fail(texts.unknown(name, [for (final k in kits.kits) k.name]));

  void _say(CommandContext ctx, String line) => ctx.sender.send(line);

  // -- Player commands --------------------------------------------------------

  void _openMenu(CommandContext ctx) => ui.open(ctx.player);

  void _claim(CommandContext ctx) {
    final player = ctx.player;
    final kit = _kit(ctx.string('name'));
    _say(ctx, texts.claim(kits.claim(PlayerKitRecipient(player), kit.name)));
  }

  void _preview(CommandContext ctx) =>
      ui.preview(ctx.player, _kit(ctx.string('name')));

  void _list(CommandContext ctx) {
    if (kits.kits.isEmpty) {
      _say(ctx, texts.line('list.empty'));
      return;
    }
    final player = ctx.player;
    final uuid = player.asEntity().getUuid().asString;
    _say(ctx, texts.plain('list.header'));
    for (final kit in kits.kits) {
      final status = kits.status(uuid, kit, ctx.hasPermission);
      _say(
        ctx,
        texts.plain('list.line', {
          'kit': kit.title,
          'state': texts.state(status),
        }),
      );
    }
  }

  // -- Admin ------------------------------------------------------------------

  void _create(CommandContext ctx) {
    final name = ctx.string('name');
    final items = PlayerKitRecipient(ctx.player).capture();
    if (items.isEmpty) _fail(texts.plain('admin.empty'));
    final bool replaced;
    try {
      replaced = kits.createKit(name, items);
    } on KitException catch (e) {
      throw CommandException(e.message);
    }
    onKitsChanged();
    _say(
      ctx,
      texts.line(replaced ? 'admin.replaced' : 'admin.created', {
        'name': name.toLowerCase(),
        'count': items.length,
      }),
    );
  }

  void _delete(CommandContext ctx) {
    final name = ctx.string('name');
    try {
      kits.deleteKit(name);
    } on KitException catch (e) {
      throw CommandException(e.message);
    }
    onKitsChanged();
    _say(ctx, texts.line('admin.deleted', {'name': name.toLowerCase()}));
  }

  void _reload(CommandContext ctx) {
    final report = kits.reload(backend);
    if (!report.ok) {
      _say(ctx, texts.line('admin.reload_failed', {'error': report.error}));
      return;
    }
    _say(ctx, texts.line('admin.reloaded', {'kits': report.kits}));
    for (final problem in report.problems) {
      log.warn(problem);
      _say(ctx, texts.plain('admin.problem', {'problem': problem}));
    }
    onKitsChanged();
  }
}

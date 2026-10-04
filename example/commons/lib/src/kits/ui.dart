import 'package:pumpkin_api/pumpkin_api.dart';

import 'inventory.dart';
import 'messages.dart';
import 'model.dart';
import 'permissions.dart';
import 'service.dart';

const _filler = ItemSpec('gray_stained_glass_pane', name: ' ');

/// The chest menus of the kits: the list of kits, and a read-only preview of
/// one kit.
///
/// Click mapping in the list: left click claims the kit, right click opens
/// the preview. Nothing in a preview can be taken.
final class KitsUi {
  final KitService kits;
  final KitTexts texts;
  final Logger log;

  KitsUi(this.kits, this.texts, this.log);

  /// Opens the kit list for [player].
  void open(Player player) => _list(player).open(player);

  /// Opens a read-only look into [kit].
  void preview(Player player, Kit kit) => _preview(player, kit).open(player);

  /// What a menu needs to know about a player, as plain data. Player handles
  /// are only valid inside the callback that received them, but a menu is
  /// drawn again later (page changes, refreshes).
  _Viewer _viewer(Player player) {
    final nodes = [
      KitPerms.bypass.node,
      for (final kit in kits.kits) kit.permission,
    ];
    return _Viewer(player.asEntity().getUuid().asString, {
      for (final node in nodes)
        if (player.hasPermission(node: node)) node,
    });
  }

  Menu _list(Player player) {
    final viewer = _viewer(player);
    final menu = PagedMenu<Kit>(
      title: texts.plain('menu.title'),
      rows: 4,
      items: () => kits.kits,
      render: (kit) => _kitItem(viewer, kit),
      onSelect: (click, kit) => _guard(click.player, () {
        if (click.isLeft) {
          final result = kits.claim(PlayerKitRecipient(click.player), kit.name);
          _report(click.player, result);
          // The kit's lore shows the new cooldown.
          click.refresh();
        } else if (click.isRight) {
          click.open(_preview(click.player, kit));
        }
      }),
    );
    if (kits.kits.isEmpty) {
      menu.button(
        row: 1,
        column: 4,
        item: ItemSpec('barrier', name: texts.plain('menu.empty')),
      );
    }
    return menu;
  }

  ItemSpec _kitItem(_Viewer viewer, Kit kit) {
    final status = kits.status(viewer.uuid, kit, viewer.granted.contains);
    return ItemSpec(
      kit.icon,
      name: kit.title,
      lore: texts.kitLore(
        kit,
        status,
        canAfford: kits.economy.canAfford(viewer.uuid, kit.price),
      ),
      glint: status.canClaim ? true : null,
    );
  }

  Menu _preview(Player player, Kit kit) {
    final rows = ((kit.items.length + 8) ~/ 9 + 1).clamp(2, 6);
    final menu = Menu(
      title: texts.plain('menu.preview_title', {
        'kit': MessageFormat.stripColors(kit.title),
      }),
      rows: rows,
    );
    for (var i = 0; i < kit.items.length; i++) {
      menu.set(i, previewSpec(kit.items[i]));
    }
    final bottom = (rows - 1) * menuColumns;
    for (var column = 0; column < menuColumns; column++) {
      menu.set(bottom + column, _filler);
    }
    menu.button(
      slot: bottom + 3,
      item: ItemSpec('paper', name: texts.plain('lore.preview_hint')),
    );
    menu.button(
      slot: bottom + 5,
      item: ItemSpec('arrow', name: texts.plain('menu.back')),
      onClick: (click) => _guard(click.player, () {
        click.open(_list(click.player));
      }),
    );
    return menu;
  }

  /// Shows what a claim did above the hotbar, with a sound.
  void _report(Player player, ClaimResult result) {
    player.actionBar(texts.claim(result, withPrefix: false));
    try {
      player.customSound(
        result.isOk
            ? 'minecraft:entity.player.levelup'
            : 'minecraft:entity.villager.no',
        volume: 0.6,
      );
    } catch (e) {
      log.debug('Could not play a sound: $e');
    }
  }

  /// Runs a click handler so that a failure is logged and shown to the
  /// player instead of reaching the server.
  void _guard(Player player, void Function() body) {
    try {
      body();
    } catch (e, s) {
      log.error('Kit menu action failed', error: e, stackTrace: s);
      try {
        player.actionBar(texts.plain('claim.failed'));
      } catch (_) {
        // The player is gone, nothing to tell.
      }
    }
  }
}

final class _Viewer {
  final String uuid;
  final Set<String> granted;

  const _Viewer(this.uuid, this.granted);
}

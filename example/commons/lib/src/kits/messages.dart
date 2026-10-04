// ignore: implementation_imports
import 'package:pumpkin_api/src/message_format.dart';
// ignore: implementation_imports
import 'package:pumpkin_api/src/command_help.dart' show formatDuration;

import '../core/api.dart';
import 'catalog.dart';
import 'model.dart';
import 'service.dart';

/// Every text of the kits module, as defaults for `messages/kits.json`.
const kitMessageDefaults = <String, String>{
  // Claiming.
  'claim.ok': '&aYou claimed the &r{kit} &akit!',
  'claim.paid': '&7(paid &6{price}&7, balance &6{balance}&7)',
  'claim.cooldown':
      '&cThe &r{kit} &ckit is on cooldown for another &f{time}&c.',
  'claim.once':
      '&cYou already claimed the &r{kit} &ckit, it can only be claimed once.',
  'claim.locked': '&cYou are not allowed to claim the &r{kit} &ckit.',
  'claim.funds':
      '&cThe &r{kit} &ckit costs &6{price}&c, you need &6{missing} &cmore.',
  'claim.space': '&cMake room in your inventory first. You were not charged.',
  'claim.failed': '&cThe kit could not be given. You were not charged.',
  'claim.payment': '&cThe payment was refused.',
  'claim.unknown': '&cThere is no kit called {name}.',
  'claim.kits': '&7Kits: &f{kits}',
  // First join.
  'starter.title': '&6Welcome, {player}!',
  'starter.subtitle': '&7Your starter kit is in your inventory',
  'starter.no_room': '&eMake room in your inventory and type &a/kit starter &eto get your starter kit.',
  // /kit list.
  'list.header': '&6Kits:',
  'list.empty': '&cThere are no kits.',
  'list.line': '&r{kit} &8- {state}',
  'state.available': '&aavailable',
  'state.cooldown': '&cin {time}',
  'state.claimed': '&7claimed',
  'state.locked': '&clocked',
  // Admin.
  'admin.created':
      '&aSaved the kit {name} with {count} stack(s) from your inventory.',
  'admin.replaced': '&aReplaced the items of the kit {name} with {count} stack(s) from your inventory.',
  'admin.deleted': '&aDeleted the kit {name}.',
  'admin.empty': '&cYour inventory is empty, there is nothing to save.',
  'admin.reloaded': '&aKits reloaded: {kits} kits.',
  'admin.problem': '&e- {problem}',
  'admin.reload_failed': '&cNothing was reloaded: {error}',
  // Menus.
  'menu.title': '&8Kits',
  'menu.preview_title': '&8Kit: {kit}',
  'menu.back': '&eBack to the kits',
  'menu.empty': '&cThere are no kits yet',
  // Lore of a kit in the menu.
  'lore.available': '&aAvailable',
  'lore.cooldown': '&cOn cooldown: &f{time}',
  'lore.claimed': '&cAlready claimed',
  'lore.locked': '&cLocked: you need permission',
  'lore.price': '&7Price: &6{price}',
  'lore.cant_afford': '&cYou can not afford it yet',
  'lore.wait': '&7Cooldown: &f{time}',
  'lore.once': '&7Can be claimed once',
  'lore.contains': '&7Contains:',
  'lore.item': '&8- &7{amount}x {item}',
  'lore.more': '&8... and {count} more',
  'lore.claim': '&eLeft click&7: claim',
  'lore.preview': '&eRight click&7: preview',
  'lore.preview_hint': '&7Preview only: nothing here can be taken',
};

/// Builds the player-facing text of the kits from a [MessageCatalog].
/// Binding-free, so it is unit tested.
final class KitTexts {
  final MessageCatalog _messages;
  final Economy _economy;
  final String Function() _prefix;

  /// [prefix] is read on every use, so `/kit reload` can change it.
  KitTexts(this._messages, this._economy, this._prefix);

  String plain(String key, [Map<String, Object?> values = const {}]) =>
      _messages[key].format(values);

  String line(String key, [Map<String, Object?> values = const {}]) =>
      '${_prefix()}${plain(key, values)}';

  String money(int amount) => _economy.format(amount);

  /// What happened in [result], for the player. With [withPrefix] false the
  /// line fits an action bar.
  String claim(ClaimResult result, {bool withPrefix = true}) {
    String say(String key, [Map<String, Object?> values = const {}]) =>
        withPrefix ? line(key, values) : plain(key, values);

    final kit = result.kit;
    final values = {
      'kit': kit?.title ?? '',
      'price': kit == null ? '' : money(kit.price),
    };
    final failure = result.failure;
    if (failure == null) {
      final ok = say('claim.ok', values);
      return result.charged == 0
          ? ok
          : '$ok ${plain('claim.paid', {'price': money(result.charged), 'balance': money(result.balance)})}';
    }
    return switch (failure) {
      ClaimFailure.unknownKit => say('claim.unknown', {
        'name': MessageFormat.escape(result.requested ?? ''),
      }),
      ClaimFailure.noPermission => say('claim.locked', values),
      ClaimFailure.alreadyClaimed => say('claim.once', values),
      ClaimFailure.onCooldown => say('claim.cooldown', {
        ...values,
        'time': formatDuration(result.remaining ?? Duration.zero),
      }),
      ClaimFailure.insufficientFunds => say('claim.funds', {
        ...values,
        'missing': money(result.missing),
      }),
      ClaimFailure.paymentRefused => say('claim.payment'),
      ClaimFailure.noSpace => say('claim.space'),
      ClaimFailure.deliveryFailed => say('claim.failed'),
    };
  }

  /// "There is no kit called [name]", listing the kits.
  String unknown(String name, Iterable<String> kits) {
    final text = line('claim.unknown', {'name': MessageFormat.escape(name)});
    return kits.isEmpty
        ? text
        : '$text ${plain('claim.kits', {'kits': kits.join(', ')})}';
  }

  /// A short word for a [status], for lists.
  String state(KitStatus status) => switch (status.state) {
    KitState.available => plain('state.available'),
    KitState.locked => plain('state.locked'),
    KitState.claimed => plain('state.claimed'),
    KitState.cooldown => plain('state.cooldown', {
      'time': formatDuration(status.remaining ?? Duration.zero),
    }),
  };

  /// The lines that describe [kit] in a menu: status, price, cooldown and a
  /// few of its items. [canAfford] only matters for kits with a price.
  List<String> kitLore(
    Kit kit,
    KitStatus status, {
    required bool canAfford,
    int maxItems = 8,
  }) {
    final available = status.canClaim;
    return [
      switch (status.state) {
        KitState.available => plain('lore.available'),
        KitState.locked => plain('lore.locked'),
        KitState.claimed => plain('lore.claimed'),
        KitState.cooldown => plain('lore.cooldown', {
          'time': formatDuration(status.remaining ?? Duration.zero),
        }),
      },
      if (kit.price > 0) plain('lore.price', {'price': money(kit.price)}),
      if (kit.price > 0 && available && !canAfford) plain('lore.cant_afford'),
      if (kit.oneTime)
        plain('lore.once')
      else if (kit.cooldownSeconds > 0)
        plain('lore.wait', {'time': formatDuration(kit.cooldown)}),
      '',
      plain('lore.contains'),
      for (final item in kit.items.take(maxItems))
        plain('lore.item', {
          'amount': item.count,
          'item': item.name == null
              ? prettyItemName(normalizeItemKey(item.item))
              : MessageFormat.stripColors(item.name!),
        }),
      if (kit.items.length > maxItems)
        plain('lore.more', {'count': kit.items.length - maxItems}),
      '',
      if (available) plain('lore.claim'),
      plain('lore.preview'),
    ];
  }
}

import 'package:wasm_components/wasm_components.dart' as wc;

import 'bindings.g.dart';

/// Normalizes an item id: `diamond` becomes `minecraft:diamond`, ids that
/// already have a namespace are kept.
String _itemKey(String item) => item.contains(':') ? item : 'minecraft:$item';

wc.Option<String> _someOrNone(String? value) =>
    value == null ? wc.Option.none : wc.Option.some(value);

/// Number of slots in an ender chest.
const int enderChestSize = 27;

/// Constructors for kick options with sensible defaults (logged, graceful).
abstract final class KickOptions {
  /// Options to kick a Java player. [reason] is consumed.
  static JavaKickOptions java(
    TextComponent reason, {
    bool logToConsole = true,
    SocketTeardownPolicy teardownPolicy = SocketTeardownPolicy.graceful,
  }) => JavaKickOptions(
    reason: reason,
    logToConsole: logToConsole,
    teardownPolicy: teardownPolicy,
  );

  /// Options to kick a Bedrock player.
  static BedrockKickOptions bedrock({
    BedrockDisconnectReason reason = BedrockDisconnectReason.kicked,
    String message = '',
    bool skipMessage = false,
    String filteredMessage = '',
    bool logToConsole = true,
    SocketTeardownPolicy teardownPolicy = SocketTeardownPolicy.graceful,
  }) => BedrockKickOptions(
    reason: reason,
    message: message,
    skipMessage: skipMessage,
    filteredMessage: filteredMessage,
    logToConsole: logToConsole,
    teardownPolicy: teardownPolicy,
  );
}

/// Constructors for ban options. Bans are permanent unless a [duration] or
/// [expiresAtUtc] (RFC-3339) is given.
abstract final class BanOptions {
  /// Options to ban a player. [reason] is consumed.
  static BanPlayerOptions player({
    TextComponent? reason,
    String? source,
    Duration? duration,
    String? expiresAtUtc,
    bool kickIfOnline = true,
    bool logToConsole = true,
  }) => BanPlayerOptions(
    reason: reason == null ? wc.Option.none : wc.Option.some(reason),
    source: _someOrNone(source),
    expiresAtUtc: _someOrNone(expiresAtUtc),
    durationSeconds: duration == null
        ? wc.Option.none
        : wc.Option.some(duration.inSeconds),
    kickIfOnline: kickIfOnline,
    logToConsole: logToConsole,
  );

  /// Options to ban an IP address. [reason] is consumed.
  static BanIpOptions ip({
    TextComponent? reason,
    String? source,
    Duration? duration,
    String? expiresAtUtc,
    bool kickMatchingPlayers = true,
    bool logToConsole = true,
  }) => BanIpOptions(
    reason: reason == null ? wc.Option.none : wc.Option.some(reason),
    source: _someOrNone(source),
    expiresAtUtc: _someOrNone(expiresAtUtc),
    durationSeconds: duration == null
        ? wc.Option.none
        : wc.Option.some(duration.inSeconds),
    kickMatchingPlayers: kickMatchingPlayers,
    logToConsole: logToConsole,
  );
}

/// Ender chest helpers.
extension PlayerEnderChest on Player {
  /// All [enderChestSize] slots of the ender chest; empty slots are null.
  List<ItemStack?> get enderChestItems => [
    for (var slot = 0; slot < enderChestSize; slot++)
      () {
        final item = getEnderChestItem(slot: slot);
        return item.hasValue ? item.requireValue() : null;
      }(),
  ];

  /// Fills the ender chest from [items] (null clears a slot; extra items are
  /// ignored, missing ones leave their slot unchanged). The stacks are
  /// consumed: do not use them afterwards.
  void setEnderChestItems(Iterable<ItemStack?> items) {
    var slot = 0;
    for (final item in items) {
      if (slot >= enderChestSize) break;
      setEnderChestItem(
        slot: slot++,
        stack: item == null ? wc.Option.none : wc.Option.some(item),
      );
    }
  }
}

/// Item cooldown helpers. Items are registry ids, with `minecraft:` assumed
/// when no namespace is given (`'ender_pearl'` or `'my_mod:wand'`).
extension PlayerCooldowns on Player {
  /// Shows a cooldown overlay on [item] for [ticks] ticks.
  void setCooldown(String item, int ticks) =>
      setItemCooldown(itemId: _itemKey(item), ticks: ticks);

  /// The remaining cooldown ticks for [item], or null if it is not cooling
  /// down.
  int? getCooldown(String item) {
    final ticks = getItemCooldown(itemId: _itemKey(item));
    return ticks.hasValue ? ticks.requireValue() : null;
  }

  /// Whether [item] is currently cooling down.
  bool hasCooldown(String item) => hasItemCooldown(itemId: _itemKey(item));
}

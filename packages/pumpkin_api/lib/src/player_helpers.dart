import 'bindings.g.dart';
import 'blocks.dart';
import 'commands.dart';
import 'geometry.dart';
import 'inventory.dart';
import 'uuid_ext.dart';

/// Server ticks per second.
const int ticksPerSecond = 20;

/// Converts [d] to ticks (50 ms each), rounding down.
int durationToTicks(Duration d) => d.inMilliseconds ~/ 50;

/// Converts [ticks] to a [Duration].
Duration ticksToDuration(int ticks) => Duration(milliseconds: ticks * 50);

/// Helpers for command senders.
extension CommandSenderPlayer on CommandSender {
  /// The sending player, or throws
  /// `CommandException('Only players can use this command.')`.
  ///
  /// ```dart
  /// final player = sender.requirePlayer();
  /// ```
  Player requirePlayer() =>
      asPlayer() ?? (throw CommandException('Only players can use this command.'));
}

/// Identity, permission, state and view helpers for players.
extension PlayerHelpers on Player {
  /// The UUID in canonical text form.
  String get uuidString => getId().asString;

  /// Whether this player is a server operator. (Only the server's op manager
  /// knows, so [server] is needed; for a plain permission check use
  /// `hasPermission`.)
  bool isOperator(Server server) => server.getOpManager().isOp(id: getId());

  /// Whether the permission level is at least [level].
  bool hasPermissionLevel(PermissionLevel level) =>
      getPermissionLevel().index >= level.index;

  /// Whether the game mode is survival.
  bool get isSurvival => getGamemode() == GameMode.survival;

  /// Whether the game mode is creative.
  bool get isCreative => getGamemode() == GameMode.creative;

  /// Whether the game mode is adventure.
  bool get isAdventure => getGamemode() == GameMode.adventure;

  /// Whether the game mode is spectator.
  bool get isSpectator => getGamemode() == GameMode.spectator;

  /// Whether health is above zero.
  bool get isAlive => getHealth() > 0;

  /// Sets health to the maximum.
  void healFully() => setHealth(health: getMaxHealth());

  /// Fills food level (20) and saturation.
  void feedFully() {
    setFoodLevel(foodLevel: 20);
    setSaturation(saturation: 20);
  }

  /// The eye position.
  Vec3 get eyePosition => asEntity().getEyePosition();

  /// The unit vector the player looks along.
  Vec3 get lookDirection => directionFromRotation(getYaw(), getPitch());

  /// Puts [stack] in the first empty slot of the main inventory (no merging
  /// with existing stacks). Returns null when placed ([stack] is then
  /// consumed), or [stack] itself when the inventory is full (still usable).
  /// There is no item-entity API, so overflow cannot be dropped.
  ItemStack? give(ItemStack stack) =>
      getInventory().storage.give(stack) ? null : stack;

  /// Gives [count] of the item [key] (`diamond`), topping up existing plain
  /// stacks (no name, lore or enchantments) first, then using empty slots.
  /// Returns the number that did not fit.
  int giveItem(String key, {int count = 1}) {
    final id = normalizeRegistryKey(key);
    final inv = getInventory().storage;
    var left = count;
    final probe = ItemStack.create(registryKey: id, count: 1);
    final max = probe.getMaxCount();
    probe.dispose();
    for (var slot = 0; slot < 36 && left > 0; slot++) {
      final s = inv.getItem(slot: slot);
      if (s == null) continue;
      if (s.getRegistryKey() == id &&
          s.getCustomName() == null &&
          s.getLore().isEmpty &&
          s.getEnchantments().isEmpty &&
          s.getCount() < max) {
        final add = (max - s.getCount()) < left ? max - s.getCount() : left;
        s.setCount(count: s.getCount() + add);
        inv.setItem(slot: slot, item: s);
        left -= add;
      } else {
        s.dispose();
      }
    }
    for (var slot = 0; slot < 36 && left > 0; slot++) {
      if (inv.getItem(slot: slot) != null) continue;
      final n = left < max ? left : max;
      inv.setItem(slot: slot, item: ItemStack.create(registryKey: id, count: n));
      left -= n;
    }
    return left;
  }

  /// Applies a status effect for [duration] (default 30 s).
  ///
  /// Named `applyEffect` because `addEffect` is the raw generated method.
  /// `removeEffect(effect:)`, `hasEffect(effect:)` and `clearEffects()` are
  /// generated already.
  void applyEffect(
    StatusEffectType type, {
    Duration duration = const Duration(seconds: 30),
    int amplifier = 0,
    bool ambient = false,
    bool showParticles = true,
    bool showIcon = true,
  }) {
    addEffect(
      effect: StatusEffectInstance(
        effectType: type,
        duration: durationToTicks(duration),
        amplifier: amplifier,
        ambient: ambient,
        showParticles: showParticles,
        showIcon: showIcon,
      ),
    );
  }

  /// Time left on [type], or null if the player doesn't have it.
  Duration? effectTimeLeft(StatusEffectType type) {
    final e = getEffect(effect: type);
    return e == null ? null : ticksToDuration(e.duration);
  }
}

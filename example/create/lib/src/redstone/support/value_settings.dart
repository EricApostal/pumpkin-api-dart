// `ScrollValueBehaviour` and the server half of `ValueSettingsPacket` for the
// behaviours of this module (the brass diodes' interval). The client draws the
// value settings board; the server only keeps the value and applies picks.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/value_settings.dart';
import '../../core/block_entity.dart';
import 'rs_runtime.dart';

/// `ScrollValueBehaviour` with the `(row, value)` conversion supplied by the owner (the
/// brass diodes show ticks, seconds and minutes rows).
class ScrollValueBehaviour extends BlockEntityBehaviour implements ValueSettingsTarget {
  static const String behaviourId = 'ScrollValue';

  @override
  String get id => behaviourId;

  final int min;
  final int max;

  /// `ScrollValueBehaviour.value`.
  int value;

  /// `withCallback`: called with the new value after it changed.
  void Function(int value)? callback;

  /// `getValueSettings` / `setValueSettings` conversions; the plain behaviour uses `(0, value)`.
  (int, int) Function(int value) toSettings;
  int Function(int row, int value) fromSettings;

  /// `onShortInteract`.
  void Function(Player player)? shortInteract;

  ScrollValueBehaviour({
    required this.min,
    required this.max,
    this.value = 0,
    this.callback,
    (int, int) Function(int value)? toSettings,
    int Function(int row, int value)? fromSettings,
    this.shortInteract,
  }) : toSettings = toSettings ?? ((v) => (0, v)),
       fromSettings = fromSettings ?? ((row, v) => v);

  /// `setValue`: clamps, notifies and syncs when the value changed.
  void setValue(int newValue) {
    newValue = newValue.clamp(min, max);
    if (newValue == value) return;
    value = newValue;
    callback?.call(newValue);
    owner.sendData();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('ScrollValue', value);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    value = tag.getInt('ScrollValue') ?? value;
  }

  @override
  int get netId => 0;

  @override
  bool get acceptsValueSettings => true;

  @override
  (int row, int value) get valueSettings => toSettings(value);

  @override
  void setValueSettings(Player? player, int row, int value, {required bool ctrlDown}) {
    if (valueSettings == (row, value)) return;
    setValue(fromSettings(row, value));
  }
}

/// Routes `create:value_settings` to the [ScrollValueBehaviour]s of block entities of
/// this module (other modules handle their own entities; the bus runs every handler).
abstract final class ValueSettingsRouter {
  static void install(RsRuntime rs) {
    final bus = rs.bus;
    if (bus == null) {
      rs.log.warn('No payload bus: create:value_settings is not handled for the redstone blocks');
      return;
    }
    bus.onServerbound('create:value_settings', (player, f) {
      final pos = f['pos'] as (int, int, int);
      final worldId = _worldIdOf(player, rs);
      if (worldId == null) return;
      final be = rs.store.at(worldId, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
      if (be == null) return;
      // BlockEntityConfigurationPacket: the player must be within 20 blocks.
      if (!_near(player, pos)) return;
      final b = be.getBehaviour<ScrollValueBehaviour>();
      if (b == null || !b.acceptsValueSettings) return;
      if (b.netId != (f['behaviourIndex'] as int? ?? 0)) return;
      if (f['interactHand'] != null) {
        b.shortInteract?.call(player);
      } else {
        b.setValueSettings(player, f['row'] as int? ?? 0, f['value'] as int? ?? 0, ctrlDown: f['ctrlDown'] == true);
      }
    });
  }

  static String? _worldIdOf(Player player, RsRuntime rs) {
    try {
      return rs.worldId(player.getWorld());
    } on Object {
      return null;
    }
  }

  static bool _near(Player player, (int, int, int) pos) {
    final (x, y, z) = player.getPosition();
    final dx = x - (pos.$1 + 0.5), dy = y - (pos.$2 + 0.5), dz = z - (pos.$3 + 0.5);
    return dx * dx + dy * dy + dz * dz < 20 * 20;
  }
}

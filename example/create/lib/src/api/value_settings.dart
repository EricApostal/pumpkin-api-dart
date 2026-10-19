// The interface between Create's value settings board (the `create:value_settings`
// packet) and the behaviours that accept its values. A behaviour (a speed
// controller's target speed, a filter, ...) implements [ValueSettingsTarget];
// whoever owns the packet channel finds them on the block entity.
import 'package:pumpkin_api/pumpkin_api.dart';

/// A block entity behaviour that accepts `ValueSettingsPacket` values.
abstract interface class ValueSettingsTarget {
  /// `acceptsValueSettings()`.
  bool get acceptsValueSettings;

  /// `netId()`: the index the client addresses the behaviour with.
  int get netId;

  /// `setValueSettings(player, ValueSettings(row, value), ctrlDown)`.
  void setValueSettings(Player? player, int row, int value, {required bool ctrlDown});

  /// `getValueSettings()` as (row, value).
  (int row, int value) get valueSettings;
}

/// A block entity that has [ValueSettingsTarget] behaviours; the owner of the
/// `create:value_settings` channel asks it for the target of a packet.
abstract interface class ValueSettingsHost {
  List<ValueSettingsTarget> get valueSettingsTargets;
}

/// A [ValueSettingsTarget] that also reacts to a short interaction (a right click on
/// its value box that does not open the board): `onShortInteract`.
abstract interface class ShortInteractTarget {
  void onShortInteract(Player player);
}

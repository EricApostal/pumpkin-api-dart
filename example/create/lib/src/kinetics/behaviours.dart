// Block entity behaviours of the kinetic blocks: scroll values (creative motor
// speed, speed controller target, valve handle angle).
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/value_settings.dart';
import '../core/block_entity.dart';
import 'generators.dart' show ValveHandleBlockEntity;

/// `ScrollValueBehaviour`: one integer between [min] and [max] that players set
/// with the value settings board. Saved as `ScrollValue`.
class ScrollValueBehaviour extends BlockEntityBehaviour implements ValueSettingsTarget {
  /// The index the client uses for the first (usually only) value behaviour.
  static const int defaultNetId = 0;

  @override
  String get id => 'scroll_value';

  int min = 0;
  int max = 1;
  int value = 0;
  void Function(int value)? callback;
  bool Function() isActive = _always;
  @override
  final int netId;

  ScrollValueBehaviour({this.netId = defaultNetId});

  static bool _always() => true;

  ScrollValueBehaviour withCallback(void Function(int value) cb) {
    callback = cb;
    return this;
  }

  ScrollValueBehaviour between(int min, int max) {
    this.min = min;
    this.max = max;
    return this;
  }

  ScrollValueBehaviour onlyActiveWhen(bool Function() condition) {
    isActive = condition;
    return this;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('ScrollValue', value);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    value = tag.getInt('ScrollValue') ?? 0;
  }

  /// `setValue`: clamps, calls the callback, saves and syncs.
  void setValue(int newValue) {
    newValue = newValue.clamp(min, max);
    if (newValue == value) return;
    value = newValue;
    callback?.call(newValue);
    owner.markDirty();
    owner.sendData();
  }

  int getValue() => value;

  @override
  bool get acceptsValueSettings => isActive();

  @override
  (int, int) get valueSettings => (0, value);

  @override
  void setValueSettings(Player? player, int row, int newValue, {required bool ctrlDown}) {
    if (row == valueSettings.$1 && newValue == value) return;
    setValue(newValue);
  }
}

/// `KineticScrollValueBehaviour`: two rows (clockwise and counter clockwise),
/// the value is negative for counter clockwise... as Create stores it.
class KineticScrollValueBehaviour extends ScrollValueBehaviour {
  KineticScrollValueBehaviour({super.netId});

  @override
  (int, int) get valueSettings => (value < 0 ? 0 : 1, value.abs());

  @override
  void setValueSettings(Player? player, int row, int newValue, {required bool ctrlDown}) {
    final v = newValue < 1 ? 1 : newValue;
    setValue(row == 0 ? -v : v);
  }
}

/// The valve handle's angle input: same board, rows 0 and 1 mean the sign. A short
/// right click on the value box turns the handle (`onShortInteract`).
class ValveHandleScrollValueBehaviour extends KineticScrollValueBehaviour implements ShortInteractTarget {
  ValveHandleScrollValueBehaviour({super.netId});

  @override
  void onShortInteract(Player player) {
    final be = owner;
    if (be is ValveHandleBlockEntity) be.activate(player.asEntity().isSneaking());
  }
}

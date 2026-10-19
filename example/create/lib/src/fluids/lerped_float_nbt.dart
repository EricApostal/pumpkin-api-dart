// The NBT of a catnip `LerpedFloat` (`LerpedFloat.write` / `read`). The client reads the
// compound, so values the client animates are written in this form, not as a plain number.
import 'package:pumpkin_api/pumpkin_api.dart';

abstract final class LerpedFloatNbt {
  /// Writes [value] under [key] as `{Speed, Target, Value[, Force]}`.
  static void write(
    NbtCompound tag,
    String key,
    double value, {
    double? target,
    double speed = 0,
    bool force = false,
  }) {
    final compound = NbtCompound()
      ..putFloat('Speed', speed)
      ..putFloat('Target', target ?? value)
      ..putFloat('Value', value);
    if (force) compound.putBool('Force', true);
    tag.putCompound(key, compound);
  }

  /// Reads the value of [key]; the plain number of older data is accepted.
  static double read(NbtCompound tag, String key, {double fallback = 0}) {
    final compound = tag.getCompound(key);
    if (compound != null) return compound.getDouble('Value') ?? fallback;
    return tag.getDouble(key) ?? fallback;
  }
}

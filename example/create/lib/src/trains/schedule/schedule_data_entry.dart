// `ScheduleDataEntry` (pure): the base of instructions and conditions, which keep their
// configuration in one `data` tag the client edits (`Value`, `TimeUnit`, `Text`, ...).
import '../util/ctag.dart';
import 'i_schedule_input.dart';

abstract class ScheduleDataEntry implements IScheduleInput {
  /// `protected CompoundTag data`.
  CTag data = CTag();

  ScheduleDataEntry();

  @override
  CTag getData() => data;

  @override
  void setData(CTag data) {
    this.data = data;
    readAdditional(data);
  }

  /// `writeAdditional(registries, tag)`: derived state back into the tag copy that is written.
  void writeAdditional(CTag tag) {}

  /// `readAdditional(registries, tag)`.
  void readAdditional(CTag tag) {}

  /// `enumData(key, enumClass)`: `enumConstants[data.getIntOr(key, 0) % length]`.
  T enumData<T>(String key, List<T> enumConstants) => enumConstants[data.getInt(key) % enumConstants.length];

  /// `textData(key)`.
  String textData(String key) => data.getString(key);

  /// `intData(key)`.
  int intData(String key) => data.getInt(key);

  @override
  int slotsTargeted() => 0;

  @override
  void setItem(int slot, CTag stack) {}

  @override
  CTag getItem(int slot) => CTag();
}

// `CargoThresholdCondition` (pure): the base of the item and fluid threshold conditions.
import '../../entity/train.dart';
import '../../util/ctag.dart';
import '../schedule_level.dart';
import 'lazy_ticked_schedule_condition.dart';

// ignore_for_file: constant_identifier_names

/// `CargoThresholdCondition.Ops`.
enum Ops {
  GREATER('>'),
  LESS('<'),
  EQUAL('=');

  final String formatted;

  const Ops(this.formatted);

  bool test(int current, int target) => switch (this) {
    GREATER => current > target,
    EQUAL => current == target,
    LESS => current < target,
  };
}

/// `Integer.valueOf(String)`; `null` for a `NumberFormatException`.
int? parseJavaInt(String s) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(s)) return null;
  final v = int.tryParse(s.startsWith('+') ? s.substring(1) : s);
  if (v == null || v > 2147483647 || v < -2147483648) return null;
  return v;
}

abstract class CargoThresholdCondition extends LazyTickedScheduleCondition {
  CargoThresholdCondition() : super(20) {
    data.putString('Threshold', '10');
  }

  @override
  bool lazyTickCompletion(ScheduleLevel level, Train train, CTag context) {
    final lastChecked = context.contains('LastChecked') ? context.getInt('LastChecked') : -1;
    var status = 0;
    for (final carriage in train.carriages) {
      status += carriage.storage.getVersion();
    }
    status = status.toSigned(32);
    if (status == lastChecked) return false;
    context.putInt('LastChecked', status);
    return test(level, train, context);
  }

  /// `requestStatusToUpdate(amount, context)`.
  void requestStatusToUpdateAmount(int amount, CTag context) {
    context.putInt('CurrentDisplay', amount);
    requestStatusToUpdate(context);
  }

  /// `getLastDisplaySnapshot(context)`.
  int getLastDisplaySnapshot(CTag context) {
    if (!context.contains('CurrentDisplay')) return -1;
    return context.getInt('CurrentDisplay');
  }

  bool test(ScheduleLevel level, Train train, CTag context);

  @override
  int slotsTargeted() => 1;

  Ops getOperator() => enumData('Operator', Ops.values);

  int getThreshold() {
    final v = parseJavaInt(textData('Threshold'));
    if (v != null) return v;
    data.putString('Threshold', '0');
    return 0;
  }

  int getMeasure() => intData('Measure');
}

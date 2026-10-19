// `Schedule` (pure): the entries a train works through, whether it loops, and the progress saved
// when the schedule item was taken back. The NBT form (`Entries`, `Cyclic`, `Progress`) is what the
// `create:train_schedule` data component of the schedule item holds and what the client reads.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names
import '../../common/data.dart' show Pair;
import '../manager/create.dart';
import '../util/ctag.dart';
import 'condition/fluid_threshold_condition.dart';
import 'condition/idle_cargo_condition.dart';
import 'condition/item_threshold_condition.dart';
import 'condition/player_passenger_condition.dart';
import 'condition/redstone_link_condition.dart';
import 'condition/schedule_wait_condition.dart';
import 'condition/scheduled_delay.dart';
import 'condition/station_powered_condition.dart';
import 'condition/station_unloaded_condition.dart';
import 'condition/time_of_day_condition.dart';
import 'destination/change_throttle_instruction.dart';
import 'destination/change_title_instruction.dart';
import 'destination/deliver_packages_instruction.dart';
import 'destination/destination_instruction.dart';
import 'destination/fetch_packages_instruction.dart';
import 'destination/schedule_instruction.dart';
import 'schedule_entry.dart';

class Schedule {
  /// `Schedule.INSTRUCTION_TYPES`: id and factory, in registration order.
  static final List<Pair<String, ScheduleInstruction Function()>> INSTRUCTION_TYPES = [];

  /// `Schedule.CONDITION_TYPES`.
  static final List<Pair<String, ScheduleWaitCondition Function()>> CONDITION_TYPES = [];

  static bool _registered = false;

  /// The static block of the Java class: registers the built-in types once. Called by the
  /// registration of the schedule area and lazily by [Schedule.new].
  static void ensureRegistered() {
    if (_registered) return;
    _registered = true;
    registerInstruction('destination', DestinationInstruction.new);
    registerInstruction('package_delivery', DeliverPackagesInstruction.new);
    registerInstruction('package_retrieval', FetchPackagesInstruction.new);
    registerInstruction('rename', ChangeTitleInstruction.new);
    registerInstruction('throttle', ChangeThrottleInstruction.new);
    registerCondition('delay', ScheduledDelay.new);
    registerCondition('time_of_day', TimeOfDayCondition.new);
    registerCondition('fluid_threshold', FluidThresholdCondition.new);
    registerCondition('item_threshold', ItemThresholdCondition.new);
    registerCondition('redstone_link', RedstoneLinkCondition.new);
    registerCondition('player_count', PlayerPassengerCondition.new);
    registerCondition('idle', IdleCargoCondition.new);
    registerCondition('unloaded', StationUnloadedCondition.new);
    registerCondition('powered', StationPoweredCondition.new);
  }

  static void registerInstruction(String name, ScheduleInstruction Function() factory) =>
      INSTRUCTION_TYPES.add(Pair(Create.asResource(name), factory));

  static void registerCondition(String name, ScheduleWaitCondition Function() factory) =>
      CONDITION_TYPES.add(Pair(Create.asResource(name), factory));

  List<ScheduleEntry> entries;
  bool cyclic;
  int savedProgress;

  /// `new Schedule()`.
  Schedule() : this.of([], true, 0);

  /// `new Schedule(entries, cyclic, savedProgress)`.
  Schedule.of(this.entries, this.cyclic, this.savedProgress) {
    ensureRegistered();
  }

  /// `write(registries)`.
  CTag write() {
    final tag = CTag();
    tag.putCompoundList('Entries', [for (final e in entries) e.write()]);
    tag.putBoolean('Cyclic', cyclic);
    if (savedProgress > 0) tag.putInt('Progress', savedProgress);
    return tag;
  }

  /// `fromTag(registries, tag)`.
  static Schedule fromTag(CTag tag) {
    final schedule = Schedule();
    schedule.entries = [for (final t in tag.getCompoundList('Entries')) ScheduleEntry.fromTag(t)];
    schedule.cyclic = tag.getBooleanOr('Cyclic', false);
    if (tag.contains('Progress')) schedule.savedProgress = tag.getInt('Progress');
    return schedule;
  }

  /// `Schedule.STREAM_CODEC` as the payload map of `create:configure_schedule`
  /// (`entries`: list of `{instruction, conditions}`, `cyclic`, `savedProgress`).
  static Schedule fromWire(Map<String, Object?> fields) {
    ensureRegistered();
    final entries = <ScheduleEntry>[];
    for (final e in (fields['entries'] as List<Object?>? ?? const [])) {
      entries.add(ScheduleEntry.fromWire(e! as Map<String, Object?>));
    }
    return Schedule.of(entries, fields['cyclic'] == true, (fields['savedProgress'] as int?) ?? 0);
  }

  /// The inverse of [fromWire].
  Map<String, Object?> toWire() => {
    'entries': [for (final e in entries) e.toWire()],
    'cyclic': cyclic,
    'savedProgress': savedProgress,
  };
}

// `ScheduleEditPacket` (`create:configure_schedule`, pure part): the schedule the client edited,
// applied to the schedule item in the sender's main hand.
import '../util/ctag.dart';
import 'schedule.dart';

final class ScheduleEditPacket {
  final Schedule schedule;

  const ScheduleEditPacket(this.schedule);

  /// `STREAM_CODEC` from the payload map (`{schedule: {entries, cyclic, savedProgress}}`).
  factory ScheduleEditPacket.fromFields(Map<String, Object?> fields) =>
      ScheduleEditPacket(Schedule.fromWire(fields['schedule']! as Map<String, Object?>));

  Map<String, Object?> toFields() => {'schedule': schedule.toWire()};

  /// What `handle` puts on the item: the new value of the `create:train_schedule` component, or
  /// `null` to remove it (an empty schedule).
  CTag? scheduleComponent() => schedule.entries.isEmpty ? null : schedule.write();
}

// `ScheduleEntry` (pure): one instruction and the conditions to wait for after it. Conditions
// are an OR of columns, each column an AND (in order) of conditions.
import '../../core/nbt.dart' show NbtKind, NbtValue;
import '../util/ctag.dart';
import 'condition/schedule_wait_condition.dart';
import 'destination/destination_instruction.dart';
import 'destination/schedule_instruction.dart';
import 'schedule.dart';

class ScheduleEntry {
  late ScheduleInstruction instruction;
  List<List<ScheduleWaitCondition>> conditions;

  /// `new ScheduleEntry()`: no instruction yet (set [instruction] before use).
  ScheduleEntry.blank() : conditions = [] {
    Schedule.ensureRegistered();
    instruction = DestinationInstruction();
  }

  /// `new ScheduleEntry(instruction, conditions)`.
  ScheduleEntry(this.instruction, this.conditions) {
    Schedule.ensureRegistered();
  }

  /// `clone(registries)`.
  ScheduleEntry clone() => fromTag(write());

  /// `write(registries)`.
  CTag write() {
    final tag = CTag();
    tag.putCompound('Instruction', instruction.write());
    if (!instruction.supportsConditions()) return tag;
    final outer = <NbtValue>[
      for (final column in conditions) NbtValue.list([for (final c in column) NbtValue.compound(c.write().entries)]),
    ];
    tag.putList('Conditions', outer);
    return tag;
  }

  /// `fromTag(registries, tag)`.
  static ScheduleEntry fromTag(CTag tag) {
    Schedule.ensureRegistered();
    final entry = ScheduleEntry.blank();
    entry.instruction = ScheduleInstruction.fromTag(tag.getCompound('Instruction'));
    entry.conditions = [];
    if (entry.instruction.supportsConditions()) {
      for (final t in tag.getList('Conditions')) {
        if (t.kind != NbtKind.list) continue;
        final column = <ScheduleWaitCondition>[];
        for (final c in t.value as List<NbtValue>) {
          if (c.kind != NbtKind.compound) continue;
          final condition = ScheduleWaitCondition.fromTag(CTag(c.asCompound));
          if (condition != null) column.add(condition);
        }
        entry.conditions.add(column);
      }
    }
    return entry;
  }

  /// `ScheduleEntry.STREAM_CODEC` from the payload map.
  static ScheduleEntry fromWire(Map<String, Object?> fields) {
    Schedule.ensureRegistered();
    final instruction = ScheduleInstruction.fromTag(CTag.fromNbt(fields['instruction'] as NbtValue?));
    final conditions = <List<ScheduleWaitCondition>>[];
    for (final column in (fields['conditions'] as List<Object?>? ?? const [])) {
      final list = <ScheduleWaitCondition>[];
      for (final c in column! as List<Object?>) {
        final condition = ScheduleWaitCondition.fromTag(CTag.fromNbt(c as NbtValue?));
        if (condition != null) list.add(condition);
      }
      conditions.add(list);
    }
    return ScheduleEntry(instruction, conditions);
  }

  /// The inverse of [fromWire].
  Map<String, Object?> toWire() => {
    'instruction': instruction.write().toNbt(),
    'conditions': [
      for (final column in conditions) [for (final c in column) c.write().toNbt()],
    ],
  };
}

// `ScheduleInstruction` (pure): one line of a schedule that starts something (navigate to a
// station, rename the schedule, change the throttle ...).
import '../../graph/discovered_path.dart';
import '../../util/ctag.dart';
import '../schedule.dart';
import '../schedule_data_entry.dart';
import '../schedule_level.dart';
import '../schedule_runtime.dart';
import 'destination_instruction.dart';

abstract class ScheduleInstruction extends ScheduleDataEntry {
  ScheduleInstruction();

  /// `supportsConditions()`.
  bool supportsConditions();

  /// `start(runtime, level)`: begins the instruction, returns the path to navigate or `null`.
  DiscoveredPath? start(ScheduleRuntime runtime, ScheduleLevel level);

  /// `write(registries)`: `{Id, Data}`.
  CTag write() {
    final tag = CTag();
    final dataCopy = data.copy();
    writeAdditional(dataCopy);
    tag.putString('Id', getId());
    tag.putCompound('Data', dataCopy);
    return tag;
  }

  /// `fromTag(registries, tag)`: an unknown id gives a [DestinationInstruction].
  static ScheduleInstruction fromTag(CTag tag) {
    final location = normalizeIdentifier(tag.getString('Id'));
    ScheduleInstruction Function()? supplier;
    for (final pair in Schedule.INSTRUCTION_TYPES) {
      if (pair.first == location) supplier = pair.second;
    }
    if (supplier == null) return DestinationInstruction();

    final scheduleDestination = supplier();
    // Left around for migration purposes. Data added in writeAdditional has moved into the "Data" tag
    scheduleDestination.readAdditional(tag);
    final data = tag.getCompound('Data');
    scheduleDestination.readAdditional(data);
    scheduleDestination.data = data;
    return scheduleDestination;
  }
}

/// `Identifier.parse(id)`: an id without namespace is in `minecraft`.
String normalizeIdentifier(String id) => id.contains(':') ? id : 'minecraft:$id';

// `ChangeTitleInstruction` (pure): renames the schedule (the title displays show).
import '../../graph/discovered_path.dart';
import '../schedule_level.dart';
import '../schedule_runtime.dart';
import 'text_schedule_instruction.dart';

class ChangeTitleInstruction extends TextScheduleInstruction {
  @override
  String getId() => 'create:rename';

  @override
  bool supportsConditions() => false;

  /// `getScheduleTitle()`.
  String getScheduleTitle() => getLabelText();

  @override
  DiscoveredPath? start(ScheduleRuntime runtime, ScheduleLevel level) {
    runtime.currentTitle = getScheduleTitle();
    runtime.state = State.PRE_TRANSIT;
    runtime.currentEntry++;
    return null;
  }
}

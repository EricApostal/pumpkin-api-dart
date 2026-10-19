// `ChangeThrottleInstruction` (pure): sets the throttle of the train.
import '../../graph/discovered_path.dart';
import '../schedule_level.dart';
import '../schedule_math.dart';
import '../schedule_runtime.dart';
import 'schedule_instruction.dart';

class ChangeThrottleInstruction extends ScheduleInstruction {
  ChangeThrottleInstruction() {
    data.putInt('Value', 100);
  }

  @override
  String getId() => 'create:throttle';

  @override
  bool supportsConditions() => false;

  /// `getThrottle()`: `intData("Value") / 100f`.
  double getThrottle() => toFloat32(intData('Value') / 100);

  @override
  DiscoveredPath? start(ScheduleRuntime runtime, ScheduleLevel level) {
    runtime.train.throttle = getThrottle();
    runtime.state = State.PRE_TRANSIT;
    runtime.currentEntry++;
    return null;
  }
}

// `TextScheduleInstruction` (pure): an instruction configured with one text (`Text`).
import 'schedule_instruction.dart';

abstract class TextScheduleInstruction extends ScheduleInstruction {
  /// `getLabelText()`.
  String getLabelText() => textData('Text');
}

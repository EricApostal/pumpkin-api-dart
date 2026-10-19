// `AllTriggers` (pure): the criterion triggers Create registers. The definitions come from the
// content manifest (`kTriggers`); this class gives them names for the rest of the code.
import '../../manifest/manifest.dart';

/// `AllTriggers`.
abstract final class AllTriggers {
  /// The class of every `SimpleCreateTrigger` (`AllTriggers.addSimple`).
  static const String simpleTriggerClass =
      'com.simibubi.create.foundation.advancement.SimpleCreateTrigger';

  /// Every registered trigger id, in manifest (registration) order.
  static final List<String> all = [for (final trigger in kTriggers) trigger.id];

  /// The simple triggers: they fire unconditionally when their advancement is awarded.
  static final List<String> simple = [
    for (final trigger in kTriggers)
      if (trigger.javaClass == simpleTriggerClass) trigger.id,
  ];

  /// Whether [triggerId] is one of the simple triggers.
  static bool isSimple(String triggerId) => simple.contains(triggerId);

  /// `AllAdvancements.<name>`'s trigger id: `create:<path>_builtin`.
  static String forAdvancement(String advancementPath) =>
      'create:${advancementPath}_builtin';
}

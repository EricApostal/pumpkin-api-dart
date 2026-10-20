// `dev.ryanhcode.sable.command.argument.SubLevelSuggestionProvider`: a command
// source that can name the sub-level the sender is looking at, so the selector
// argument can suggest its UUID.
//
// Pure: no host imports.
import '../model/sub_level.dart';

/// A suggestion source that knows which sub-level is selected.
abstract interface class SubLevelSuggestionProvider {
  /// The selected sub-level, or `null`.
  SubLevel? getSelectedSubLevel() => null;
}

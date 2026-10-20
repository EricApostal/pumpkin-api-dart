// `dev.ryanhcode.sable.command.data_accessor.SubLevelDataAccessor`: the
// `/data` integration that reads and writes a sub-level's user-data tag.
//
// Java plugs this into vanilla's `/data` command (`ArgProvider`). The plugin's
// command layer has no `/data` extension point, so the port keeps the accessor
// itself — the read/write of `SubLevel.userDataTag` and the message texts — and
// leaves the command wiring to whoever gains that hook.
//
// Pure: no host imports.
import '../model/server_sub_level.dart';

/// Reads and writes the user-data tag of one sub-level.
final class SubLevelDataAccessor {
  final ServerSubLevel subLevel;

  SubLevelDataAccessor(this.subLevel);

  /// `setData(tag)`.
  void setData(Map<String, Object?> tag) => subLevel.setUserDataTag(tag);

  /// `getData()`.
  Map<String, Object?> getData() => subLevel.getUserDataTag() ?? {};

  /// `getModifiedSuccess()`.
  String getModifiedSuccess() => 'Modified the data of ${subLevel.name ?? subLevel.uniqueId}';

  /// `getPrintSuccess(tag)`.
  String getPrintSuccess(Object? tag) =>
      'The data of ${subLevel.name ?? subLevel.uniqueId} is: $tag';

  /// `getPrintSuccess(path, scale, result)`.
  String getPrintSuccessAtPath(String path, double scale, int result) =>
      '$path of ${subLevel.name ?? subLevel.uniqueId} is $result '
      '(scaled by ${scale.toStringAsFixed(2)})';
}

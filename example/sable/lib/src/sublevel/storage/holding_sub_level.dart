// `dev.ryanhcode.sable.sublevel.storage.HoldingSubLevel`: a sub-level that is in
// memory but not in the level, plus the pointer to where it is saved.
//
// Pure: no host imports.
import 'holding/saved_pointer.dart';
import 'serialization/sub_level_data.dart';

/// A sub-level waiting in a holding chunk.
final class HoldingSubLevel {
  final SubLevelData data;
  GlobalSavedSubLevelPointer? pointer;

  HoldingSubLevel(this.data, this.pointer);

  /// The serialized data.
  SubLevelData getData() => data;

  /// The pointer to where this is saved.
  GlobalSavedSubLevelPointer? getPointer() => pointer;

  /// Sets the pointer (after the data moved to another chunk).
  void setPointer(GlobalSavedSubLevelPointer? pointer) => this.pointer = pointer;

  @override
  bool operator ==(Object other) =>
      other is HoldingSubLevel && other.data == data && other.pointer == pointer;

  @override
  int get hashCode => Object.hash(data, pointer);

  @override
  String toString() => 'HoldingSubLevel[data=$data, pointer=$pointer]';
}

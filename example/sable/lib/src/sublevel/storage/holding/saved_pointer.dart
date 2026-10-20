// `dev.ryanhcode.sable.sublevel.storage.holding.SavedSubLevelPointer` and
// `GlobalSavedSubLevelPointer`: where a sub-level is stored on disk.
//
// A storage file holds up to 1024 sub-levels (`subLevelIndex`), and a chunk can
// have several storage files (`storageIndex`). The local pointer packs both into
// one int; the global pointer adds the chunk the storage file belongs to.
//
// Pure: no host imports.
import 'dart:typed_data';

/// A sub-level's index inside a chunk's storage files.
final class SavedSubLevelPointer {
  /// The index of the storage file (Java `short`).
  final int storageIndex;

  /// The index of the sub-level inside that file (Java `short`).
  final int subLevelIndex;

  const SavedSubLevelPointer(this.storageIndex, this.subLevelIndex);

  /// `packed()`: `(storageIndex << 16) | (subLevelIndex & 0xFFFF)`, as a
  /// 32-bit value.
  int packed() => ((storageIndex & 0xFFFF) << 16) | (subLevelIndex & 0xFFFF);

  /// `unpack(int)`, sign-extending both halves like Java's `short` cast.
  static SavedSubLevelPointer unpack(int packed) =>
      SavedSubLevelPointer(_toShort(packed >> 16), _toShort(packed));

  static int _toShort(int value) {
    final v = value & 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  /// Writes this pointer as the two ints the holding-chunk NBT stores.
  List<int> toInts() => [storageIndex, subLevelIndex];

  @override
  bool operator ==(Object other) =>
      other is SavedSubLevelPointer &&
      other.storageIndex == storageIndex &&
      other.subLevelIndex == subLevelIndex;

  @override
  int get hashCode => Object.hash(storageIndex, subLevelIndex);

  @override
  String toString() => 'local->[storageIndex=$storageIndex, subLevelIndex=$subLevelIndex]';
}

/// A global location of sub-level storage: a chunk plus a local pointer.
final class GlobalSavedSubLevelPointer {
  final int chunkX;
  final int chunkZ;
  final int storageIndex;
  final int subLevelIndex;

  const GlobalSavedSubLevelPointer(this.chunkX, this.chunkZ, this.storageIndex, this.subLevelIndex);

  /// `local()`.
  SavedSubLevelPointer get local => SavedSubLevelPointer(storageIndex, subLevelIndex);

  /// The NBT shape of `GlobalSavedSubLevelPointer.CODEC`:
  /// `chunk_x`, `chunk_z`, `storage_index`, `sub_level_index`.
  Map<String, Object?> toMap() => {
    'chunk_x': chunkX,
    'chunk_z': chunkZ,
    'storage_index': storageIndex,
    'sub_level_index': subLevelIndex,
  };

  /// The inverse of [toMap].
  static GlobalSavedSubLevelPointer fromMap(Map<String, Object?> map) => GlobalSavedSubLevelPointer(
    (map['chunk_x'] as num?)?.toInt() ?? 0,
    (map['chunk_z'] as num?)?.toInt() ?? 0,
    (map['storage_index'] as num?)?.toInt() ?? 0,
    (map['sub_level_index'] as num?)?.toInt() ?? 0,
  );

  /// The pointer as the eight bytes it is encoded as on the wire (chunk x, chunk
  /// z, storage index, sub-level index).
  Uint8List toBytes() {
    final data = ByteData(8);
    data.setInt32(0, chunkX);
    data.setInt32(4, chunkZ);
    // The indices are shorts; they travel with the chunk in the ticket data.
    return data.buffer.asUint8List();
  }

  @override
  bool operator ==(Object other) =>
      other is GlobalSavedSubLevelPointer &&
      other.chunkX == chunkX &&
      other.chunkZ == chunkZ &&
      other.storageIndex == storageIndex &&
      other.subLevelIndex == subLevelIndex;

  @override
  int get hashCode => Object.hash(chunkX, chunkZ, storageIndex, subLevelIndex);

  @override
  String toString() => 'global->[chunkPos=($chunkX, $chunkZ), '
      'storageIndex=$storageIndex, subLevelIndex=$subLevelIndex]';
}

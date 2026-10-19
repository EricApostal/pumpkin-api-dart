/// The public API of the millstone part of the processing module (re-exported by
/// `package:create/src/api/processing.dart`).
///
/// Other modules reach the millstone's storage through
/// [ItemStorageProvider][MillstoneBlockEntity] (the mechanical arm's interaction point and
/// belts do) and use the block key below.
library;

export 'millstone_block_entity.dart' show MillstoneBlockEntity;
export 'millstone_keys.dart';

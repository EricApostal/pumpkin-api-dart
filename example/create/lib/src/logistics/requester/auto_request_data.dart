// `AutoRequestData` (pure): the order a redstone requester or a table cloth shop was programmed
// with, and the stock keeper it points at.
import '../model/orders.dart';

/// `AutoRequestData`.
final class AutoRequestData {
  final PackageOrderWithCrafts encodedRequest;
  final String encodedTargetAddress;

  /// `targetOffset`: relative to the block that was programmed (or that carries the shop).
  final (int, int, int) targetOffset;
  final String targetDim;
  final bool isValid;

  const AutoRequestData(
    this.encodedRequest,
    this.encodedTargetAddress,
    this.targetOffset,
    this.targetDim,
    this.isValid,
  );

  factory AutoRequestData.empty() => AutoRequestData(
    PackageOrderWithCrafts.empty(),
    '',
    (0, 0, 0),
    'null',
    false,
  );

  Map<String, dynamic> toMap() => {
    'encoded_request': encodedRequest.toMap(),
    'encoded_target_address': encodedTargetAddress,
    'target_offset': [targetOffset.$1, targetOffset.$2, targetOffset.$3],
    'target_dim': targetDim,
    'is_valid': isValid,
  };

  static AutoRequestData fromMap(Map<String, dynamic> map) {
    final offset = map['target_offset'];
    return AutoRequestData(
      map['encoded_request'] is Map
          ? PackageOrderWithCraftsMapper.fromMap(
              (map['encoded_request'] as Map).cast<String, dynamic>(),
            )
          : PackageOrderWithCrafts.empty(),
      map['encoded_target_address'] as String? ?? '',
      offset is List && offset.length == 3
          ? (offset[0] as int, offset[1] as int, offset[2] as int)
          : (0, 0, 0),
      map['target_dim'] as String? ?? 'null',
      map['is_valid'] == true,
    );
  }

  /// `writeToItem(position)`: the offset is stored relative to the placement position.
  AutoRequestData writeToItem((int, int, int) position) => AutoRequestData(
    encodedRequest,
    encodedTargetAddress,
    (
      position.$1 + targetOffset.$1,
      position.$2 + targetOffset.$2,
      position.$3 + targetOffset.$3,
    ),
    targetDim,
    isValid,
  );

  /// `readFromItem(level, position)`: the offset becomes relative to the placed block and the
  /// keeper must be within 128 blocks and in the same dimension.
  AutoRequestData readFromItem((int, int, int) position, String dimension) {
    final offset = (
      targetOffset.$1 - position.$1,
      targetOffset.$2 - position.$2,
      targetOffset.$3 - position.$3,
    );
    final distSq =
        offset.$1 * offset.$1 + offset.$2 * offset.$2 + offset.$3 * offset.$3;
    return AutoRequestData(
      encodedRequest,
      encodedTargetAddress,
      offset,
      targetDim,
      distSq < 128 * 128 && targetDim == dimension,
    );
  }

  /// The absolute position of the stock keeper, for a block at [position].
  (int, int, int) targetPos((int, int, int) position) => (
    position.$1 + targetOffset.$1,
    position.$2 + targetOffset.$2,
    position.$3 + targetOffset.$3,
  );

  bool get isEmpty => encodedRequest.isEmpty;
}

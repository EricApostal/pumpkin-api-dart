// `AutoRequestData` (pure): the order a redstone requester or a table cloth shop was programmed
// with, and the stock keeper it points at. The item component (`create:auto_request_data`) is the
// network encoding of the Java record.
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../model/orders.dart';
import '../model/stack_wire.dart';

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

  /// `AutoRequestData.STREAM_CODEC`: the order, the address, the target offset as a packed
  /// `BlockPos` long, the dimension and the validity flag.
  List<int> encode(StackWire wire) => PacketBuffer.encode((w) {
    wire.writeOrderWithCrafts(w, encodedRequest);
    w.writeString(encodedTargetAddress);
    w.writeLong(blockPosAsLong(targetOffset));
    w.writeString(targetDim);
    w.writeBool(isValid);
  });

  /// Reads [AutoRequestData.encode]; `null` when the bytes are not a valid value.
  static AutoRequestData? decode(List<int> bytes, StackWire wire) {
    try {
      return PacketBuffer.decode(bytes, (r) {
        final request = wire.readOrderWithCrafts(r);
        final address = r.readString();
        final offset = blockPosFromLong(r.readLong());
        final dim = r.readString();
        final valid = r.readBool();
        return AutoRequestData(request, address, offset, dim, valid);
      });
    } on Object {
      return null;
    }
  }
}

/// `BlockPos.asLong`.
int blockPosAsLong((int, int, int) pos) =>
    ((pos.$1 & 0x3FFFFFF) << 38) |
    ((pos.$3 & 0x3FFFFFF) << 12) |
    (pos.$2 & 0xFFF);

/// `BlockPos.of(long)`.
(int, int, int) blockPosFromLong(int packed) =>
    (packed >> 38, (packed << 52) >> 52, (packed << 26) >> 38);

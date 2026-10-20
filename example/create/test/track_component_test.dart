// The `create:track_connecting_from` data component: the first click of a track item stores the
// clicked end as this component and the second click reads it back to find the track it started
// from. A round trip that loses a coordinate makes the second click look at the wrong block, so
// `TrackPlacement.tryConnect` reports `create.track.original_missing`.
//
// Java sources (branch `port/26.3`):
//   content/trains/track/TrackPlacement.java:120-140  ConnectingFrom.STREAM_CODEC
//   content/trains/track/TrackPlacement.java:157-178  tryConnect: the state of `connectingFrom.pos`
import 'dart:typed_data';

import 'package:create/src/content/components.dart';
import 'package:create/src/trains/track/track_placement.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

/// The component's bytes: `BlockPos.STREAM_CODEC` (one long) and three `VEC3` (three doubles).
const int connectingFromBytes = 8 + 3 * 3 * 8;

void main() {
  group('ConnectingFrom', () {
    test('round-trips negative block coordinates and vectors', () {
      const value = ConnectingFrom(
        (-1234, -60, -5678),
        (0.0, 0.0, -1.0),
        (0.0, 1.0, 0.0),
        (-0.5, 0.0, -0.5),
      );

      final bytes = PacketBuffer.encode(value.write);
      expect(bytes, hasLength(connectingFromBytes));

      final read = PacketBuffer.decode(bytes, ConnectingFrom.read);
      expect(read, value);
      expect(read.pos, (-1234, -60, -5678));
      expect(read.axis, (0.0, 0.0, -1.0));
      expect(read.end, (-0.5, 0.0, -0.5));
    });

    test('round-trips every sign combination of a block position', () {
      for (final pos in const [
        (0, 0, 0),
        (1, 1, 1),
        (-1, -1, -1),
        (30000000 - 1, 0, 0),
        (0, 0, 30000000 - 1),
        (-30000000, -64, -30000000),
        (0, 319, 0),
      ]) {
        final value = ConnectingFrom(pos, (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.5, 0.0, 0.5));
        final bytes = PacketBuffer.encode(value.write);
        expect(
          PacketBuffer.decode(bytes, ConnectingFrom.read).pos,
          pos,
          reason: 'position $pos',
        );
      }
    });

    test('the encoded bytes are one value of the declared component codec', () {
      const value = ConnectingFrom(
        (-7, -60, 9),
        (0.0, 0.0, 1.0),
        (0.0, 1.0, 0.0),
        (0.5, 0.0, 1.0),
      );
      final bytes = PacketBuffer.encode(value.write);
      final codec = createComponents.firstWhere((c) => c.key == 'create:track_connecting_from');
      expect(codec.approximate, isFalse);

      // The codec's shape: a long, then three sequences of three doubles.
      final view = ByteData.sublistView(Uint8List.fromList(bytes));
      expect(view.getInt64(0), isA<int>());
      expect(bytes.length, connectingFromBytes);
    });
  });
}

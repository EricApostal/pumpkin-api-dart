import 'package:create/src/redstone/nixie/nixie_logic.dart';
import 'package:test/test.dart';

void main() {
  group('nixie computer signal', () {
    test('a tube display starts at the Java defaults', () {
      final tube = TubeDisplay();
      expect(
        (
          tube.r,
          tube.g,
          tube.b,
          tube.blinkPeriod,
          tube.blinkOffTime,
          tube.glowWidth,
          tube.glowHeight,
        ),
        (63, 63, 63, 0, 0, 1, 1),
      );
    });

    test('two displays encode into 14 bytes and decode back', () {
      final signal = ComputerSignal()
        ..first = TubeDisplay(
          r: 1,
          g: 2,
          b: 3,
          blinkPeriod: 4,
          blinkOffTime: 5,
          glowWidth: 6,
          glowHeight: 7,
        )
        ..second = TubeDisplay(
          r: 8,
          g: 9,
          b: 10,
          blinkPeriod: 11,
          blinkOffTime: 12,
          glowWidth: 13,
          glowHeight: 14,
        );
      final encoded = signal.encode();
      expect(encoded.length, TubeDisplay.encodedSize * 2);
      expect(encoded.take(7), [1, 2, 3, 4, 5, 6, 7]);
      expect(encoded.skip(7), [8, 9, 10, 11, 12, 13, 14]);

      final decoded = ComputerSignal()..decode(encoded);
      expect(decoded.first, signal.first);
      expect(decoded.second, signal.second);
    });

    test('signed bytes are read as unsigned', () {
      final encoded = List<int>.filled(TubeDisplay.encodedSize * 2, 0);
      encoded[0] = -1; // 255
      encoded[1] = -128; // 128
      final decoded = ComputerSignal()..decode(encoded);
      expect(decoded.first.r, 255);
      expect(decoded.first.g, 128);
    });

    test('a short array leaves the displays at their defaults', () {
      final decoded = ComputerSignal()
        ..first = TubeDisplay(r: 5)
        ..second = TubeDisplay(r: 6);
      decoded.decode(const [1, 2, 3]);
      expect(decoded.first.r, 5);
      expect(decoded.second.r, 6);
    });

    test('encoding writes into an existing array at an offset', () {
      final data = List<int>.filled(14, 0);
      TubeDisplay(r: 10, g: 20).encode(data, TubeDisplay.encodedSize);
      expect(data[7], 10);
      expect(data[8], 20);
      expect(data[0], 0);
    });
  });
}

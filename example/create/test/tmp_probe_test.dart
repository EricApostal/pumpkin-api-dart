import 'package:create/src/trains/track/track_placement.dart';
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:test/test.dart';

void main() {
  test('ConnectingFrom component bytes match its codec', () {
    const from = ConnectingFrom((1, 2, 3), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (0.5, 0.0, 1.0));
    final bytes = PacketBuffer.encode(from.write);
    final back = PacketBuffer.decode(bytes, ConnectingFrom.read);
    expect(back, from);

    final vec3 = ComponentCodec.sequence([ComponentCodec.float64, ComponentCodec.float64, ComponentCodec.float64]);
    final codec = ComponentCodec.sequence([
      ComponentCodec.long,
      vec3,
      vec3,
      vec3,
    ]);
    print('measure=${codec.measure(bytes)} bytes=${bytes.length}');
    expect(codec.measure(bytes), bytes.length);
  });
}

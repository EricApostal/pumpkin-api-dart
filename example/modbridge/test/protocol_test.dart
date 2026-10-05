import 'package:modbridge/src/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('codecs round trip', () {
    final hello = Protocol.hello.decode(
      Protocol.hello.encode(const Hello(1, 'Pumpkin')),
    );
    expect((hello.protocol, hello.serverName), (1, 'Pumpkin'));

    final ack = Protocol.ack.decode(Protocol.ack.encode(const Ack(1, '1.0.0')));
    expect((ack.protocol, ack.modVersion), (1, '1.0.0'));

    final pong = Protocol.pong.decode(
      Protocol.pong.encode(const Pong(-5, 123456789012)),
    );
    expect((pong.nonce, pong.serverTick), (-5, 123456789012));

    final toast = Protocol.toast.decode(
      Protocol.toast.encode(const Toast('Hé', 'ünïcode ✓')),
    );
    expect((toast.title, toast.message), ('Hé', 'ünïcode ✓'));
  });

  test('wire format matches the documented layout', () {
    expect(Protocol.ping.encode(const Ping(1)), [0, 0, 0, 0, 0, 0, 0, 1]);
    expect(Protocol.ack.encode(const Ack(1, 'ab')), [1, 2, 0x61, 0x62]);
  });

  test('judge', () {
    expect(judge(null), HandshakeOutcome.noMod);
    expect(judge(const Ack(1, 'x')), HandshakeOutcome.accepted);
    expect(judge(const Ack(2, 'x')), HandshakeOutcome.wrongProtocol);
  });

  test('ModUsers', () {
    final users = ModUsers()..accept('u', '1.0');
    expect(users.has('u'), isTrue);
    expect(users.versionOf('u'), '1.0');
    users.remove('u');
    expect(users.count, 0);
  });
}

// The host side of payload channels: sends over `sendCustomPayload`, receives
// through one `Events.playerCustomPayload` listener. The descriptors and codecs
// are in `payload.dart` (pure); channels are declared on `CreateRegistry`.
import 'package:pumpkin_api/pumpkin_api.dart';

import 'payload.dart';

final class CreateNetwork {
  final PayloadRegistry<Player> payloads;
  final Logger log;

  CreateNetwork(this.payloads, this.log);

  /// Connects the clientbound channels to the host and starts dispatching the
  /// serverbound ones.
  void install(Context context) {
    for (final channel in payloads.clientboundChannels) {
      channel.attach(_send);
    }
    context.listen(Events.playerCustomPayload, (server, event) async {
      final channel = payloads.serverboundFor(event.channel);
      if (channel == null) return;
      try {
        await channel.dispatch(event.player, event.data);
      } on PacketException catch (e) {
        log.warn('Dropped an invalid payload on ${event.channel} from ${event.player.getName()}: $e');
      } catch (e, s) {
        log.error('Handler of ${event.channel} failed', error: e, stackTrace: s);
      }
    });
  }

  Future<void> _send(Player player, String channel, List<int> data) async {
    final java = player.asJava();
    if (java == null) return; // Bedrock players have no custom payloads.
    try {
      await java.sendCustomPayload(channel: channel, data: data);
    } finally {
      java.dispose();
    }
  }
}

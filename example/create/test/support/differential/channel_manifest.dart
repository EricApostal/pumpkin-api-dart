// The channel set a Create client answers the `NeoForge` handshake with.
//
// This is the client side of the negotiation, built from the plugin's own payload registry — the
// same table `registerPayloadChannels` declares, which is extracted from the Java mod's
// registration and pinned by the manifest tests. A parity test asks both servers the same question
// with it: *does a client that has Create, and nothing else, join you?*
//
// It is written in the format `pumpkin-tester client --query` takes (the bot adds `NeoForge`'s own
// registrations itself), so it can also be used by hand:
//
// ```sh
// pumpkin-tester client --addr 127.0.0.1:25566 --name Probe --trace /tmp/probe.jsonl \
//   --query /tmp/create-channels.json
// ```

import 'dart:convert';
import 'dart:io';

import 'package:create/src/core/payload.dart';
import 'package:create/src/protocol/codec_compiler.dart';
import 'package:create/src/protocol/payload_hub.dart';

/// The channels Create registers, in registration order.
///
/// The hub is built with a sink that throws away its messages: nothing is handled here, the
/// registry is only asked what it declared.
List<DeclaredPayload> createDeclaredChannels() {
  final payloads = PayloadRegistry<Object>();
  final hub = PayloadHub<Object>(
    schemas: PayloadSchemas.manifest,
    sink: (_, _) {},
    describePlayer: (_) => 'probe',
  );
  registerPayloadChannels(payloads, hub);
  return payloads.declared;
}

/// The `--query` file for [channels], written to [file] and returned.
/// Only the mod's own channels are listed: `NeoForge`'s registrations are added by the bot, because
/// every `NeoForge` client has them (and the registry synchronisation is refused without them).
File writeChannelQuery(File file, List<DeclaredPayload> channels) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'channels': [
        for (final channel in channels)
          {
            'id': channel.id,
            'version': channel.version,
            'phase': 'play',
            'flow': channel.serverbound ? 'serverbound' : 'clientbound',
            'optional': channel.optional,
          },
      ],
    })}\n',
  );
  return file;
}

/// The client a Create client is: [writeChannelQuery] with Create's own channels, in [directory].
///
/// This is what makes two arms comparable: both clients answer the `NeoForge` handshake with the
/// same set, so a difference in what the servers send is a difference in the servers. A vanilla
/// client on one arm and a modded one on the other would differ by construction (the host sends
/// `neoforge:auxiliary_light_data` only to a `NeoForge` client), and the comparison would report
/// the harness's choice as the plugin's.
File createChannelQuery(Directory directory) => writeChannelQuery(
  File('${directory.path}/create-channels.json'),
  createDeclaredChannels(),
);

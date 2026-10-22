// Offroad as an addon of Create's declaration model: the mod id and the payload
// channels of `network/offroad_channels.dart`, contributed through Create's
// generic hook. Nothing here names Offroad in Create.
//
// Host: this file uses `pumpkin_api` (through `package:create/create.dart`).
import 'package:create/create.dart' show CreateAddon, DeclaredPayload;

import '../index/offroad_ids.dart';
import '../network/offroad_channels.dart';

/// The mod Offroad declares.
final class OffroadAddon extends CreateAddon {
  const OffroadAddon();

  @override
  String get modId => offroadModId;

  @override
  String get version => '0.1.0';

  @override
  String get displayName => 'Offroad';

  /// The registries Offroad registers content in are the client's: the ids are positions in the
  /// host's dynamic registry, and a client that is not sent the host's order resolves every id
  /// past the vanilla entries to a different entry. See `AeronauticsAddon.contentVerified`.
  @override
  bool get contentVerified => true;

  @override
  Iterable<DeclaredPayload> get channels => offroadChannels;
}

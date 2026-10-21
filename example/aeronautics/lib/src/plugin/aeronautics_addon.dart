// Aeronautics as an addon of Create's declaration model: the mod id and the
// payload channels of `aeronautics_channels.dart`, contributed through Create's
// generic hook. Nothing here names Aeronautics in Create.
//
// Host: this file uses `pumpkin_api` (through `package:create/create.dart`).
import 'package:create/create.dart' show CreateAddon, DeclaredPayload;

import '../../aeronautics_channels.dart';

/// The mod Aeronautics declares.
final class AeronauticsAddon extends CreateAddon {
  const AeronauticsAddon();

  @override
  String get modId => aeronauticsModId;

  @override
  String get version => '0.1.0';

  @override
  String get displayName => 'Aeronautics';

  @override
  Iterable<DeclaredPayload> get channels => aeronauticsChannels;
}

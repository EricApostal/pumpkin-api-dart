// The network channels CC: Tweaked registers (`NetworkMessages`), and how they
// are announced to a NeoForge client.
//
// All of them are play-phase payloads of the mod id `computercraft`,
// registered through `registrar.versioned(<mod version>)` and *not*
// `.optional()`: a client with the mod refuses a server that does not
// announce them in `neoforge:network` with the same version string.
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart';

abstract final class CcChannels {
  static const String namespace = 'computercraft';

  // Serverbound (player -> server).
  static const String computerAction = 'computercraft:computer_action';
  static const String keyEvent = 'computercraft:key_event';
  static const String mouseEvent = 'computercraft:mouse_event';
  static const String pasteEvent = 'computercraft:paste_event';
  static const String uploadFile = 'computercraft:upload_file';

  // Clientbound (server -> player).
  static const String chatTable = 'computercraft:chat_table';
  static const String pocketComputerData = 'computercraft:pocket_computer_data';
  static const String pocketComputerDeleted = 'computercraft:pocket_computer_deleted';
  static const String computerTerminal = 'computercraft:computer_terminal';
  static const String playRecord = 'computercraft:play_record';
  static const String monitorClient = 'computercraft:monitor_client';
  static const String speakerAudio = 'computercraft:speaker_audio';
  static const String speakerMove = 'computercraft:speaker_move';
  static const String speakerPlay = 'computercraft:speaker_play';
  static const String speakerStop = 'computercraft:speaker_stop';
  static const String uploadResult = 'computercraft:upload_result';

  /// NeoForge's own payload that opens menus with extra data.
  static const String advancedOpenScreen = 'neoforge:advanced_open_screen';

  static const List<String> serverbound = [
    computerAction,
    keyEvent,
    mouseEvent,
    pasteEvent,
    uploadFile,
  ];

  static const List<String> clientbound = [
    chatTable,
    pocketComputerData,
    pocketComputerDeleted,
    computerTerminal,
    playRecord,
    monitorClient,
    speakerAudio,
    speakerMove,
    speakerPlay,
    speakerStop,
    uploadResult,
  ];

  /// The channel declarations for `NeoForgeServerSpec.channels`: every
  /// channel in the play phase, required, with the mod's [version].
  static List<PayloadChannelSpec> specs(String version) => [
    for (final id in serverbound)
      PayloadChannelSpec(
        id: id,
        version: version,
        phases: const {NetworkPhase.play},
        flow: PacketFlow.serverbound,
      ),
    for (final id in clientbound)
      PayloadChannelSpec(
        id: id,
        version: version,
        phases: const {NetworkPhase.play},
        flow: PacketFlow.clientbound,
      ),
  ];
}

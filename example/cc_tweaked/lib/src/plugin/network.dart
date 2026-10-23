// The player-facing side of a computer's GUI: opens the `computercraft:computer`
// menu through the host (`PluginMenus.openPluginMenu`, which sends the
// `neoforge:advanced_open_screen` payload for a menu with extra data), keeps the
// "sessions" that tie a player with a GUI open to that computer, pushes terminal
// changes to them (`computer_terminal`), and feeds the serverbound payloads
// (key, mouse, paste, action, file upload) to the machine.
//
// Unverified against a live client and a built host: docs/host-requirements.md
// lists the byte level assumptions.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show NbtText, VanillaRegistries;

import '../machine/computer.dart';
import '../machine/input.dart';
import '../machine/peripherals.dart' show SpeakerSink, SpeakerSound, SpeakerAudioChunk;
import '../machine/transfer.dart';
import '../protocol/channels.dart';
import '../protocol/menu_data.dart';
import '../protocol/messages.dart';
import '../protocol/registries.dart';
import '../protocol/terminal_state.dart';
import '../protocol/upload.dart';
import 'records.dart';

/// A player with a computer's GUI open.
final class ComputerSession {
  final String playerUuid;
  final Computer computer;
  final int containerId;
  final ComputerInput input;

  /// The block the computer stands in: the menu closes when the player walks
  /// away from it (`stillValid`). `null` for a pocket computer. A turtle's
  /// moves update it ([CcNetwork.relocate]).
  ComputerLocation? at;

  final UploadAssembler uploads = UploadAssembler();
  TerminalState? lastSent;
  bool lastOn;

  ComputerSession(
    this.playerUuid,
    this.computer,
    this.containerId,
    this.input, {
    this.at,
    required this.lastOn,
  });
}

/// The furthest a player may be from the block of the computer they use, in
/// blocks (`Container.stillValidBlockEntity` with CC's buffer: 4.5 + 4, plus
/// half a block diagonal because the distance is measured from the centre).
const double _maxUseDistance = 9.5;

/// The `source` UUID of a speaker: the client keys everything it plays by it,
/// so one speaker keeps one for as long as it exists and a `play`/`audio`/`stop`
/// sequence matches (`SpeakerPeripheral.getSource`).
///
/// Java makes a `UUID.randomUUID()`; the host has no UUID generator, so this
/// makes one from the clock and a counter. It is unique for the life of the
/// server, which is all the client needs (it forgets a source that stops).
String newSpeakerSource() {
  final seed = _speakerSeed + _speakerCounter++;
  final rng = math.Random(seed);
  final high = (rng.nextInt(1 << 32) << 32) | rng.nextInt(1 << 32);
  final low = (rng.nextInt(1 << 32) << 32) | rng.nextInt(1 << 32);
  String hex(int value, int digits) => value.toUnsigned(digits * 4).toRadixString(16).padLeft(digits, '0');
  final all = hex(high, 16) + hex(low, 16);
  return '${all.substring(0, 8)}-${all.substring(8, 12)}-${all.substring(12, 16)}-'
      '${all.substring(16, 20)}-${all.substring(20)}';
}

final int _speakerSeed = DateTime.now().microsecondsSinceEpoch;
int _speakerCounter = 0;

/// A [SpeakerSink] that sends CC's speaker payloads to the players that can
/// hear the speaker (Java: `ServerNetworking.sendToAllAround(pos, volume * 16)`
/// for a note, `sendToAllTracking(chunk)` for audio, `sendToAllPlayers` for a
/// stop).
///
/// Java decides who hears a note by the sound radius (`volume * 16`) and audio
/// by chunk tracking; this port uses a fixed radius for both, so a quiet note
/// reaches a few players more than a client renders. The sends are not awaited
/// (the speaker is ticked, not called from a host callback); a failure is
/// logged and does not stop the others.
///
/// The dimension the payload names is the world of the player receiving it:
/// everyone sent to is in the speaker's world, and the host has no dimension
/// for a world name without a world handle. So the sink is given the world's
/// *name* (what [ComputerLocation.world] holds) and [server] is set by whoever
/// ticks the speaker.
final class CcSpeakerSink implements SpeakerSink {
  final CcNetwork _network;
  final String source;

  /// The name of the world the speaker is in (`World.getName`).
  final String worldName;

  /// Where the speaker is, asked each time it matters (a turtle's speaker moves).
  final (double, double, double) Function() at;

  /// The entity the speaker follows, if it follows one (a pocket computer in a
  /// player's hand).
  final int? entityId;

  /// The server, set by the tick that drives the speaker before [update].
  Server? server;

  CcSpeakerSink(this._network, this.source, this.worldName, this.at, {this.entityId});

  /// How far the players that hear the speaker are, in blocks.
  static const double _hearRadius = 64;

  void _send(double radius, Future<void> Function(Player, SpeakerPositionMessage) send) {
    final server = this.server;
    if (server == null) return;
    final position = at();
    for (final player in server.playersNear(position, radius, worldName: worldName)) {
      unawaited(() async {
        try {
          final world = player.getWorld();
          final String dimension;
          try {
            dimension = world.getDimension();
          } finally {
            world.dispose();
          }
          await send(player, SpeakerPositionMessage(dimension, position, entityId));
        } catch (e) {
          logger.warn('Could not send a speaker payload to ${player.getName()}: $e');
        } finally {
          player.dispose();
        }
      }());
    }
  }

  @override
  void play(SpeakerSound sound) {
    final volume = sound.volume;
    _send(
      volume * 16 > _hearRadius ? volume * 16 : _hearRadius,
      (player, position) => _network._speakerPlay.send(
        player,
        SpeakerPlayMessage(source, position, sound.id, volume, sound.pitch),
      ),
    );
  }

  @override
  void playAudio(SpeakerAudioChunk chunk) => _send(
    _hearRadius,
    (player, position) => _network._speakerAudio.send(
      player,
      SpeakerAudioMessage(
        source,
        position,
        chunk.charge,
        chunk.strength,
        chunk.previousBit,
        chunk.audio,
        chunk.volume,
      ),
    ),
  );

  @override
  void stop() {
    final server = this.server;
    if (server == null) return;
    for (final player in server.allPlayers) {
      unawaited(() async {
        try {
          await _network._speakerStop.send(player, SpeakerStopMessage(source));
        } catch (e) {
          logger.warn('Could not stop a speaker for ${player.getName()}: $e');
        } finally {
          player.dispose();
        }
      }());
    }
  }

  @override
  void moved() => _send(
    _hearRadius,
    (player, position) => _network._speakerMove.send(player, SpeakerMoveMessage(source, position)),
  );
}

final class CcNetwork {
  final Map<String, ComputerSession> _sessions = {};
  final CcRegistryIds _ids = CcRegistryIds();
  final List<(String, int)> _pendingConsumed = [];
  int _ticks = 0;

  /// Whether a [tick] is still waiting for the host.
  bool _ticking = false;

  /// Whether a player's connection can open CC's GUI: it answered the
  /// NeoForge handshake and registered CC's channels. The plugin sets it when
  /// the handshake is installed; by default every player is let through (the
  /// host does not check either).
  bool Function(Player player) canOpenGui = (_) => true;

  final TypedChannel<ComputerActionMessage> _action = TypedChannel(
    CcChannels.computerAction,
    ComputerActionMessage.codec,
  );
  final TypedChannel<KeyEventMessage> _key = TypedChannel(CcChannels.keyEvent, KeyEventMessage.codec);
  final TypedChannel<MouseEventMessage> _mouse = TypedChannel(CcChannels.mouseEvent, MouseEventMessage.codec);
  final TypedChannel<PasteEventMessage> _paste = TypedChannel(CcChannels.pasteEvent, PasteEventMessage.codec);
  final TypedChannel<UploadFileMessage> _upload = TypedChannel(
    CcChannels.uploadFile,
    UploadFileMessage.codecWith(),
  );
  final TypedChannel<UploadResultMessage> _uploadResult = TypedChannel(
    CcChannels.uploadResult,
    UploadResultMessage.codec,
  );
  final TypedChannel<ComputerTerminalMessage> _terminal = TypedChannel(
    CcChannels.computerTerminal,
    ComputerTerminalMessage.codec,
  );

  /// A monitor's screen. The monitor block entities (`CcWorldMonitors`) send
  /// on it; nothing else does.
  final TypedChannel<MonitorMessage> monitor = TypedChannel(
    CcChannels.monitorClient,
    MonitorMessage.codec,
  );

  final TypedChannel<SpeakerPlayMessage> _speakerPlay = TypedChannel(
    CcChannels.speakerPlay,
    SpeakerPlayMessage.codec,
  );
  final TypedChannel<SpeakerAudioMessage> _speakerAudio = TypedChannel(
    CcChannels.speakerAudio,
    SpeakerAudioMessage.codec,
  );
  final TypedChannel<SpeakerStopMessage> _speakerStop = TypedChannel(
    CcChannels.speakerStop,
    SpeakerStopMessage.codec,
  );
  final TypedChannel<SpeakerMoveMessage> _speakerMove = TypedChannel(
    CcChannels.speakerMove,
    SpeakerMoveMessage.codec,
  );

  CcNetwork();

  /// Number of players with a computer open.
  int get sessionCount => _sessions.length;

  /// Whether the player with [playerUuid] has a computer open.
  bool hasSession(String playerUuid) => _sessions.containsKey(playerUuid);

  /// Listens for the serverbound messages of an open computer GUI and for the
  /// menu closing.
  void install(Context context) {
    _action.listen(context, (player, message) {
      final session = _sessionFor(player, message.containerId);
      if (session == null) return;
      switch (message.action) {
        case ComputerAction.terminate:
          session.computer.queueEvent('terminate', const []);
        case ComputerAction.turnOn:
          session.computer.turnOn();
        case ComputerAction.shutdown:
          session.computer.shutdown();
        case ComputerAction.reboot:
          session.computer.reboot();
      }
    });
    _key.listen(context, (player, message) {
      final session = _sessionFor(player, message.containerId);
      if (session == null) return;
      switch (message.action) {
        case KeyAction.down:
          session.input.keyDown(message.key);
        case KeyAction.repeat:
          session.input.keyDown(message.key, repeat: true);
        case KeyAction.up:
          session.input.keyUp(message.key);
        case KeyAction.char:
          session.input.charTyped(message.key);
      }
    });
    _mouse.listen(context, (player, message) {
      final session = _sessionFor(player, message.containerId);
      if (session == null) return;
      switch (message.action) {
        case MouseAction.click:
          session.input.mouseClick(message.argument, message.x, message.y);
        case MouseAction.drag:
          session.input.mouseDrag(message.argument, message.x, message.y);
        case MouseAction.up:
          session.input.mouseUp(message.argument, message.x, message.y);
        case MouseAction.scroll:
          session.input.mouseScroll(message.argument, message.x, message.y);
      }
    });
    _paste.listen(context, (player, message) {
      final session = _sessionFor(player, message.containerId);
      session?.input.paste(String.fromCharCodes(message.text));
    });
    _upload.listen(context, (player, message) async {
      final session = _sessionFor(player, message.containerId);
      if (session != null) await _receiveUpload(player, session, message);
    });
    context.listen(Events.menuClosed, (server, event) {
      final uuid = event.player.getId().asString;
      final session = _sessions[uuid];
      if (session != null && session.containerId == event.containerId) close(uuid);
    });
    context.listen(Events.playerLeave, (server, event) {
      close(event.player.getId().asString);
    });
  }

  ComputerSession? _sessionFor(Player player, int containerId) {
    final session = _sessions[player.getId().asString];
    return session != null && session.containerId == containerId ? session : null;
  }

  // -- Uploads (`ServerInputState.startUpload` / `finishUpload`) ------------------

  Future<void> _receiveUpload(Player player, ComputerSession session, UploadFileMessage message) async {
    final List<UploadedFile>? files;
    try {
      files = session.uploads.accept(message);
    } on StateError catch (e) {
      logger.warn('${player.getName()}: upload rejected: ${e.message}');
      await _sendUploadResult(
        player,
        UploadResultMessage(
          session.containerId,
          UploadResultKind.error,
          NbtText.translatable('gui.computercraft.upload.failed.corrupted'),
        ),
      );
      return;
    }
    if (files == null || files.isEmpty) return;
    final uuid = session.playerUuid;
    final containerId = session.containerId;
    session.computer.queueRawEvent('file_transfer', [
      buildTransferredFiles(
        [for (final f in files) TransferredFileData(f.name, f.bytes)],
        () => _pendingConsumed.add((uuid, containerId)),
      ),
    ]);
    await _sendUploadResult(player, UploadResultMessage(containerId, UploadResultKind.queued));
  }

  Future<void> _sendUploadResult(Player player, UploadResultMessage message) async {
    try {
      await _uploadResult.send(player, message);
    } on UnsupportedError {
      // A Bedrock player: nothing to tell.
    }
  }

  // -- Opening --------------------------------------------------------------------

  /// What the client shows as the title of a computer menu: the label, or the
  /// translated name (`ComputerBlockEntity.getName`).
  static TextComponent titleOf(String? label, String translationKey) => label != null && label.isNotEmpty
      ? Text(label).build()
      : TextComponent.translate(key: translationKey, with_: const []);

  /// The stack `ComputerContainerData` carries (what `collectSafeComponents`
  /// of the block entity gives): the item with the computer's id and label.
  WireItemStack displayStack(String itemName, Computer computer, [List<ComponentEntry> extra = const []]) {
    final customName = VanillaRegistries.require('minecraft:data_component_type').indexOf('minecraft:custom_name');
    final label = computer.label;
    return WireItemStack(
      _ids.idOf('minecraft:item', itemName),
      components: [
        ComponentEntry.varInt(_ids.idOf('minecraft:data_component_type', 'computer_id'), computer.id),
        if (label != null && customName >= 0) ComponentEntry.text(customName, NbtText.literal(label)),
        ...extra,
      ],
    );
  }

  /// The numeric id of CC's data component type [name] (`left_turtle_upgrade`).
  int componentTypeId(String name) => _ids.idOf('minecraft:data_component_type', name);

  /// Opens the GUI of [computer] for [player] and returns the container id, or
  /// `null` when the player's connection cannot show it.
  ///
  /// The menu is opened through the host with the `ComputerContainerData` as
  /// extra data: the host sends `neoforge:advanced_open_screen` (window id,
  /// menu type id, title, extra data) instead of the vanilla open screen packet.
  /// No slots are tracked by the host: the client's menu has nine invisible
  /// slots over the hotbar that its own inventory fills.
  ///
  /// [itemName] names the item of the display stack (`computer_advanced`,
  /// `pocket_computer_normal`, ...), [menu] the menu type key, [at] the block
  /// the player must stay near. A menu with slots of its own (the turtle's)
  /// passes [slots] (the number the host tracks) and [extraComponents] for the
  /// display stack.
  int? open(
    Player player,
    Computer computer, {
    String? itemName,
    String menu = 'computercraft:computer',
    String? titleKey,
    ComputerLocation? at,
    bool turnOn = true,
    int slots = 0,
    List<ComponentEntry> extraComponents = const [],
  }) {
    if (!canOpenGui(player)) return null;
    final uuid = player.getId().asString;
    close(uuid);
    final advanced = computer.family == ComputerFamily.advanced;
    final item = itemName ?? (advanced ? 'computer_advanced' : 'computer_normal');
    final terminal = TerminalState.of(computer.terminal);
    final data = ComputerContainerData(
      family: advanced ? WireFamily.advanced : WireFamily.normal,
      terminal: terminal,
      displayStack: displayStack(item, computer, extraComponents),
    );
    final key = titleKey ?? (item.startsWith('pocket_') ? 'item.computercraft.$item' : 'block.computercraft.$item');
    final containerId = player.openPluginMenu(menu, titleOf(computer.label, key), extraData: data.encode(), slots: slots);
    final session = ComputerSession(
      uuid,
      computer,
      containerId,
      computer.createInput(),
      at: at,
      lastOn: computer.isOn,
    )..lastSent = terminal;
    _sessions[uuid] = session;
    if (turnOn) computer.turnOn();
    _sendOn(player, session);
    return containerId;
  }

  /// `AbstractComputerMenu`'s data slot 0: `isOn`.
  void _sendOn(Player player, ComputerSession session) {
    try {
      player.setPluginMenuData(0, session.computer.isOn ? 1 : 0);
      session.lastOn = session.computer.isOn;
    } on PluginRegistryException catch (e) {
      logger.warn('Could not send the power state of computer #${session.computer.id}: ${e.message}');
    }
  }

  /// Ends the session of [playerUuid]: releases keys and buttons still held.
  void close(String playerUuid) {
    _sessions.remove(playerUuid)?.input.releaseInputs();
  }

  /// A turtle moved: its open GUIs now need the player near [location].
  void relocate(int computerId, ComputerLocation location) {
    for (final session in _sessions.values) {
      if (session.computer.id == computerId && session.at != null) session.at = location;
    }
  }

  /// Closes the menus of every player that has [computerId] open (its block
  /// was removed or its chunk unloaded).
  void closeAllFor(Server server, int computerId) {
    for (final session in _sessions.values.toList()) {
      if (session.computer.id != computerId) continue;
      final player = server.getPlayerByUuid(id: Uuids.parse(session.playerUuid));
      close(session.playerUuid);
      if (player == null) continue;
      try {
        player.closePluginMenu();
      } finally {
        player.dispose();
      }
    }
  }

  // -- The server tick ------------------------------------------------------------

  /// Sends changed terminals and the power state to the players looking at them
  /// (every other tick), and closes menus that are no longer valid.
  ///
  /// The sends wait for the host: a tick that comes while the previous one is
  /// still sending is skipped.
  Future<void> tick(Server server) async {
    if (_sessions.isEmpty || _ticking) return;
    _ticking = true;
    try {
      if (_pendingConsumed.isNotEmpty) await _flushConsumed(server);
      if (++_ticks % 2 != 0) return;
      for (final session in _sessions.values.toList()) {
        final player = server.getPlayerByUuid(id: Uuids.parse(session.playerUuid));
        if (player == null) {
          close(session.playerUuid);
          continue;
        }
        try {
          await _tickSession(player, session);
        } on UnsupportedError {
          close(session.playerUuid);
        } finally {
          player.dispose();
        }
      }
    } catch (e, s) {
      // Nobody awaits the tick (see plugin.dart): log instead of losing the error.
      logger.error('The network tick failed: $e\n$s');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tickSession(Player player, ComputerSession session) async {
    // The menu is only valid while the computer exists and the player is near.
    final at = session.at;
    var valid = !session.computer.isClosed;
    if (valid && at != null) {
      final (px, py, pz) = player.getPosition();
      final dx = px - (at.x + 0.5);
      final dy = py - (at.y + 0.5);
      final dz = pz - (at.z + 0.5);
      valid = dx * dx + dy * dy + dz * dz <= _maxUseDistance * _maxUseDistance;
    }
    if (valid) {
      // A menu the player replaced ends with `menu-closed`; this only guards
      // against a container id that is not ours any more.
      final open = player.currentPluginMenu;
      valid = open != null && open.containerId == session.containerId;
    }
    if (!valid) {
      close(session.playerUuid);
      player.closePluginMenu();
      return;
    }
    final state = TerminalState.of(session.computer.terminal);
    final last = session.lastSent;
    if (last == null || !last.sameAs(state)) {
      await _terminal.send(player, ComputerTerminalMessage(session.containerId, state));
      session.lastSent = state;
    }
    if (session.lastOn != session.computer.isOn) _sendOn(player, session);
  }

  Future<void> _flushConsumed(Server server) async {
    final pending = List.of(_pendingConsumed);
    _pendingConsumed.clear();
    for (final (uuid, containerId) in pending) {
      final player = server.getPlayerByUuid(id: Uuids.parse(uuid));
      if (player == null) continue;
      try {
        await _sendUploadResult(player, UploadResultMessage(containerId, UploadResultKind.consumed));
      } finally {
        player.dispose();
      }
    }
  }
}

// The player-facing side of a computer's GUI: opens the `computercraft:computer`
// menu through the host (`PluginMenus.openPluginMenu`, which sends the
// `neoforge:advanced_open_screen` payload for a menu with extra data), keeps the
// "sessions" that tie a player with a GUI open to that computer, pushes terminal
// changes to them (`computer_terminal`), and feeds the serverbound payloads
// (key, mouse, paste, action, file upload) to the machine.
//
// Unverified against a live client and a built host: docs/host-requirements.md
// lists the byte level assumptions.
import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show NbtText, VanillaRegistries;

import '../machine/computer.dart';
import '../machine/input.dart';
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
  /// away from it (`stillValid`). `null` for a pocket computer.
  final ComputerLocation? at;

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

final class CcNetwork {
  final Map<String, ComputerSession> _sessions = {};
  final CcRegistryIds _ids = CcRegistryIds();
  final List<(String, int)> _pendingConsumed = [];
  int _ticks = 0;

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
    _upload.listen(context, (player, message) {
      final session = _sessionFor(player, message.containerId);
      if (session != null) _receiveUpload(player, session, message);
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

  void _receiveUpload(Player player, ComputerSession session, UploadFileMessage message) {
    final List<UploadedFile>? files;
    try {
      files = session.uploads.accept(message);
    } on StateError catch (e) {
      logger.warn('${player.getName()}: upload rejected: ${e.message}');
      _sendUploadResult(
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
    _sendUploadResult(player, UploadResultMessage(containerId, UploadResultKind.queued));
  }

  void _sendUploadResult(Player player, UploadResultMessage message) {
    try {
      _uploadResult.send(player, message);
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
  WireItemStack displayStack(String itemName, Computer computer) {
    final customName = VanillaRegistries.require('minecraft:data_component_type').indexOf('minecraft:custom_name');
    final label = computer.label;
    return WireItemStack(
      _ids.idOf('minecraft:item', itemName),
      components: [
        ComponentEntry.varInt(_ids.idOf('minecraft:data_component_type', 'computer_id'), computer.id),
        if (label != null && customName >= 0) ComponentEntry.text(customName, NbtText.literal(label)),
      ],
    );
  }

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
  /// the player must stay near.
  int? open(
    Player player,
    Computer computer, {
    String? itemName,
    String menu = 'computercraft:computer',
    String? titleKey,
    ComputerLocation? at,
    bool turnOn = true,
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
      displayStack: displayStack(item, computer),
    );
    final key = titleKey ?? (item.startsWith('pocket_') ? 'item.computercraft.$item' : 'block.computercraft.$item');
    final containerId = player.openPluginMenu(menu, titleOf(computer.label, key), extraData: data.encode());
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
  void tick(Server server) {
    if (_sessions.isEmpty) return;
    if (_pendingConsumed.isNotEmpty) _flushConsumed(server);
    if (++_ticks % 2 != 0) return;
    for (final session in _sessions.values.toList()) {
      final player = server.getPlayerByUuid(id: Uuids.parse(session.playerUuid));
      if (player == null) {
        close(session.playerUuid);
        continue;
      }
      try {
        _tickSession(player, session);
      } on UnsupportedError {
        close(session.playerUuid);
      } finally {
        player.dispose();
      }
    }
  }

  void _tickSession(Player player, ComputerSession session) {
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
      _terminal.send(player, ComputerTerminalMessage(session.containerId, state));
      session.lastSent = state;
    }
    if (session.lastOn != session.computer.isOn) _sendOn(player, session);
  }

  void _flushConsumed(Server server) {
    final pending = List.of(_pendingConsumed);
    _pendingConsumed.clear();
    for (final (uuid, containerId) in pending) {
      final player = server.getPlayerByUuid(id: Uuids.parse(uuid));
      if (player == null) continue;
      try {
        _sendUploadResult(player, UploadResultMessage(containerId, UploadResultKind.consumed));
      } finally {
        player.dispose();
      }
    }
  }
}

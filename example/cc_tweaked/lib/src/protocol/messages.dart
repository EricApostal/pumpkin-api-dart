// The payloads of CC: Tweaked's channels (see channels.dart), as codecs. Each
// layout is taken from the `STREAM_CODEC` of the message class in the mod's
// source (mc-26.3, `shared/network/...`); docs/client-compat.md lists them.
//
// `RegistryFriendlyByteBuf` primitives: `VarInt`, strings and identifiers
// (`namespace:path` as a string), `bool`, `float`/`double` big endian, enums as
// VarInt ordinals, UUIDs as two longs, block positions packed in a long.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';
import 'package:pumpkin_neoforge/pumpkin_neoforge_core.dart' show NbtText;

import 'terminal_state.dart';

// -- Enums (ordinals are the wire values) -------------------------------------

/// `ComputerActionServerMessage.Action`.
enum ComputerAction { terminate, turnOn, shutdown, reboot }

/// `KeyEventServerMessage.Action`.
enum KeyAction { down, repeat, up, char }

/// `MouseEventServerMessage.Action`.
enum MouseAction { click, drag, up, scroll }

/// `ComputerFamily` as used in menu data.
enum WireFamily { normal, advanced, command }

/// `ComputerState`.
enum WireComputerState { off, on, blinking }

/// `UploadResult`.
enum UploadResultKind { queued, consumed, error }

T _enumAt<T>(List<T> values, int ordinal, String name) {
  if (ordinal < 0 || ordinal >= values.length) {
    throw PacketException('Unknown $name ordinal $ordinal');
  }
  return values[ordinal];
}

// -- Serverbound ----------------------------------------------------------------

/// Terminate, turn on, shut down or reboot the computer of an open menu.
final class ComputerActionMessage {
  final int containerId;
  final ComputerAction action;

  const ComputerActionMessage(this.containerId, this.action);

  static final PayloadCodec<ComputerActionMessage> codec = PayloadCodec.buffer(
    write: (w, m) => w
      ..writeVarInt(m.containerId)
      ..writeVarInt(m.action.index),
    read: (r) => ComputerActionMessage(
      r.readVarInt(),
      _enumAt(ComputerAction.values, r.readVarInt(), 'ComputerAction'),
    ),
  );
}

/// A key press, repeat, release or typed character. [key] is a GLFW key code,
/// or the character's byte for [KeyAction.char].
final class KeyEventMessage {
  final int containerId;
  final KeyAction action;
  final int key;

  const KeyEventMessage(this.containerId, this.action, this.key);

  static final PayloadCodec<KeyEventMessage> codec = PayloadCodec.buffer(
    write: (w, m) => w
      ..writeVarInt(m.containerId)
      ..writeVarInt(m.action.index)
      ..writeInt(m.key),
    read: (r) => KeyEventMessage(
      r.readVarInt(),
      _enumAt(KeyAction.values, r.readVarInt(), 'KeyAction'),
      r.readInt(),
    ),
  );
}

/// A mouse click, drag, release or scroll at a character cell (1-based).
/// [argument] is the button (1-3) or the scroll direction.
final class MouseEventMessage {
  final int containerId;
  final MouseAction action;
  final int argument;
  final int x;
  final int y;

  const MouseEventMessage(this.containerId, this.action, this.argument, this.x, this.y);

  static final PayloadCodec<MouseEventMessage> codec = PayloadCodec.buffer(
    write: (w, m) => w
      ..writeVarInt(m.containerId)
      ..writeVarInt(m.action.index)
      ..writeVarInt(m.argument)
      ..writeVarInt(m.x)
      ..writeVarInt(m.y),
    read: (r) => MouseEventMessage(
      r.readVarInt(),
      _enumAt(MouseAction.values, r.readVarInt(), 'MouseAction'),
      r.readVarInt(),
      r.readVarInt(),
      r.readVarInt(),
    ),
  );
}

/// Pasted text, at most 512 bytes of the terminal's character set.
final class PasteEventMessage {
  static const int maxLength = 512;

  final int containerId;
  final Uint8List text;

  const PasteEventMessage(this.containerId, this.text);

  static final PayloadCodec<PasteEventMessage> codec = PayloadCodec.buffer(
    write: (w, m) => w
      ..writeVarInt(m.containerId)
      ..writeByteArray(m.text, maxLength: maxLength - 1),
    read: (r) => PasteEventMessage(
      r.readVarInt(),
      r.readByteArray(maxLength: maxLength - 1),
    ),
  );
}

/// One file announced by the first message of an upload.
final class UploadFileHeader {
  final String name;
  final int size;

  /// SHA-256 of the content.
  final Uint8List checksum;

  const UploadFileHeader(this.name, this.size, this.checksum);
}

/// A piece of a file.
final class UploadSlice {
  final int fileId;
  final int offset;
  final Uint8List bytes;

  const UploadSlice(this.fileId, this.offset, this.bytes);
}

/// A file upload (drag and drop onto a terminal), in messages of up to 30 KiB.
final class UploadFileMessage {
  static const int flagFirst = 1;
  static const int flagLast = 2;
  static const int maxFiles = 32;
  static const int maxFileName = 128;
  static const int checksumLength = 32;

  final int containerId;

  /// Identifies the upload across its messages.
  final String uploadId;
  final int flags;

  /// Present in the message with [flagFirst].
  final List<UploadFileHeader>? files;
  final List<UploadSlice> slices;

  const UploadFileMessage(
    this.containerId,
    this.uploadId,
    this.flags,
    this.files,
    this.slices,
  );

  bool get isFirst => flags & flagFirst != 0;
  bool get isLast => flags & flagLast != 0;

  /// [maxTotalSize] is the server's `upload_max_size` (default 512 KiB).
  static PayloadCodec<UploadFileMessage> codecWith({int maxTotalSize = 512 * 1024}) =>
      PayloadCodec.buffer(
        write: (w, m) {
          w
            ..writeVarInt(m.containerId)
            ..writeUuid(m.uploadId)
            ..writeByte(m.flags);
          if (m.isFirst) {
            final files = m.files!;
            w.writeVarInt(files.length);
            for (final file in files) {
              w
                ..writeString(file.name, maxLength: maxFileName)
                ..writeVarInt(file.size)
                ..writeBytes(file.checksum);
            }
          }
          w.writeVarInt(m.slices.length);
          for (final slice in m.slices) {
            w
              ..writeByte(slice.fileId)
              ..writeVarInt(slice.offset)
              ..writeShort(slice.bytes.length)
              ..writeBytes(slice.bytes);
          }
        },
        read: (r) {
          final containerId = r.readVarInt();
          final uploadId = r.readUuid();
          final flags = r.readByte();
          List<UploadFileHeader>? files;
          if (flags & flagFirst != 0) {
            final count = r.readVarInt();
            if (count > maxFiles) throw const PacketException('Too many files');
            var total = 0;
            files = [];
            for (var i = 0; i < count; i++) {
              final name = r.readString(maxLength: maxFileName);
              final size = r.readVarInt();
              total += size;
              if (size > maxTotalSize || total > maxTotalSize) {
                throw const PacketException('Files are too large');
              }
              files.add(UploadFileHeader(name, size, r.readBytes(checksumLength)));
            }
          }
          final sliceCount = r.readVarInt();
          final slices = <UploadSlice>[];
          for (var i = 0; i < sliceCount; i++) {
            final fileId = r.readUnsignedByte();
            final offset = r.readVarInt();
            final size = r.readUnsignedShort();
            if (size > 30 * 1024) throw const PacketException('File is too large');
            slices.add(UploadSlice(fileId, offset, r.readBytes(size)));
          }
          return UploadFileMessage(containerId, uploadId, flags, files, slices);
        },
      );
}

// -- Clientbound ----------------------------------------------------------------

/// A new screen for the open computer menu.
final class ComputerTerminalMessage {
  final int containerId;
  final TerminalState terminal;

  const ComputerTerminalMessage(this.containerId, this.terminal);

  static final PayloadCodec<ComputerTerminalMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w.writeVarInt(m.containerId);
      m.terminal.write(w);
    },
    read: (r) => ComputerTerminalMessage(r.readVarInt(), TerminalState.read(r)),
  );
}

/// The screen of the monitor whose origin block is at [position]; null when
/// it has no terminal (no computer uses it).
final class MonitorMessage {
  final (int, int, int) position;
  final TerminalState? terminal;

  const MonitorMessage(this.position, this.terminal);

  static final PayloadCodec<MonitorMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w.writeBlockPos(m.position);
      w.writeOptional<TerminalState>(m.terminal, (w, t) => t.write(w));
    },
    read: (r) => MonitorMessage(
      r.readBlockPos(),
      r.readOptional(TerminalState.read),
    ),
  );
}

/// The state of a pocket computer item, keyed by its instance UUID.
final class PocketComputerDataMessage {
  final String instanceId;
  final WireComputerState state;
  final int lightState;
  final TerminalState? terminal;

  const PocketComputerDataMessage(this.instanceId, this.state, this.lightState, this.terminal);

  static final PayloadCodec<PocketComputerDataMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w
        ..writeUuid(m.instanceId)
        ..writeVarInt(m.state.index)
        ..writeVarInt(m.lightState);
      w.writeOptional<TerminalState>(m.terminal, (w, t) => t.write(w));
    },
    read: (r) => PocketComputerDataMessage(
      r.readUuid(),
      _enumAt(WireComputerState.values, r.readVarInt(), 'ComputerState'),
      r.readVarInt(),
      r.readOptional(TerminalState.read),
    ),
  );
}

/// A pocket computer was deleted on the server.
final class PocketComputerDeletedMessage {
  final String instanceId;

  const PocketComputerDeletedMessage(this.instanceId);

  static final PayloadCodec<PocketComputerDeletedMessage> codec = PayloadCodec.buffer(
    write: (w, m) => w.writeUuid(m.instanceId),
    read: (r) => PocketComputerDeletedMessage(r.readUuid()),
  );
}

/// Where a speaker is: a dimension and a position, optionally an entity.
final class SpeakerPositionMessage {
  /// The dimension id, e.g. `minecraft:overworld`.
  final String level;
  final (double, double, double) position;
  final int? entityId;

  const SpeakerPositionMessage(this.level, this.position, [this.entityId]);

  void write(PacketWriter w) {
    w
      ..writeString(level)
      ..writeDouble(position.$1)
      ..writeDouble(position.$2)
      ..writeDouble(position.$3);
    w.writeOptional<int>(entityId, (w, id) => w.writeVarInt(id));
  }

  static SpeakerPositionMessage read(PacketReader r) => SpeakerPositionMessage(
    r.readString(),
    (r.readDouble(), r.readDouble(), r.readDouble()),
    r.readOptional((r) => r.readVarInt()),
  );
}

/// Audio a speaker plays, as DFPWM-encoded chunks.
final class SpeakerAudioMessage {
  final String source;
  final SpeakerPositionMessage position;

  /// The decoder state: `charge` and `strength` of the DFPWM codec, and the
  /// previous bit.
  final int charge;
  final int strength;
  final bool previousBit;
  final Uint8List audio;
  final double volume;

  const SpeakerAudioMessage(
    this.source,
    this.position,
    this.charge,
    this.strength,
    this.previousBit,
    this.audio,
    this.volume,
  );

  static final PayloadCodec<SpeakerAudioMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w.writeUuid(m.source);
      m.position.write(w);
      w
        ..writeVarInt(m.charge)
        ..writeVarInt(m.strength)
        ..writeBool(m.previousBit)
        ..writeByteArray(m.audio)
        ..writeFloat(m.volume);
    },
    read: (r) => SpeakerAudioMessage(
      r.readUuid(),
      SpeakerPositionMessage.read(r),
      r.readVarInt(),
      r.readVarInt(),
      r.readBool(),
      r.readByteArray(),
      r.readFloat(),
    ),
  );
}

/// A speaker moved (follows an entity, or a pocket computer's holder).
final class SpeakerMoveMessage {
  final String source;
  final SpeakerPositionMessage position;

  const SpeakerMoveMessage(this.source, this.position);

  static final PayloadCodec<SpeakerMoveMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w.writeUuid(m.source);
      m.position.write(w);
    },
    read: (r) => SpeakerMoveMessage(r.readUuid(), SpeakerPositionMessage.read(r)),
  );
}

/// A speaker plays a sound event by name.
final class SpeakerPlayMessage {
  final String source;
  final SpeakerPositionMessage position;
  final String sound;
  final double volume;
  final double pitch;

  const SpeakerPlayMessage(this.source, this.position, this.sound, this.volume, this.pitch);

  static final PayloadCodec<SpeakerPlayMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w.writeUuid(m.source);
      m.position.write(w);
      w
        ..writeString(m.sound)
        ..writeFloat(m.volume)
        ..writeFloat(m.pitch);
    },
    read: (r) => SpeakerPlayMessage(
      r.readUuid(),
      SpeakerPositionMessage.read(r),
      r.readString(),
      r.readFloat(),
      r.readFloat(),
    ),
  );
}

/// A speaker stopped.
final class SpeakerStopMessage {
  final String source;

  const SpeakerStopMessage(this.source);

  static final PayloadCodec<SpeakerStopMessage> codec = PayloadCodec.buffer(
    write: (w, m) => w.writeUuid(m.source),
    read: (r) => SpeakerStopMessage(r.readUuid()),
  );
}

/// The outcome of a file upload, shown in the terminal's GUI.
final class UploadResultMessage {
  final int containerId;
  final UploadResultKind result;

  /// The error text for [UploadResultKind.error] (network NBT component).
  final NbtText? error;

  const UploadResultMessage(this.containerId, this.result, [this.error]);

  static final PayloadCodec<UploadResultMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w
        ..writeVarInt(m.containerId)
        ..writeVarInt(m.result.index);
      w.writeOptional<NbtText>(m.error, (w, text) => text.write(w));
    },
    read: (r) => UploadResultMessage(
      r.readVarInt(),
      _enumAt(UploadResultKind.values, r.readVarInt(), 'UploadResult'),
      r.readOptional(NbtText.read),
    ),
  );
}

/// `neoforge:advanced_open_screen`: opens a menu whose factory reads extra
/// data. For computers, [extraData] is a `ComputerContainerData` (see
/// menu_data.dart).
final class AdvancedOpenScreenMessage {
  final int windowId;

  /// The numeric id of the menu type in the synchronised `minecraft:menu`
  /// registry.
  final int menuTypeId;
  final NbtText title;
  final Uint8List extraData;

  const AdvancedOpenScreenMessage(this.windowId, this.menuTypeId, this.title, this.extraData);

  static final PayloadCodec<AdvancedOpenScreenMessage> codec = PayloadCodec.buffer(
    write: (w, m) {
      w
        ..writeVarInt(m.windowId)
        ..writeVarInt(m.menuTypeId);
      m.title.write(w);
      w.writeByteArray(m.extraData);
    },
    read: (r) => AdvancedOpenScreenMessage(
      r.readVarInt(),
      r.readVarInt(),
      NbtText.read(r),
      r.readByteArray(),
    ),
  );
}

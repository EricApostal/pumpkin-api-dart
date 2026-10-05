// `TerminalState`: the terminal snapshot every screen update carries
// (`dan200.computercraft.shared.computer.terminal.TerminalState`).
//
// Wire format, from `TerminalState.write`/`NetworkedTerminal.write`:
//
//     bool    colour
//     VarInt  width, height, cursorX, cursorY
//     bool    cursorBlink
//     byte    cursorBackground << 4 | cursorForeground
//     VarInt  length, then:
//       height x ( width text bytes, width colour bytes (bg << 4 | fg) )
//       16 x ( r, g, b )   the palette, channel * 255 as one byte each
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../machine/terminal.dart';

final class TerminalState {
  final bool colour;
  final int width;
  final int height;
  final int cursorX;
  final int cursorY;
  final bool cursorBlink;

  /// Colour indexes of the cursor (0 = white .. 15 = black).
  final int cursorBackground;
  final int cursorForeground;

  /// Text, colours and palette as described above.
  final Uint8List contents;

  const TerminalState({
    required this.colour,
    required this.width,
    required this.height,
    required this.cursorX,
    required this.cursorY,
    required this.cursorBlink,
    required this.cursorBackground,
    required this.cursorForeground,
    required this.contents,
  });

  /// Snapshots [terminal].
  factory TerminalState.of(Terminal terminal) {
    final width = terminal.width;
    final height = terminal.height;
    final contents = Uint8List(width * height * 2 + Palette.size * 3);
    var index = 0;
    for (var y = 0; y < height; y++) {
      contents.setRange(index, index + width, terminal.textLine(y));
      index += width;
      final foreground = terminal.foregroundLine(y);
      final background = terminal.backgroundLine(y);
      for (var x = 0; x < width; x++) {
        contents[index++] = (background[x] << 4) | foreground[x];
      }
    }
    for (var i = 0; i < Palette.size; i++) {
      for (final channel in terminal.palette.colour(i)) {
        contents[index++] = (channel * 255).toInt() & 0xFF;
      }
    }
    return TerminalState(
      colour: terminal.isColour,
      width: width,
      height: height,
      cursorX: terminal.cursorX,
      cursorY: terminal.cursorY,
      cursorBlink: terminal.cursorBlink,
      cursorBackground: terminal.backgroundColour,
      cursorForeground: terminal.textColour,
      contents: contents,
    );
  }

  /// The size of [contents] in bytes (what monitor bandwidth is counted in).
  int get size => contents.length;

  void write(PacketWriter writer) {
    writer
      ..writeBool(colour)
      ..writeVarInt(width)
      ..writeVarInt(height)
      ..writeVarInt(cursorX)
      ..writeVarInt(cursorY)
      ..writeBool(cursorBlink)
      ..writeByte((cursorBackground << 4) | cursorForeground)
      ..writeByteArray(contents);
  }

  static TerminalState read(PacketReader reader) {
    final colour = reader.readBool();
    final width = reader.readVarInt();
    final height = reader.readVarInt();
    final cursorX = reader.readVarInt();
    final cursorY = reader.readVarInt();
    final blink = reader.readBool();
    final cursor = reader.readUnsignedByte();
    final contents = reader.readByteArray();
    if (width < 1 || height < 1 || width > 255 || height > 255) {
      throw PacketException('Terminal of $width x $height');
    }
    if (contents.length != width * height * 2 + Palette.size * 3) {
      throw PacketException('Terminal contents of ${contents.length} bytes');
    }
    return TerminalState(
      colour: colour,
      width: width,
      height: height,
      cursorX: cursorX,
      cursorY: cursorY,
      cursorBlink: blink,
      cursorBackground: (cursor >> 4) & 0xF,
      cursorForeground: cursor & 0xF,
      contents: contents,
    );
  }

  /// Copies the snapshot into [terminal] (resizing it), like
  /// `NetworkedTerminal.read`.
  void applyTo(Terminal terminal) {
    terminal
      ..resize(width, height)
      ..cursorX = cursorX
      ..cursorY = cursorY
      ..cursorBlink = cursorBlink
      ..backgroundColour = cursorBackground
      ..textColour = cursorForeground;
    var index = 0;
    for (var y = 0; y < height; y++) {
      terminal.textLine(y).setRange(0, width, contents, index);
      index += width;
      for (var x = 0; x < width; x++) {
        final colours = contents[index++];
        terminal.backgroundLine(y)[x] = (colours >> 4) & 0xF;
        terminal.foregroundLine(y)[x] = colours & 0xF;
      }
    }
    for (var i = 0; i < Palette.size; i++) {
      terminal.palette.setColour(
        i,
        contents[index++] / 255,
        contents[index++] / 255,
        contents[index++] / 255,
      );
    }
    terminal.setChanged();
  }

  /// Whether two snapshots show the same screen (used to skip redundant
  /// updates).
  bool sameAs(TerminalState other) {
    if (colour != other.colour ||
        width != other.width ||
        height != other.height ||
        cursorX != other.cursorX ||
        cursorY != other.cursorY ||
        cursorBlink != other.cursorBlink ||
        cursorBackground != other.cursorBackground ||
        cursorForeground != other.cursorForeground ||
        contents.length != other.contents.length) {
      return false;
    }
    for (var i = 0; i < contents.length; i++) {
      if (contents[i] != other.contents[i]) return false;
    }
    return true;
  }
}

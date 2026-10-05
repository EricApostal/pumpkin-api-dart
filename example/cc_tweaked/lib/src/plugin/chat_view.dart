// Shows a computer's terminal in chat: one chat line per terminal row, with
// the text colour mapped to the nearest of Minecraft's 16 chat colours. This is
// the fallback view until the real CC: Tweaked client renders terminals.
import '../machine/terminal.dart';

/// Minecraft's chat colours as `(code, 0xRRGGBB)`.
const List<(String, int)> _chatColours = [
  ('0', 0x000000),
  ('1', 0x0000AA),
  ('2', 0x00AA00),
  ('3', 0x00AAAA),
  ('4', 0xAA0000),
  ('5', 0xAA00AA),
  ('6', 0xFFAA00),
  ('7', 0xAAAAAA),
  ('8', 0x555555),
  ('9', 0x5555FF),
  ('a', 0x55FF55),
  ('b', 0x55FFFF),
  ('c', 0xFF5555),
  ('d', 0xFF55FF),
  ('e', 0xFFFF55),
  ('f', 0xFFFFFF),
];

String _nearestChatColour(int rgb) {
  var best = 'f';
  var bestDistance = 1 << 30;
  for (final (code, value) in _chatColours) {
    final dr = ((rgb >> 16) & 0xFF) - ((value >> 16) & 0xFF);
    final dg = ((rgb >> 8) & 0xFF) - ((value >> 8) & 0xFF);
    final db = (rgb & 0xFF) - (value & 0xFF);
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = code;
    }
  }
  return best;
}

/// The printable form of a terminal byte: Latin-1 where it is printable, a
/// placeholder for CC's drawing characters (128-159) and control codes.
String _glyph(int byte) {
  if (byte >= 32 && byte <= 126) return String.fromCharCode(byte);
  if (byte >= 160) return String.fromCharCode(byte);
  if (byte >= 128 && byte <= 159) return '▒';
  return ' ';
}

/// Renders [terminal] as chat lines with `&` colour codes (text that came
/// from the program has its own `&` doubled). Trailing blanks are trimmed.
List<String> renderTerminal(Terminal terminal) {
  final colours = [
    for (var i = 0; i < Palette.size; i++)
      _nearestChatColour(terminal.palette.rgb8(15 - i)),
  ];
  final lines = <String>[];
  for (var y = 0; y < terminal.height; y++) {
    final text = terminal.textLine(y);
    final foreground = terminal.foregroundLine(y);
    final background = terminal.backgroundLine(y);
    var end = terminal.width;
    while (end > 0 && text[end - 1] == 32 && background[end - 1] == 15) {
      end--;
    }
    final out = StringBuffer();
    var current = '';
    for (var x = 0; x < end; x++) {
      var code = colours[foreground[x]];
      var glyph = _glyph(text[x]);
      if (background[x] != 15 && text[x] == 32) {
        // A coloured background cell: draw it as a block in its colour.
        code = colours[background[x]];
        glyph = '█';
      }
      if (code != current) {
        out.write('&$code');
        current = code;
      }
      out.write(glyph == '&' ? '&&' : glyph);
    }
    lines.add(out.toString());
  }
  return lines;
}

// The terminal of a computer or monitor: a grid of characters with a text and
// a background colour per cell, a cursor and a 16 colour palette. It mirrors
// CC: Tweaked's `Terminal`, `TextBuffer` and `Palette` so that its state maps
// one to one onto the `TerminalState` network payload.
//
// Colours inside the terminal are *indexes* 0..15, where index 0 is white
// (`colors.white` = 2^0) and 15 is black (`colors.black` = 2^15). The palette
// is indexed the other way round (0 is black), so the RGB of colour index `n`
// is `palette[15 - n]`, exactly as in the client.
import 'dart:typed_data';

/// The 16 default palette colours as 0xRRGGBB, in palette order (index 0 is
/// black), from `dan200.computercraft.core.util.Colour`.
const List<int> defaultPaletteRgb = [
  0x111111, // black
  0xcc4c4c, // red
  0x57A64E, // green
  0x7f664c, // brown
  0x3366cc, // blue
  0xb266e5, // purple
  0x4c99b2, // cyan
  0x999999, // light grey
  0x4c4c4c, // grey
  0xf2b2cc, // pink
  0x7fcc19, // lime
  0xdede6c, // yellow
  0x99b2f2, // light blue
  0xe57fd8, // magenta
  0xf2b233, // orange
  0xf0f0f0, // white
];

/// The 16 colour palette; entries are RGB triples of doubles in 0..1.
final class Palette {
  static const int size = 16;

  final List<List<double>> _colours = [
    for (var i = 0; i < size; i++) <double>[0, 0, 0],
  ];

  Palette() {
    reset();
  }

  /// Restores the default colours.
  void reset() {
    for (var i = 0; i < size; i++) {
      final rgb = defaultPaletteRgb[i];
      setColour(
        i,
        ((rgb >> 16) & 0xFF) / 255,
        ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255,
      );
    }
  }

  void setColour(int index, double r, double g, double b) {
    if (index < 0 || index >= size) return;
    _colours[index][0] = r;
    _colours[index][1] = g;
    _colours[index][2] = b;
  }

  /// The RGB triple of palette entry [index] (the list is live).
  List<double> colour(int index) => _colours[index];

  /// The palette entry as 0xRRGGBB.
  int rgb8(int index) {
    final c = _colours[index];
    return (((c[0] * 255).toInt() & 0xFF) << 16) |
        (((c[1] * 255).toInt() & 0xFF) << 8) |
        ((c[2] * 255).toInt() & 0xFF);
  }
}

/// A character grid with colours, a cursor and a palette.
///
/// [onChanged] runs whenever something visible changes.
final class Terminal {
  int _width;
  int _height;
  final bool isColour;
  final void Function()? onChanged;
  final Palette palette = Palette();

  int cursorX = 0;
  int cursorY = 0;
  bool cursorBlink = false;

  /// The text colour index new text is written with (0 = white).
  int textColour = 0;

  /// The background colour index (15 = black).
  int backgroundColour = 15;

  late List<Uint8List> _text;
  late List<Uint8List> _foreground;
  late List<Uint8List> _background;

  Terminal(this._width, this._height, this.isColour, {this.onChanged}) {
    _allocate();
  }

  int get width => _width;
  int get height => _height;

  void _allocate() {
    _text = [for (var y = 0; y < _height; y++) _blankText()];
    _foreground = [for (var y = 0; y < _height; y++) _blankColour(textColour)];
    _background = [for (var y = 0; y < _height; y++) _blankColour(backgroundColour)];
  }

  Uint8List _blankText() => Uint8List(_width)..fillRange(0, _width, 32);

  Uint8List _blankColour(int colour) =>
      Uint8List(_width)..fillRange(0, _width, colour);

  void setChanged() => onChanged?.call();

  /// Clears the screen and restores the default colours, cursor and palette.
  void reset() {
    textColour = 0;
    backgroundColour = 15;
    cursorX = 0;
    cursorY = 0;
    cursorBlink = false;
    clear();
    palette.reset();
    setChanged();
  }

  /// Changes the size, keeping what fits.
  void resize(int width, int height) {
    if (width == _width && height == _height) return;
    final oldText = _text;
    final oldForeground = _foreground;
    final oldBackground = _background;
    final oldWidth = _width;
    final oldHeight = _height;
    _width = width;
    _height = height;
    _allocate();
    for (var y = 0; y < height && y < oldHeight; y++) {
      final n = width < oldWidth ? width : oldWidth;
      _text[y].setRange(0, n, oldText[y]);
      _foreground[y].setRange(0, n, oldForeground[y]);
      _background[y].setRange(0, n, oldBackground[y]);
    }
    setChanged();
  }

  void setCursorPos(int x, int y) {
    if (cursorX != x || cursorY != y) {
      cursorX = x;
      cursorY = y;
      setChanged();
    }
  }

  void setCursorBlink(bool blink) {
    if (cursorBlink != blink) {
      cursorBlink = blink;
      setChanged();
    }
  }

  void setTextColour(int colour) {
    if (textColour != colour) {
      textColour = colour;
      setChanged();
    }
  }

  void setBackgroundColour(int colour) {
    if (backgroundColour != colour) {
      backgroundColour = colour;
      setChanged();
    }
  }

  /// Writes [text] at the cursor with the current colours, clipped to the
  /// line. The cursor does not move.
  void write(String text) {
    final y = cursorY;
    if (y < 0 || y >= _height) return;
    final start = cursorX;
    final first = start < 0 ? 0 : start;
    var end = start + text.length;
    if (end > _width) end = _width;
    for (var x = first; x < end; x++) {
      _text[y][x] = text.codeUnitAt(x - start) & 0xFF;
      _foreground[y][x] = textColour;
      _background[y][x] = backgroundColour;
    }
    setChanged();
  }

  /// Writes text with a colour per character; [textColours] and
  /// [backgroundColours] are strings of hexadecimal colour digits.
  void blit(String text, String textColours, String backgroundColours) {
    final y = cursorY;
    if (y < 0 || y >= _height) return;
    final start = cursorX;
    final first = start < 0 ? 0 : start;
    var end = start + text.length;
    if (end > _width) end = _width;
    for (var x = first; x < end; x++) {
      final i = x - start;
      _text[y][x] = text.codeUnitAt(i) & 0xFF;
      _foreground[y][x] = colourFromChar(textColours.codeUnitAt(i), 0);
      _background[y][x] = colourFromChar(backgroundColours.codeUnitAt(i), 15);
    }
    setChanged();
  }

  /// Scrolls the screen up by [lines] (down if negative).
  void scroll(int lines) {
    if (lines == 0) return;
    final newText = <Uint8List>[];
    final newForeground = <Uint8List>[];
    final newBackground = <Uint8List>[];
    for (var y = 0; y < _height; y++) {
      final from = y + lines;
      if (from >= 0 && from < _height) {
        newText.add(_text[from]);
        newForeground.add(_foreground[from]);
        newBackground.add(_background[from]);
      } else {
        newText.add(_blankText());
        newForeground.add(_blankColour(textColour));
        newBackground.add(_blankColour(backgroundColour));
      }
    }
    _text = newText;
    _foreground = newForeground;
    _background = newBackground;
    setChanged();
  }

  /// Clears the whole screen with the current colours.
  void clear() {
    for (var y = 0; y < _height; y++) {
      _text[y].fillRange(0, _width, 32);
      _foreground[y].fillRange(0, _width, textColour);
      _background[y].fillRange(0, _width, backgroundColour);
    }
    setChanged();
  }

  /// Clears the cursor's line.
  void clearLine() {
    final y = cursorY;
    if (y < 0 || y >= _height) return;
    _text[y].fillRange(0, _width, 32);
    _foreground[y].fillRange(0, _width, textColour);
    _background[y].fillRange(0, _width, backgroundColour);
    setChanged();
  }

  /// The character codes of line [y] (live).
  Uint8List textLine(int y) => _text[y];

  /// The text colour indexes of line [y] (live).
  Uint8List foregroundLine(int y) => _foreground[y];

  /// The background colour indexes of line [y] (live).
  Uint8List backgroundLine(int y) => _background[y];

  /// The text of line [y] as a string.
  String lineText(int y) => String.fromCharCodes(_text[y]);

  /// The colour index for the hexadecimal digit [char], or [fallback].
  static int colourFromChar(int char, int fallback) {
    if (char >= 48 && char <= 57) return char - 48;
    if (char >= 97 && char <= 102) return char - 87;
    if (char >= 65 && char <= 70) return char - 55;
    return fallback;
  }
}

// `EdgeGroupColor` (pure): the colour of a signal edge group, picked so that adjacent groups differ.
// ignore_for_file: constant_identifier_names

enum EdgeGroupColor {
  YELLOW(0xEBC255),
  GREEN(0x51C054),
  BLUE(0x5391E1),
  ORANGE(0xE36E36),
  LAVENDER(0xCB92BA),
  RED(0xA43538),
  CYAN(0x6EDAD9),
  BROWN(0xA17C58),
  WHITE(0xE5E1DC);

  /// The RGB value (`Color.getRGB()` without alpha).
  final int rgb;

  const EdgeGroupColor(this.rgb);

  int get mask => 1 << index;

  int strikeFrom(int mask) {
    if (this == WHITE) return mask;
    return mask | this.mask;
  }

  /// `get()`: the colour as an opaque ARGB int.
  int get() => (0xFF000000 | rgb).toSigned(32);

  static EdgeGroupColor getDefault() => values[0];

  static EdgeGroupColor findNextAvailable(int mask) {
    for (final value in values) {
      if ((mask & 1) == 0) return value;
      mask = mask >> 1;
    }
    return WHITE;
  }
}

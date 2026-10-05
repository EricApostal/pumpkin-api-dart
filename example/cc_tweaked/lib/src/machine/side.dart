// The six sides of a computer, in the order CC: Tweaked numbers them.

/// A side of a computer, as programs name it (`"top"`, `"left"`, ...).
enum ComputerSide {
  bottom('bottom'),
  top('top'),
  back('back'),
  front('front'),
  right('right'),
  left('left');

  final String luaName;

  const ComputerSide(this.luaName);

  /// The side called [name] (ignoring case), or null.
  static ComputerSide? parse(String name) {
    for (final side in values) {
      if (side.luaName == name.toLowerCase()) return side;
    }
    return null;
  }
}

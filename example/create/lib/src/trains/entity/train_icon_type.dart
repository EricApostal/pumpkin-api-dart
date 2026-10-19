// `TrainIconType` (pure): the icon of a train on the station screen and the train map. Only the
// id matters to the server (it is saved and sent to the clients); the sheet position is kept for
// parity.
import '../manager/create.dart';

class TrainIconType {
  /// `REGISTRY` (the three Create icons are registered when it is first read).
  static final Map<String, TrainIconType> REGISTRY = _defaults();

  static Map<String, TrainIconType> _defaults() {
    final sheet = Create.asResource('textures/gui/assemble.png');
    return {
      for (final e in [('traditional', 205), ('electric', 216), ('modern', 227)])
        Create.asResource(e.$1): TrainIconType(Create.asResource(e.$1), sheet, 2, e.$2),
    };
  }

  /// `register(id, sheet, x, y)`.
  static void register(String id, String sheet, int x, int y) {
    REGISTRY[id] = TrainIconType(id, sheet, x, y);
  }

  final String sheet;
  final String id;
  final int x, y;

  TrainIconType(this.id, this.sheet, this.x, this.y);

  /// `byId(id)`: the icon, or the default one.
  static TrainIconType byId(String id) {
    return REGISTRY[id] ?? getDefault();
  }

  /// `getDefault()`: `create:traditional`.
  static TrainIconType getDefault() {
    return REGISTRY[Create.asResource('traditional')]!;
  }

  String getId() => id;

  static const int ENGINE = -1;
  static const int FLIPPED_ENGINE = -2;

  int getIconWidth(int lengthOrEngine) {
    if (lengthOrEngine == FLIPPED_ENGINE) return 19;
    if (lengthOrEngine == ENGINE) return 19;
    if (lengthOrEngine < 3) return 7;
    if (lengthOrEngine < 9) return 13;
    return 19;
  }

  int getIconOffset(int lengthOrEngine) {
    if (lengthOrEngine == FLIPPED_ENGINE) return 0;
    if (lengthOrEngine == ENGINE) return 62;
    if (lengthOrEngine < 3) return 34;
    if (lengthOrEngine < 9) return 20;
    return 42;
  }
}

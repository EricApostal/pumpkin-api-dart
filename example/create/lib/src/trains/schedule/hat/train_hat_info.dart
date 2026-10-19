// `TrainHatInfo` (pure): where the conductor's hat sits on a passenger entity model. The table is
// resource data (`train_hat_info/<entity>.json`, a client asset); the server keeps the parsed
// model so datapack / resource readers and tests can use it. `getAdjustedPart` walks the client's
// model parts and is not ported.
import 'package:dart_mappable/dart_mappable.dart';

import '../../../common/vec_helper.dart' show Vec3;

part 'train_hat_info.mapper.dart';

@MappableClass()
class TrainHatInfo with TrainHatInfoMappable {
  /// `model_part`: a `/` separated path of model part names, empty for the default part.
  final String part;

  /// `cube_index`.
  final int cubeIndex;

  /// `offset`: three floats in the JSON.
  final List<double> offsetList;

  /// `scale`.
  final double scale;

  const TrainHatInfo(this.part, this.cubeIndex, this.offsetList, this.scale);

  /// `new TrainHatInfo(part, cubeIndex, offset, scale)`.
  factory TrainHatInfo.of(String part, int cubeIndex, Vec3 offset, double scale) =>
      TrainHatInfo(part, cubeIndex, [offset.$1, offset.$2, offset.$3], scale);

  /// The `offset` as a vector.
  Vec3 get offset => (offsetList[0], offsetList[1], offsetList[2]);

  /// `TrainHatInfo.CODEC` on a decoded JSON object: `offset` is required, the rest optional
  /// (`model_part` "", `cube_index` 0, `scale` 1). Throws [FormatException] when invalid.
  static TrainHatInfo fromJson(Map<String, Object?> json) {
    final offset = json['offset'];
    if (offset is! List<Object?> || offset.length != 3 || offset.any((e) => e is! num)) {
      throw const FormatException('train hat info: offset must be a list of three numbers');
    }
    final part = json['model_part'];
    final cube = json['cube_index'];
    final scale = json['scale'];
    if (part != null && part is! String) throw const FormatException('train hat info: model_part must be a string');
    if (cube != null && cube is! int) throw const FormatException('train hat info: cube_index must be an integer');
    if (scale != null && scale is! num) throw const FormatException('train hat info: scale must be a number');
    return TrainHatInfo((part as String?) ?? '', (cube as int?) ?? 0, [
      for (final e in offset) (e! as num).toDouble(),
    ], (scale as num?)?.toDouble() ?? 1.0);
  }
}

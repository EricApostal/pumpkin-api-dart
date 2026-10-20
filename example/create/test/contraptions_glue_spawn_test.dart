import 'package:create/src/common/bounds.dart';
import 'package:create/src/contraptions/glue/super_glue_entity.dart';
import 'package:test/test.dart';

void main() {
  group('SuperGlueEntity spawn data', () {
    test('the box round-trips through writeSpawnData/readSpawnData', () {
      const box = Aabb(1.0, 64.0, 2.0, 3.0, 65.0, 4.5);
      final data = glueSpawnData(box);
      expect(data, isNotEmpty);

      final decoded = glueBoxFromSpawnData(data);
      expect(decoded, isNotNull);
      expect(decoded!.minX, closeTo(box.minX, 1e-6));
      expect(decoded.minY, closeTo(box.minY, 1e-6));
      expect(decoded.minZ, closeTo(box.minZ, 1e-6));
      expect(decoded.maxX, closeTo(box.maxX, 1e-6));
      expect(decoded.maxY, closeTo(box.maxY, 1e-6));
      expect(decoded.maxZ, closeTo(box.maxZ, 1e-6));
      expect(glueVolume(decoded), closeTo(glueVolume(box), 1e-6));
    });

    test('an entity without spawn data has no box', () {
      expect(glueBoxFromSpawnData(null), isNull);
      expect(glueBoxFromSpawnData(const []), isNull);
      expect(glueBoxFromSpawnData(const [1, 2, 3]), isNull);
    });

    test('the entity sits at the horizontal center of the box, on its bottom', () {
      const box = Aabb(1.0, 64.0, 2.0, 3.0, 66.0, 4.0);
      final pos = glueEntityPos(box);
      expect(pos.$1, closeTo(2.0, 1e-6));
      expect(pos.$2, closeTo(64.0, 1e-6));
      expect(pos.$3, closeTo(3.0, 1e-6));
    });
  });
}

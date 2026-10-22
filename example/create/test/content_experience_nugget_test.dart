// The experience nugget: the foil of `ExperienceNuggetItem.isFoil` and the orb values of
// `ExperienceNuggetItem.use`. The port awards the orbs' total directly (the host cannot give an
// orb a value; see `experience_nugget_host.dart`), so the value math is pure and tested here.
import 'package:create/src/content/material_content.dart';
import 'package:create/src/manifest/manifest.dart';
import 'package:test/test.dart';

void main() {
  test('the nugget carries the foil component', () {
    final nugget = kItems.firstWhere((i) => i.key == 'experience_nugget');
    final glint = materialItem(nugget).components.singleWhere(
      (c) => c.name == 'minecraft:enchantment_glint_override',
    );
    // `ExperienceNuggetItem.isFoil` is true (`ExperienceNuggetItem.java:23-26`); the value is the
    // `BOOL` the `ItemSpec.glint` builder writes (`item_builder.dart:238-239`).
    expect(glint.bytes, [1]);
    expect(glint.wireName, 'enchantment-glint-override');
  });

  test('one nugget is worth ceil(3f * 1) = 3 experience', () {
    expect(experienceNuggetXp(1), 3);
    // total 3, maxOrbs 1, valuePer max(1, 1 + 3 ~/ 1) = 4, and orb 0 is min(4, 3) = 3 — not
    // valuePer.
    expect(experienceNuggetOrbs(1), [3]);
  });

  test('two nuggets spawn 2, 2, 2 — the last term of the Java loop is negative', () {
    expect(experienceNuggetXp(2), 6);
    // total 6, maxOrbs 5, valuePer max(1, 1 + 6 ~/ 5) = 2; the loop's five terms are
    // 2, 2, 2, 0, -2 (`ExperienceNuggetItem.java:43`): the zero means no orb (`:44-45`) and the -2
    // orb awards nothing on pickup (`ExperienceOrb.java:288`), so three 2s remain.
    expect(6 - 4 * 2, -2);
    expect(experienceNuggetOrbs(2), [2, 2, 2]);
  });

  test('a stack is spread over at most five orbs', () {
    // total 15, valuePer max(1, 1 + 15 ~/ 5) = 4: 4, 4, 4, 3, then -1.
    expect(experienceNuggetOrbs(5), [4, 4, 4, 3]);
    // A full stack: total 192, valuePer 1 + 38 = 39, and 192 - 4 * 39 = 36.
    expect(experienceNuggetOrbs(64), [39, 39, 39, 39, 36]);
  });

  test('the orb values always add up to the experience Java awards', () {
    for (var amount = 1; amount <= 99; amount++) {
      final orbs = experienceNuggetOrbs(amount);
      expect(orbs.length, lessThanOrEqualTo(5), reason: '$amount nuggets');
      expect(
        orbs.fold(0, (sum, value) => sum + value),
        experienceNuggetXp(amount),
        reason: '$amount nuggets',
      );
    }
  });
}
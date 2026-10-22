// The sand paper's polishing use: Java's `SandPaperItem.getUseDuration` is 32 ticks and the host
// never starts an item use for the sand paper (it has no `minecraft:consumable`), so the module
// counts the use down itself on the player tick (`MiscItemsHost`).
import 'package:create/src/equipment/tools/sand_paper_use.dart';
import 'package:test/test.dart';

void main() {
  test('a polishing use lasts getUseDuration (32) ticks', () {
    expect(sandPaperUseDuration, 32);
  });

  test('the polishing use finishes on the 32nd tick', () {
    final use = SandPaperUse();
    expect(use.isRunning, isTrue);
    expect(use.remaining, 32);

    for (var i = 0; i < 31; i++) {
      expect(use.tick(), isFalse, reason: 'tick $i of the use');
    }
    expect(use.remaining, 1);
    expect(use.isRunning, isTrue);

    expect(use.tick(), isTrue);
    expect(use.remaining, 0);
    expect(use.isRunning, isFalse);
  });

  test('a finished polishing use stays finished', () {
    final use = SandPaperUse();
    for (var i = 0; i < 32; i++) {
      use.tick();
    }
    expect(use.remaining, 0);
    expect(use.tick(), isTrue);
    expect(use.remaining, 0);
  });
}
import 'package:create/src/equipment/armor/backtank_math.dart';
import 'package:test/test.dart';

void main() {
  test('capacity', () {
    expect(BacktankMath.maxAir(airInBacktank: 900, enchantedCapacity: 300, enchantLevel: 0), 900);
    expect(BacktankMath.maxAir(airInBacktank: 900, enchantedCapacity: 300, enchantLevel: 3), 1800);
  });

  test('consume and warnings', () {
    expect(BacktankMath.consume(10, 3, 900), 7);
    expect(BacktankMath.consume(2, 3, 900), 0);
    expect(BacktankMath.consume(2000, 0, 900), 900);
    // low warning at maxAir/10 = 90: crossing from 100 to 80
    expect(BacktankMath.crossesWarning(100, 80, 90), isTrue);
    expect(BacktankMath.crossesWarning(80, 70, 90), isFalse);
    expect(BacktankMath.crossesWarning(100, 100, 90), isFalse);
    // depleted threshold 1
    expect(BacktankMath.crossesWarning(5, 0, 1), isTrue);
  });

  test('tool cost', () {
    expect(BacktankMath.usageCost(900, 200), 4);
    expect(BacktankMath.usageCost(900, 1000), 1);
  });

  test('bar and comparator', () {
    expect(BacktankMath.barWidth(450, 900), 7); // round(6.5) = 7 (Java Math.round half up)
    expect(BacktankMath.barWidth(0, 900), 0);
    expect(BacktankMath.barWidth(900, 900), 13);
    expect(BacktankMath.fractionToRedstoneLevel(0), 0);
    expect(BacktankMath.fractionToRedstoneLevel(1), 15);
    expect(BacktankMath.fractionToRedstoneLevel(0.5), 8);
  });

  test('refill maths', () {
    expect(BacktankMath.refillIncrement(256), 5);
    expect(BacktankMath.refillIncrement(120), 1);
    expect(BacktankMath.refillIncrement(10), 1);
    expect(BacktankMath.refillTimer(256), 0);
    expect(BacktankMath.refillTimer(32), 13);
    expect(BacktankMath.refillTimer(0), 20);
  });
}

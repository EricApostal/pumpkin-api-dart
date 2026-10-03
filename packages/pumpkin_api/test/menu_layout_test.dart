import 'package:pumpkin_api/src/menu_layout.dart';
import 'package:test/test.dart';

void main() {
  componentTests();
  test('slot maths', () {
    expect(MenuLayout.slot(1, 4), 13);
    expect(MenuLayout.rowOf(13), 1);
    expect(MenuLayout.columnOf(13), 4);
    expect(() => MenuLayout.slot(0, 9), throwsRangeError);
    expect(MenuLayout.size(3), 27);
  });

  test('row and column slots', () {
    expect(MenuLayout.rowSlots(2), [18, 19, 20, 21, 22, 23, 24, 25, 26]);
    expect(MenuLayout.columnSlots(8, 3), [8, 17, 26]);
  });

  test('border and inner', () {
    expect(MenuLayout.borderSlots(3).length, 20);
    expect(MenuLayout.innerSlots(3), [10, 11, 12, 13, 14, 15, 16]);
    expect(MenuLayout.borderSlots(2).length, 18);
    expect(MenuLayout.innerSlots(1), isEmpty);
    expect(MenuLayout.isBorder(13, 3), isFalse);
    expect(MenuLayout.isBorder(9, 3), isTrue);
  });

  test('page layout', () {
    final l = PageLayout(4);
    expect(l.pageSize, 27);
    expect(l.previousSlot, 30);
    expect(l.indicatorSlot, 31);
    expect(l.nextSlot, 32);
    expect(l.pageCount(0), 1);
    expect(l.pageCount(27), 1);
    expect(l.pageCount(28), 2);
    expect(l.range(1, 30), (27, 30));
    expect(l.range(5, 30), (30, 30));
    expect(l.clampPage(9, 30), 1);
    expect(l.clampPage(-1, 30), 0);
    expect(() => PageLayout(1), throwsRangeError);
  });
}

void componentTests() {
  group('ComponentBytes', () {
    test('varInt', () {
      expect(ComponentBytes.varInt(0), [0]);
      expect(ComponentBytes.varInt(127), [127]);
      expect(ComponentBytes.varInt(128), [0x80, 1]);
      expect(ComponentBytes.varInt(300), [0xac, 2]);
      expect(ComponentBytes.varInt(-1), [0xff, 0xff, 0xff, 0xff, 0x0f]);
    });
    test('string', () {
      expect(ComponentBytes.string('ab'), [2, 97, 98]);
      expect(ComponentBytes.string('é'), [2, 0xc3, 0xa9]);
    });
    test('float and cmd', () {
      expect(ComponentBytes.float32(1.0), [0x3f, 0x80, 0, 0]);
      expect(ComponentBytes.customModelData(1), [1, 0x3f, 0x80, 0, 0, 0, 0, 0]);
    });
  });
}

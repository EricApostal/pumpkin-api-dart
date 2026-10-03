import 'package:pumpkin_api/src/message_format.dart';
import 'package:test/test.dart';

void main() {
  test('colorize', () {
    expect(MessageFormat.colorize('&aHi &lyou'), '§aHi §lyou');
    expect(MessageFormat.colorize('Fish & chips &&a'), 'Fish & chips &a');
    expect(MessageFormat.stripColors('&aHi §cthere'), 'Hi there');
    expect(MessageFormat.colorize(MessageFormat.escape('&a§b')), '&ab');
  });
  test('ticks', () {
    expect(MessageFormat.ticks(const Duration(seconds: 1)), 20);
    expect(MessageFormat.ticks(const Duration(milliseconds: 51)), 2);
    expect(MessageFormat.ticks(Duration.zero), 0);
  });
  test('format', () {
    expect(MessageFormat.format('Hi {name}!', {'name': 'Bob'}), 'Hi Bob!');
    expect(MessageFormat.format('{0}-{1}-{0}', ['a', 2]), 'a-2-a');
    expect(MessageFormat.format('{x} {{y}}', {}), '{x} {y}');
    expect(MessageFormat.format('open {', {}), 'open {');
    expect(MessageFormat.format('n={n}', {'n': 3}), 'n=3');
  });
  test('catalog', () {
    final c = MessageCatalog({'a': 'A {x}', 'b': 'B'}, overrides: {'b': 'B2'}, prefix: '> ');
    expect(c['a'].format({'x': 1}), 'A 1');
    expect(c['b'].format(), 'B2');
    expect(c['nope'].format(), 'nope');
    expect(c.text('a', {'x': 2}), '> A 2');
    expect(c.has('a'), isTrue);
    expect(c.missingKeys, ['a']);
  });
  test('catalog json', () {
    final c = MessageCatalog.fromJson({'a': 'A', 'b': 'B'}, '{"a":"X","c":"C","d":1}');
    expect(c['a'].text, 'X');
    expect(c['b'].text, 'B');
    expect(c.effective, {'a': 'X', 'b': 'B', 'c': 'C'});
    expect(c.missingKeys, ['b']);
    expect(MessageCatalog.fromJson({'a': 'A'}, '{broken')['a'].text, 'A');
    expect(MessageCatalog.fromJson({'a': 'A'}, null).missingKeys, ['a']);
    expect(c.toJson(), contains('"c": "C"'));
  });
  test('sidebar layout', () {
    expect(SidebarLayout.entries(['&aA', 'x', 'x', 'x']), ['§aA', 'x', 'x§r', 'x§r§r']);
    expect(SidebarLayout.score(0, 3), 3);
    expect(SidebarLayout.score(2, 3), 1);
  });
}

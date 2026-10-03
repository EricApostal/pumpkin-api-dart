import 'package:pumpkin_api/src/pagination.dart';
import 'package:test/test.dart';

void main() {
  test('pages', () {
    final p = Paginator(List.generate(25, (i) => i), pageSize: 10);
    expect(p.pageCount, 3);
    expect(p.page(1).items.length, 10);
    expect(p.page(3).items, [20, 21, 22, 23, 24]);
    expect(p.page(99).number, 3);
    expect(p.page(-4).number, 1);
    expect(p.page(2).startIndex, 10);
    expect(p.page(2).numberOf(0), 11);
    expect(p.page(2).hasPrevious && p.page(2).hasNext, isTrue);
    expect(p.pageOf(0), 1);
    expect(p.pageOf(10), 2);
    expect(p.pageOf(24), 3);
    expect(() => p.pageOf(25), throwsRangeError);
    expect(p.next().number, 2);
    expect(p.previous().number, 1);
    expect(p.currentNumber, 1);
  });
  test('empty and exact', () {
    final e = Paginator<int>([]);
    expect(e.pageCount, 1);
    expect(e.page(1).isEmpty, isTrue);
    expect(Paginator([1, 2, 3, 4], pageSize: 2).pageCount, 2);
    expect(() => Paginator([1], pageSize: 0), throwsArgumentError);
  });
  test('render', () {
    final p = Paginator(['a', 'b', 'c'], pageSize: 2);
    final r = renderPage(p.page(2), title: 'Homes', format: (s, i) => '${i + 1}. $s');
    expect(r.header, '§e--- Homes (2/2) ---');
    expect(r.lines, ['3. c']);
    expect(r.footer, '§e${'-' * 19}');
  });
  test('confirmations', () {
    var now = DateTime.utc(2026);
    final m = ConfirmationManager<String>(now: () => now);
    m.request('p', 'del');
    expect(m.hasPending('p'), isTrue);
    expect(m.remaining('p'), const Duration(seconds: 10));
    now = now.add(const Duration(seconds: 5));
    expect(m.confirm('p'), 'del');
    expect(m.confirm('p'), isNull);
    m.request('p', 'x', ttl: const Duration(seconds: 2));
    now = now.add(const Duration(seconds: 2));
    expect(m.hasPending('p'), isFalse);
    m.request('q', 'y', ttl: const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 3));
    expect(m.confirm('q'), isNull);
    m.request('r', 'z');
    m.request('s', 'w', ttl: const Duration(seconds: 1));
    now = now.add(const Duration(seconds: 2));
    m.purgeExpired();
    expect(m.length, 1);
    expect(m.cancel('r'), isTrue);
  });
}

import 'dart:math';

import 'package:test/test.dart';
import 'package:wasm_components/src/text/regexp.dart';

/// Compares our engine with the VM's for a pattern and input.
void expectSame(
  String pattern,
  String input, {
  bool multiLine = false,
  bool caseSensitive = true,
  bool unicode = false,
  bool dotAll = false,
  int start = 0,
}) {
  final expected = RegExp(
    pattern,
    multiLine: multiLine,
    caseSensitive: caseSensitive,
    unicode: unicode,
    dotAll: dotAll,
  ).matchAsPrefix(input, start) == null &&
          start == 0
      ? RegExp(
          pattern,
          multiLine: multiLine,
          caseSensitive: caseSensitive,
          unicode: unicode,
          dotAll: dotAll,
        ).firstMatch(input)
      : RegExp(
          pattern,
          multiLine: multiLine,
          caseSensitive: caseSensitive,
          unicode: unicode,
          dotAll: dotAll,
        ).allMatches(input, start).firstOrNull;

  final compiled = CompiledRegExp(
    pattern,
    multiLine: multiLine,
    caseSensitive: caseSensitive,
    unicode: unicode,
    dotAll: dotAll,
  );
  final actual = compiled.match(StringCodeUnits(input), start, false);
  final reason = '/$pattern/ on ${input.runes.length < 40 ? input : '...'} '
      '(m=$multiLine i=${!caseSensitive} u=$unicode s=$dotAll)';
  if (expected == null) {
    expect(actual, isNull, reason: reason);
    return;
  }
  expect(actual, isNotNull, reason: reason);
  expect(actual!.start, expected.start, reason: reason);
  expect(actual.end, expected.end, reason: reason);
  expect(actual.groupCount, expected.groupCount, reason: reason);
  for (var g = 0; g <= expected.groupCount; g++) {
    final s = actual.starts[g];
    final e = actual.ends[g];
    expect(s < 0 ? null : input.substring(s, e), expected.group(g),
        reason: '$reason group $g');
  }
}

void main() {
  test('literals, classes and quantifiers', () {
    final patterns = [
      'abc', 'a+', 'a*b', 'a?b', r'\d+', r'\w+', r'\s+', r'\D\W\S', '[abc]+',
      '[^abc]+', '[a-z0-9_]+', r'[\d.]+', r'[\w-]+', 'a{2}', 'a{2,}', 'a{2,3}',
      'a+?', 'a*?b', '(a+)(b+)', '(a|b)+', '(?:ab)+', '^abc', 'abc\$', r'\bfoo\b',
      r'\Boo', '.', '.+', 'a.c', '', '|a', 'a|', 'a||b', r'\.', r'\\', r'\/',
      '[.]', r'[\]]', '[]a]', r'x{', 'x{1', r'a{,2}', '(a)|(b)', '(a)?b',
      '(a*)*', '(a*)+', '(a|ab)(c|bcd)(d*)', r'(\d{3})-(\d{4})', '(?:a|b)*c',
      r'\x41', r'A', r'\t', r'\n', r'\0', '[\\b]', r'\cJ',
      '(?<year>\\d{4})-(?<month>\\d{2})', r'(a)\1', r'(?<n>a)\k<n>', r'\1(a)',
      '(?=a)a', '(?!a)b', '(?<=a)b', '(?<!a)b', r'(?<=\$)\d+', 'a(?=b)',
      '[a-c-e]+', r'[\s\S]+', r'[^\s]+', r'(.)\1', r'^$', r'(?:)',
    ];
    final inputs = [
      '', 'a', 'abc', 'aabbcc', 'xabcx', 'foo bar', 'a1b2', ' a ', 'ab\ncd',
      '12-3456', '2024-05', r'$100 and $20', 'aaa', 'abab', 'ABC', 'xyz',
      'aab', 'ba', 'a.b', 'a]b', 'x{', 'x{1', '\t\n', 'abcd', 'hello world',
      'foo.bar', 'abba', '___', 'a-b', 'aa', 'bcd',
    ];
    for (final pattern in patterns) {
      for (final input in inputs) {
        expectSame(pattern, input);
        expectSame(pattern, input, caseSensitive: false);
        expectSame(pattern, input, multiLine: true);
        expectSame(pattern, input, dotAll: true);
      }
    }
  });

  test('start offsets', () {
    for (final pattern in ['a', r'\d+', 'a+', r'\b\w']) {
      for (final input in ['xaxaxa', '12 345', 'aaa bbb']) {
        for (var start = 0; start <= input.length; start++) {
          expectSame(pattern, input, start: start);
        }
      }
    }
  });

  test('case insensitive', () {
    for (final (pattern, input) in [
      ('abc', 'ABC'), ('[a-c]+', 'AbC'), (r'é', 'É'), ('é', 'É'),
      ('straße', 'STRASSE'), ('σ', 'Σ'), ('привет', 'ПРИВЕТ'), ('[^a]', 'A'),
      ('(a)\\1', 'aA'),
    ]) {
      expectSame(pattern, input, caseSensitive: false);
    }
  });

  test('unicode mode', () {
    for (final (pattern, input) in [
      ('.', '😀'), ('^.\$', '😀'), (r'\u{1F600}', '😀'), ('[😀]', '😀'),
      ('😀+', '😀😀'), (r'😀', '😀'), ('a.b', 'a😀b'),
    ]) {
      expectSame(pattern, input, unicode: true);
      if (pattern != r'\u{1F600}') expectSame(pattern, input);
    }
  });

  test('multiline and dotAll', () {
    for (final pattern in ['^b', 'a\$', '^.*\$', 'a.b', r'^\w+\$']) {
      for (final input in ['a\nb', 'ab\nab\n', 'a\r\nb', '\n\n', 'a b']) {
        expectSame(pattern, input, multiLine: true);
        expectSame(pattern, input, dotAll: true);
        expectSame(pattern, input, multiLine: true, dotAll: true);
      }
    }
  });

  test('capture reset in quantified groups', () {
    for (final (pattern, input) in [
      (r'(?:(a)|(b))+', 'ab'), (r'(?:(a)|b)*', 'ab'), (r'((a)|(b))+', 'ba'),
      (r'(z)((a+)?(b+)?(c))*', 'zaacbbbcac'), (r'(a*)*', 'b'), (r'(a*)+', 'b'),
      (r'(?:a?)*?b', 'aab'), (r'(a)|b', 'b'),
    ]) {
      expectSame(pattern, input);
    }
  });

  test('syntax errors', () {
    for (final pattern in ['(', ')', '[', 'a**', '*a', '+', '?', '[z-a]', r'\',
      '(?<n', '(?<1a>a)', '(?<n>a)(?<n>b)', r'\k<x>(?<y>a)', 'a{2,1}']) {
      Object? vmError;
      try {
        RegExp(pattern);
      } catch (e) {
        vmError = e;
      }
      Object? ourError;
      try {
        CompiledRegExp(pattern);
      } on RegExpSyntaxError catch (e) {
        ourError = e;
      }
      expect(ourError != null, vmError != null, reason: '/$pattern/');
    }
  });

  test('random patterns on random input', () {
    final generator = _PatternGenerator(Random(7));
    final random = Random(8);
    for (var i = 0; i < 1500; i++) {
      final pattern = generator.sequence(0);
      for (var j = 0; j < 4; j++) {
        final input = String.fromCharCodes(
          List.generate(
            random.nextInt(10),
            (_) => 'abcx 1_'.codeUnitAt(random.nextInt(7)),
          ),
        );
        expectSame(pattern, input);
      }
    }
  });

  test('escape matches the VM', () {
    for (final text in ['a.b', r'[x]', r'a\b', '(a|b)*', 'plain', r'^$', '{1}']) {
      expect(CompiledRegExp.escape(text), RegExp.escape(text));
    }
  });
}

final class _PatternGenerator {
  static const atoms = ['a', 'b', 'c', '.', r'\d', r'\w', '[ab]', '[^a]', 'x', ' '];
  static const quantifiers = ['', '', '', '*', '+', '?', '{1,2}', '*?', '+?', '??'];

  final Random random;

  _PatternGenerator(this.random);

  String quantifier() => quantifiers[random.nextInt(quantifiers.length)];

  String atom(int depth) {
    if (depth > 2 || random.nextInt(3) > 0) {
      return atoms[random.nextInt(atoms.length)] + quantifier();
    }
    final inner = sequence(depth + 1);
    final kind = random.nextInt(4);
    final group = switch (kind) {
      0 => '($inner)',
      1 => '(?:$inner)',
      2 => '(?=$inner)',
      _ => '($inner|${sequence(depth + 1)})',
    };
    return group + (kind < 2 ? quantifier() : '');
  }

  String sequence(int depth) =>
      List.generate(1 + random.nextInt(3), (_) => atom(depth)).join();
}

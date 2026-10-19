import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/core/nbt.dart';
import 'package:create/src/schematics/nbt_processors.dart';
import 'package:test/test.dart';

/// The block entity NBT a schematic carries: a compound with an `id`, written as binary NBT.
List<int> tag(Map<String, NbtValue> body) => BinaryNbt.write(
  NbtValue.compound({'id': const NbtValue.string('x'), ...body}),
);

NbtValue signText(String message) => NbtValue.compound({
  'messages': NbtValue.list([NbtValue.string(message)]),
});

void main() {
  test('unrelated blocks keep their data untouched', () {
    final data = tag({'Foo': const NbtValue.int32(1)});
    expect(
      processSchematicNbt(data, isSign: false, isClipboard: false),
      same(data),
    );
  });

  test('a sign without click events keeps its data', () {
    final data = tag({
      'front_text': signText('{"text":"hello"}'),
      'back_text': signText('{"text":"bye"}'),
    });
    expect(
      processSchematicNbt(data, isSign: true, isClipboard: false),
      same(data),
    );
  });

  test('a sign message with a click event loses its data', () {
    final data = tag({
      'front_text': signText(
        '{"text":"click","click_event":{"action":"run_command","command":"/kill"}}',
      ),
      'back_text': signText('{"text":"bye"}'),
    });
    expect(processSchematicNbt(data, isSign: true, isClipboard: false), isNull);
  });

  test('a sign message with a camelCase click event loses its data', () {
    final data = tag({
      'front_text': signText(
        '{"text":"click","clickEvent":{"action":"run_command"}}',
      ),
      'back_text': signText('{"text":"bye"}'),
    });
    expect(processSchematicNbt(data, isSign: true, isClipboard: false), isNull);
  });

  test('a nested click event inside a message loses the data', () {
    final data = tag({
      'front_text': signText('{"text":"a"}'),
      'back_text': signText(
        '{"text":"a","extra":[{"text":"b","click_event":{"action":"open_url"}}]}',
      ),
    });
    expect(processSchematicNbt(data, isSign: true, isClipboard: false), isNull);
  });

  test('a message that is not JSON is left alone', () {
    final data = tag({
      'front_text': signText('not json'),
      'back_text': signText('{"text":"bye"}'),
    });
    expect(
      processSchematicNbt(data, isSign: true, isClipboard: false),
      same(data),
    );
  });

  test('a sign missing a text compound loses its data', () {
    final data = tag({'front_text': signText('{"text":"a"}')});
    expect(processSchematicNbt(data, isSign: true, isClipboard: false), isNull);
  });

  test('sign data with an item loses its data', () {
    final data = tag({
      'front_text': signText('{"text":"a"}'),
      'back_text': signText('{"text":"b"}'),
      'front_item': NbtValue.emptyCompound(),
    });
    expect(processSchematicNbt(data, isSign: true, isClipboard: false), isNull);
  });

  test('a clipboard without a click event keeps its data', () {
    final data = tag({
      'components': NbtValue.compound({
        'create:clipboard_content': NbtValue.compound({
          'pages': NbtValue.list([
            NbtValue.list([
              NbtValue.compound({'text': const NbtValue.string('plain')}),
            ]),
          ]),
        }),
      }),
    });
    expect(
      processSchematicNbt(data, isSign: false, isClipboard: true),
      same(data),
    );
  });

  test('a clipboard entry text with a click event loses its data', () {
    final data = tag({
      'components': NbtValue.compound({
        'create:clipboard_content': NbtValue.compound({
          'pages': NbtValue.list([
            NbtValue.list([
              NbtValue.compound({
                'text': NbtValue.compound({
                  'click_event': NbtValue.emptyCompound(),
                }),
              }),
            ]),
          ]),
        }),
      }),
    });
    expect(processSchematicNbt(data, isSign: false, isClipboard: true), isNull);
  });

  test('unreadable NBT is left alone', () {
    final data = [0x0A, 0x00];
    expect(
      processSchematicNbt(data, isSign: true, isClipboard: false),
      same(data),
    );
  });
}

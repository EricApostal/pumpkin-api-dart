// `term` and the methods shared with monitors (`TermMethods` in CC: Tweaked).
import '../../lua/lua.dart';
import '../terminal.dart';

/// The highest set bit of a `colors` value, as a colour index 0..15.
int parseColour(int colour) {
  if (colour <= 0) throw LuaError.message('Colour out of range');
  final index = colour.bitLength - 1;
  if (index > 15) throw LuaError.message('Colour out of range');
  return index;
}

/// Adds the terminal methods to [table]. [terminal] is looked up on every
/// call, so a monitor can be detached.
void addTermMethods(LuaTable table, Terminal Function() terminal) {
  void defineAll(List<String> names, NativeImpl impl) {
    for (final name in names) {
      table.setString(name, NativeFunction(name, impl));
    }
  }

  defineAll(['write'], (list) {
    final args = Args('write', list);
    final value = args.any(0);
    if (value == null) args.wrongType(0, 'string');
    final text = value is String ? value : (value is double ? formatNumber(value) : rawToString(value));
    final t = terminal();
    t.write(text);
    t.setCursorPos(t.cursorX + text.length, t.cursorY);
    return noValues;
  });

  defineAll(['scroll'], (list) {
    terminal().scroll(Args('scroll', list).integer(0));
    return noValues;
  });

  defineAll(['getCursorPos'], (_) {
    final t = terminal();
    return <Object?>[(t.cursorX + 1).toDouble(), (t.cursorY + 1).toDouble()];
  });

  defineAll(['setCursorPos'], (list) {
    final args = Args('setCursorPos', list);
    terminal().setCursorPos(args.integer(0) - 1, args.integer(1) - 1);
    return noValues;
  });

  defineAll(['getCursorBlink'], (_) => one(terminal().cursorBlink));

  defineAll(['setCursorBlink'], (list) {
    terminal().setCursorBlink(Args('setCursorBlink', list).boolean(0));
    return noValues;
  });

  defineAll(['getSize'], (_) {
    final t = terminal();
    return <Object?>[t.width.toDouble(), t.height.toDouble()];
  });

  defineAll(['clear'], (_) {
    terminal().clear();
    return noValues;
  });

  defineAll(['clearLine'], (_) {
    terminal().clearLine();
    return noValues;
  });

  defineAll(['getTextColour', 'getTextColor'], (_) => one((1 << terminal().textColour).toDouble()));

  defineAll(['setTextColour', 'setTextColor'], (list) {
    final colour = parseColour(Args('setTextColour', list).integer(0));
    terminal().setTextColour(colour);
    return noValues;
  });

  defineAll(['getBackgroundColour', 'getBackgroundColor'], (_) => one((1 << terminal().backgroundColour).toDouble()));

  defineAll(['setBackgroundColour', 'setBackgroundColor'], (list) {
    final colour = parseColour(Args('setBackgroundColour', list).integer(0));
    terminal().setBackgroundColour(colour);
    return noValues;
  });

  defineAll(['isColour', 'isColor'], (_) => one(terminal().isColour));

  defineAll(['blit'], (list) {
    final args = Args('blit', list);
    final text = args.string(0);
    final fg = args.string(1);
    final bg = args.string(2);
    if (fg.length != text.length || bg.length != text.length) {
      throw LuaError.message('Arguments must be the same length');
    }
    final t = terminal();
    t.blit(text, fg, bg);
    t.setCursorPos(t.cursorX + text.length, t.cursorY);
    return noValues;
  });

  defineAll(['setPaletteColour', 'setPaletteColor'], (list) {
    final args = Args('setPaletteColour', list);
    final index = 15 - parseColour(args.integer(0));
    final t = terminal();
    if (list.length == 2) {
      final rgb = args.integer(1);
      t.palette.setColour(
        index,
        ((rgb >> 16) & 0xFF) / 255,
        ((rgb >> 8) & 0xFF) / 255,
        (rgb & 0xFF) / 255,
      );
    } else {
      t.palette.setColour(index, _finite(args, 1), _finite(args, 2), _finite(args, 3));
    }
    t.setChanged();
    return noValues;
  });

  defineAll(['getPaletteColour', 'getPaletteColor'], (list) {
    final index = 15 - parseColour(Args('getPaletteColour', list).integer(0));
    final c = terminal().palette.colour(index);
    return <Object?>[c[0], c[1], c[2]];
  });
}

double _finite(Args args, int index) {
  final value = args.number(index);
  if (value.isNaN || value.isInfinite) args.wrongType(index, 'number');
  return value;
}

/// Builds the global `term` table for a computer's own terminal.
LuaTable buildTermApi(Terminal terminal) {
  final table = LuaTable();
  addTermMethods(table, () => terminal);
  NativeImpl native(String name) => (list) {
    final index = 15 - parseColour(Args(name, list).integer(0));
    final rgb = defaultPaletteRgb[index];
    return <Object?>[
      ((rgb >> 16) & 0xFF) / 255,
      ((rgb >> 8) & 0xFF) / 255,
      (rgb & 0xFF) / 255,
    ];
  };
  table
    ..setString('nativePaletteColour', NativeFunction('nativePaletteColour', native('nativePaletteColour')))
    ..setString('nativePaletteColor', NativeFunction('nativePaletteColor', native('nativePaletteColor')));
  return table;
}

// The `redstone` / `rs` API.
import '../../lua/lua.dart';
import '../redstone.dart';
import '../side.dart';

LuaTable buildRedstoneApi(RedstoneState state) {
  final table = LuaTable();

  ComputerSide side(Args args, int index) {
    final name = args.string(index);
    final parsed = ComputerSide.parse(name);
    if (parsed == null) args.bad(index, "unknown option '$name'");
    return parsed;
  }

  void def(List<String> names, NativeImpl Function(String name) make) {
    for (final name in names) {
      table.setString(name, NativeFunction(name, make(name)));
    }
  }

  def(['getSides'], (_) => (_) {
    final sides = LuaTable();
    for (final s in ComputerSide.values) {
      sides.setInt(s.index + 1, s.luaName);
    }
    return one(sides);
  });

  def(['setOutput'], (name) => (list) {
    final args = Args(name, list);
    state.setOutput(side(args, 0), args.boolean(1) ? 15 : 0);
    return noValues;
  });

  def(['getOutput'], (name) => (list) {
    final args = Args(name, list);
    return one(state.getOutput(side(args, 0)) > 0);
  });

  def(['getInput'], (name) => (list) {
    final args = Args(name, list);
    return one(state.getInput(side(args, 0)) > 0);
  });

  def(['setAnalogOutput', 'setAnalogueOutput'], (name) => (list) {
    final args = Args(name, list);
    final s = side(args, 0);
    final level = args.integer(1);
    if (level < 0 || level > 15) {
      throw LuaError.message('Expected number in range 0-15');
    }
    state.setOutput(s, level);
    return noValues;
  });

  def(['getAnalogOutput', 'getAnalogueOutput'], (name) => (list) {
    final args = Args(name, list);
    return one(state.getOutput(side(args, 0)).toDouble());
  });

  def(['getAnalogInput', 'getAnalogueInput'], (name) => (list) {
    final args = Args(name, list);
    return one(state.getInput(side(args, 0)).toDouble());
  });

  def(['setBundledOutput'], (name) => (list) {
    final args = Args(name, list);
    state.setBundledOutput(side(args, 0), args.integer(1) & 0xFFFF);
    return noValues;
  });

  def(['getBundledOutput'], (name) => (list) {
    final args = Args(name, list);
    return one(state.getBundledOutput(side(args, 0)).toDouble());
  });

  def(['getBundledInput'], (name) => (list) {
    final args = Args(name, list);
    return one(state.getBundledInput(side(args, 0)).toDouble());
  });

  def(['testBundledInput'], (name) => (list) {
    final args = Args(name, list);
    final mask = args.integer(1);
    return one((state.getBundledInput(side(args, 0)) & mask) == mask);
  });

  return table;
}

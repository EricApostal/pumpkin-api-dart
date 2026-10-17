// The exports of the C Lua module (`native/lua`), imported from the core
// module `lua` that the component linker adds next to this program.
//
// Pointers are addresses in the module's own memory. Strings in that memory
// hold bytes, which map one to one onto the code units of a Lua string in
// this package (see `lua/value.dart`).
// ignore_for_file: import_internal_library
import 'dart:_wasm';

@pragma('wasm:import', 'lua.memory')
@pragma('wasm:memory-type', MemoryType(limits: Limits(64)))
external Memory get memory;

@pragma('wasm:import', 'lua._initialize')
external WasmVoid _initialize();
@pragma('wasm:import', 'lua.cc_new')
external WasmI32 _ccNew(WasmI32 memoryLimit);
@pragma('wasm:import', 'lua.cc_pushhost')
external WasmVoid _ccPushHost(WasmI32 l, WasmI32 id);
@pragma('wasm:import', 'lua.cc_sethook')
external WasmVoid _ccSetHook(WasmI32 l, WasmI32 count);
@pragma('wasm:import', 'lua.cc_alloc')
external WasmI32 _ccAlloc(WasmI32 size);
@pragma('wasm:import', 'lua.cc_free')
external WasmVoid _ccFree(WasmI32 pointer);
@pragma('wasm:import', 'lua.cc_take_preempted')
external WasmI32 _ccTakePreempted();
@pragma('wasm:import', 'lua.cc_selftest')
external WasmI32 _ccSelftest();
@pragma('wasm:import', 'lua.cc_selftest_error')
external WasmI32 _ccSelftestError();

@pragma('wasm:import', 'lua.cc_close')
external WasmVoid _ccClose(WasmI32 l);
@pragma('wasm:import', 'lua.cc_memory_used')
external WasmI32 _ccMemoryUsed(WasmI32 l);
@pragma('wasm:import', 'lua.lua_gettop')
external WasmI32 _gettop(WasmI32 l);
@pragma('wasm:import', 'lua.lua_settop')
external WasmVoid _settop(WasmI32 l, WasmI32 index);
@pragma('wasm:import', 'lua.lua_status')
external WasmI32 _status(WasmI32 l);
@pragma('wasm:import', 'lua.lua_resume')
external WasmI32 _resume(WasmI32 l, WasmI32 from, WasmI32 nargs);
@pragma('wasm:import', 'lua.lua_newthread')
external WasmI32 _newthread(WasmI32 l);
@pragma('wasm:import', 'lua.lua_type')
external WasmI32 _type(WasmI32 l, WasmI32 index);
@pragma('wasm:import', 'lua.lua_toboolean')
external WasmI32 _toboolean(WasmI32 l, WasmI32 index);
@pragma('wasm:import', 'lua.lua_tonumberx')
external WasmF64 _tonumberx(WasmI32 l, WasmI32 index, WasmI32 isnum);
@pragma('wasm:import', 'lua.lua_tolstring')
external WasmI32 _tolstring(WasmI32 l, WasmI32 index, WasmI32 len);
@pragma('wasm:import', 'lua.lua_pushnil')
external WasmVoid _pushnil(WasmI32 l);
@pragma('wasm:import', 'lua.lua_pushnumber')
external WasmVoid _pushnumber(WasmI32 l, WasmF64 n);
@pragma('wasm:import', 'lua.lua_pushboolean')
external WasmVoid _pushboolean(WasmI32 l, WasmI32 b);
@pragma('wasm:import', 'lua.lua_pushlstring')
external WasmI32 _pushlstring(WasmI32 l, WasmI32 s, WasmI32 len);
@pragma('wasm:import', 'lua.lua_pushvalue')
external WasmVoid _pushvalue(WasmI32 l, WasmI32 index);
@pragma('wasm:import', 'lua.lua_createtable')
external WasmVoid _createtable(WasmI32 l, WasmI32 narr, WasmI32 nrec);
@pragma('wasm:import', 'lua.lua_rawset')
external WasmVoid _rawset(WasmI32 l, WasmI32 index);
@pragma('wasm:import', 'lua.lua_rawseti')
external WasmVoid _rawseti(WasmI32 l, WasmI32 index, WasmI32 n);
@pragma('wasm:import', 'lua.lua_rawgeti')
external WasmVoid _rawgeti(WasmI32 l, WasmI32 index, WasmI32 n);
@pragma('wasm:import', 'lua.lua_next')
external WasmI32 _next(WasmI32 l, WasmI32 index);
@pragma('wasm:import', 'lua.lua_setglobal')
external WasmVoid _setglobal(WasmI32 l, WasmI32 name);
@pragma('wasm:import', 'lua.lua_getglobal')
external WasmVoid _getglobal(WasmI32 l, WasmI32 name);
@pragma('wasm:import', 'lua.lua_xmove')
external WasmVoid _xmove(WasmI32 from, WasmI32 to, WasmI32 n);
@pragma('wasm:import', 'lua.lua_gc')
external WasmI32 _gc(WasmI32 l, WasmI32 what, WasmI32 data);
@pragma('wasm:import', 'lua.lua_pcallk')
external WasmI32 _pcallk(
  WasmI32 l,
  WasmI32 nargs,
  WasmI32 nresults,
  WasmI32 errfunc,
  WasmI32 ctx,
  WasmI32 k,
);
@pragma('wasm:import', 'lua.luaL_loadbufferx')
external WasmI32 _loadbufferx(
  WasmI32 l,
  WasmI32 buffer,
  WasmI32 size,
  WasmI32 name,
  WasmI32 mode,
);
@pragma('wasm:import', 'lua.luaL_ref')
external WasmI32 _ref(WasmI32 l, WasmI32 table);
@pragma('wasm:import', 'lua.luaL_unref')
external WasmVoid _unref(WasmI32 l, WasmI32 table, WasmI32 ref);
@pragma('wasm:import', 'lua.luaL_where')
external WasmVoid _where(WasmI32 l, WasmI32 level);

WasmI32 _i(int value) => WasmI32.fromInt(value);

/// `LUA_REGISTRYINDEX`.
const int registryIndex = -1001000;

/// The basic types of `lua.h`.
const int typeNil = 0;
const int typeBoolean = 1;
const int typeNumber = 3;
const int typeString = 4;
const int typeTable = 5;
const int typeFunction = 6;

/// `lua_resume` and `lua_pcall` status codes.
const int statusOk = 0;
const int statusYield = 1;

void initialize() => _initialize();

/// A new state that may allocate at most [memoryLimit] bytes, or 0 if it
/// could not be created.
int newState(int memoryLimit) => _ccNew(_i(memoryLimit)).toIntUnsigned();
void pushHostFunction(int l, int id) => _ccPushHost(_i(l), _i(id));
void setCountHook(int l, int count) => _ccSetHook(_i(l), _i(count));
bool takePreempted() => _ccTakePreempted().toIntUnsigned() != 0;
void closeState(int l) => _ccClose(_i(l));
int memoryUsed(int l) => _ccMemoryUsed(_i(l)).toIntUnsigned();
int top(int l) => _gettop(_i(l)).toIntSigned();
void setTop(int l, int index) => _settop(_i(l), _i(index));
int status(int l) => _status(_i(l)).toIntSigned();
int resume(int l, int from, int nargs) =>
    _resume(_i(l), _i(from), _i(nargs)).toIntSigned();
int newThread(int l) => _newthread(_i(l)).toIntUnsigned();
int typeOf(int l, int index) => _type(_i(l), _i(index)).toIntSigned();
bool toBoolean(int l, int index) => _toboolean(_i(l), _i(index)).toIntUnsigned() != 0;
double toNumber(int l, int index) =>
    _tonumberx(_i(l), _i(index), _i(0)).toDouble();
void pushNil(int l) => _pushnil(_i(l));
void pushNumber(int l, double n) => _pushnumber(_i(l), WasmF64.fromDouble(n));
void pushBoolean(int l, bool b) => _pushboolean(_i(l), _i(b ? 1 : 0));
void pushValue(int l, int index) => _pushvalue(_i(l), _i(index));
void createTable(int l, int narr, int nrec) =>
    _createtable(_i(l), _i(narr), _i(nrec));
void rawSet(int l, int index) => _rawset(_i(l), _i(index));
void rawSetInt(int l, int index, int n) => _rawseti(_i(l), _i(index), _i(n));
void rawGetInt(int l, int index, int n) => _rawgeti(_i(l), _i(index), _i(n));
bool next(int l, int index) => _next(_i(l), _i(index)).toIntUnsigned() != 0;
void xmove(int from, int to, int n) => _xmove(_i(from), _i(to), _i(n));
int collectGarbage(int l, int what, int data) =>
    _gc(_i(l), _i(what), _i(data)).toIntSigned();
int reference(int l, int table) => _ref(_i(l), _i(table)).toIntSigned();
void unreference(int l, int table, int ref) => _unref(_i(l), _i(table), _i(ref));

/// Calls the function below [nargs] arguments, in protected mode.
int pcall(int l, int nargs, int nresults) => _pcallk(
  _i(l),
  _i(nargs),
  _i(nresults),
  _i(0),
  _i(0),
  _i(0),
).toIntSigned();

/// Pushes the position of the Lua function at [level] ("chunk:line: ").
void pushWhere(int l, int level) => _where(_i(l), _i(level));

/// Runs the C self test; null if it passes, otherwise a description.
String? selftest() {
  final failed = _ccSelftest().toIntSigned();
  if (failed == 0) return null;
  final pointer = _ccSelftestError().toIntUnsigned();
  return 'case $failed: ${pointer == 0 ? '?' : _readC(pointer)}';
}

String _readC(int pointer) {
  final out = StringBuffer();
  for (var i = pointer; ; i++) {
    final byte = memory.loadUint8(i).toIntUnsigned();
    if (byte == 0) return out.toString();
    out.writeCharCode(byte);
  }
}

// -- Strings -----------------------------------------------------------------

int _scratch = 0;
int _scratchSize = 0;

int _scratchFor(int size) {
  if (size > _scratchSize) {
    if (_scratch != 0) _ccFree(_i(_scratch));
    var capacity = _scratchSize == 0 ? 4096 : _scratchSize;
    while (capacity < size) {
      capacity *= 2;
    }
    _scratch = _ccAlloc(_i(capacity)).toIntUnsigned();
    _scratchSize = capacity;
  }
  return _scratch;
}

/// Copies the bytes of [value] (code units 0..255) into the module's memory
/// and returns their address. Valid until the next call.
int _stage(String value) {
  final length = value.length;
  final pointer = _scratchFor(length + 1);
  for (var i = 0; i < length; i++) {
    memory.storeInt8(pointer + i, _i(value.codeUnitAt(i)));
  }
  memory.storeInt8(pointer + length, _i(0));
  return pointer;
}

void pushString(int l, String value) {
  _pushlstring(_i(l), _i(_stage(value)), _i(value.length));
}

void setGlobal(int l, String name) => _setglobal(_i(l), _i(_stage(name)));

void getGlobal(int l, String name) => _getglobal(_i(l), _i(_stage(name)));

/// Compiles [source]; the function is pushed on success, otherwise the error
/// message. Returns the status code.
int loadString(int l, String source, String chunkName) {
  final length = source.length;
  final buffer = _ccAlloc(_i(length + 1)).toIntUnsigned();
  for (var i = 0; i < length; i++) {
    memory.storeInt8(buffer + i, _i(source.codeUnitAt(i)));
  }
  final name = _stage(chunkName);
  final code = _loadbufferx(
    _i(l),
    _i(buffer),
    _i(length),
    _i(name),
    _i(0),
  ).toIntSigned();
  _ccFree(_i(buffer));
  return code;
}

/// The string at [index], converting numbers like Lua does, or null if the
/// value is neither.
String? toStringOrNull(int l, int index) {
  final lengthPointer = _scratchFor(8) + 4;
  final pointer = _tolstring(_i(l), _i(index), _i(lengthPointer)).toIntUnsigned();
  if (pointer == 0) return null;
  final length = memory.loadUint32(lengthPointer).toIntUnsigned();
  final units = List<int>.filled(length, 0);
  for (var i = 0; i < length; i++) {
    units[i] = memory.loadUint8(pointer + i).toIntUnsigned();
  }
  return String.fromCharCodes(units);
}

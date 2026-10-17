#include <string.h>
#include "lua.h"
#include "lauxlib.h"

lua_State *cc_new(size_t limit);
void cc_close(lua_State *L);

static const char *last_error;

/* Runs `src` and returns 0 when it returns a true value. On failure the
 * message is available through cc_selftest_error. */
static int run_case(const char *src) {
  lua_State *L = cc_new(64 << 20);
  int rc = luaL_loadstring(L, src);
  if (rc == LUA_OK) rc = lua_pcall(L, 0, 1, 0);
  if (rc != LUA_OK) {
    last_error = lua_tostring(L, -1);
    return rc;
  }
  if (!lua_toboolean(L, -1)) {
    last_error = "returned false";
    return -1;
  }
  cc_close(L);
  return 0;
}

static const char *const cases[] = {
  "return 1 + 1 == 2",
  "return ('x'):rep(3) == 'xxx'",
  "local t = {} for i = 1, 10 do t[#t + 1] = i end return table.concat(t, ',') == '1,2,3,4,5,6,7,8,9,10'",
  "local s = 0 for i = 1, 10 do if i % 2 == 0 then goto c end s = s + i ::c:: end return s == 25",
  "return not pcall(error, 'x')",
  "return string.format('%.14g', 0.1) == '0.1'",
  "return tostring(1e15) == '1e+15' and tostring(12345.678) == '12345.678'",
  "local co = coroutine.wrap(function(a) local b = coroutine.yield(a + 1) return b * 2 end) return co(1) == 2 and co(5) == 10",
  "return bit32.band(0xff, 0x0f) == 15",
  "return ('a.b'):gsub('%.', '%%%.') == 'a%.b'",
  "return '\\u{48}\\u{20AC}' == 'H\\xE2\\x82\\xAC'",
  "return utf8.len('H\\u{20AC}') == 2 and utf8.codepoint('\\u{20AC}') == 0x20AC",
  "return select('#', table.move({1,2,3}, 1, 3, 2)) == 1",
  "local t = table.move({1,2,3}, 1, 3, 2) return t[1] == 1 and t[2] == 1 and t[4] == 3",
  "return coroutine.isyieldable() == false",
  "local ok, e = pcall(coroutine.wrap(function() error('x') end)) return e:find('^%[string') ~= nil or e == 'x' or e:find('x', 1, true) ~= nil",
  "return _VERSION == 'Lua 5.1' and unpack ~= nil and loadstring ~= nil",
  "local f = function() return x end local env = {x = 7} setfenv(f, env) return f() == 7 and getfenv(f) == env",
  "return string.dump == nil and print == nil and loadfile == nil and dofile == nil",
  "return not load(string.char(27) .. 'Lua')",
  "local n = 0 for i = 1, 100 do n = n + #string.rep('x', 100) end return n == 10000",
  "local ok = pcall(string.rep, 'x', 1e10) return not ok",
  "local function f() return 1 + f() end local ok, e = pcall(f) return not ok and e:find('stack overflow', 1, true) ~= nil",
  "local function g(n) local ok, e = pcall(g, n + 1) return n end local ok = pcall(g, 1) return ok",
  "local function r() local co = coroutine.wrap(r) return co() end local ok, e = pcall(r) return not ok",
  "local function r(s) return (s:gsub('x', r)) end local ok = pcall(r, 'xxxx') return not ok",
  "local s = ('('):rep(1000) local f, e = load('return ' .. s) return f == nil",
  "local t = setmetatable({}, {__index = function(t, k) return t[k] end}) return not pcall(function() return t.x end)",
  NULL
};

const char *cc_selftest_error(void) { return last_error; }

/* Returns 0 when every case passes, otherwise the 1-based index of the first
 * failing case. */
int cc_selftest(void) {
  for (int i = 0; cases[i]; i++) {
    if (run_case(cases[i]) != 0) return i + 1;
  }
  return 0;
}

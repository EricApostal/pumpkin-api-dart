#include <stddef.h>
#include <stdlib.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lstate.h"

#define HOST_IMPORT(name) \
  __attribute__((import_module("host"), import_name(name)))

/* Single entry point into the embedding Dart code. Ids below CC_HOST_BASE are
 * reserved for the bridge itself. */
HOST_IMPORT("call") extern int host_call(int id, int a, int b, int c);

enum { HOST_HOOK = 0 };

/* What a host function returns: the number of results, or a negative code for
 * an error whose value is on top of the stack. */
enum { HOST_ERROR_WITH_POSITION = -1, HOST_ERROR = -2 };

/* What the hook handler returns. */
enum { HOOK_CONTINUE = 0, HOOK_ABORT = 1, HOOK_YIELD = 2 };

static int preempted;

/* Whether the last resume stopped because the hook yielded. */
int cc_take_preempted(void) {
  int r = preempted;
  preempted = 0;
  return r;
}

static int host_trampoline(lua_State *L) {
  int id = (int)lua_tointeger(L, lua_upvalueindex(1));
  int n = host_call(id, (int)(size_t)L, 0, 0);
  if (n >= 0) return n;
  if (n == HOST_ERROR_WITH_POSITION) {
    luaL_where(L, 1);
    lua_insert(L, -2);
    lua_concat(L, 2);
  }
  return lua_error(L);
}

static void count_hook(lua_State *L, lua_Debug *ar) {
  (void)ar;
  switch (host_call(HOST_HOOK, (int)(size_t)L, 0, 0)) {
    case HOOK_ABORT:
      luaL_error(L, "Too long without yielding");
      break;
    case HOOK_YIELD:
      if (L->nny == 0) {
        preempted = 1;
        lua_yield(L, 0);
      }
      break;
  }
}

int luaopen_utf8(lua_State *L);
void cc_close(lua_State *L);

static const luaL_Reg libs[] = {
  {"_G", luaopen_base},
  {LUA_COLIBNAME, luaopen_coroutine},
  {LUA_TABLIBNAME, luaopen_table},
  {LUA_STRLIBNAME, luaopen_string},
  {LUA_BITLIBNAME, luaopen_bit32},
  {LUA_MATHLIBNAME, luaopen_math},
  {LUA_DBLIBNAME, luaopen_debug},
  {"utf8", luaopen_utf8},
  {NULL, NULL}
};

typedef struct {
  size_t used;
  size_t limit;
} Memory;

static void *limited_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  Memory *m = ud;
  if (!ptr) osize = 0;
  if (nsize == 0) {
    free(ptr);
    m->used -= osize;
    return NULL;
  }
  if (nsize > osize && m->used + (nsize - osize) > m->limit) return NULL;
  void *p = realloc(ptr, nsize);
  if (p) m->used += nsize - osize;
  return p;
}

static const char prelude[] =
#include "prelude.inc"
;

lua_State *cc_new(size_t limit) {
  Memory *m = malloc(sizeof(Memory));
  if (!m) return NULL;
  m->used = 0;
  m->limit = limit;
  lua_State *L = lua_newstate(limited_alloc, m);
  if (!L) {
    free(m);
    return NULL;
  }
  for (const luaL_Reg *lib = libs; lib->func; lib++) {
    luaL_requiref(L, lib->name, lib->func, 1);
    lua_pop(L, 1);
  }
  if (luaL_loadbuffer(L, prelude, sizeof(prelude) - 1, "=prelude") != LUA_OK ||
      lua_pcall(L, 0, 0, 0) != LUA_OK) {
    cc_close(L);
    return NULL;
  }
  return L;
}

void cc_close(lua_State *L) {
  void *ud;
  lua_getallocf(L, &ud);
  lua_close(L);
  free(ud);
}

size_t cc_memory_used(lua_State *L) {
  void *ud;
  lua_getallocf(L, &ud);
  return ((Memory *)ud)->used;
}

void cc_pushhost(lua_State *L, int id) {
  lua_pushinteger(L, id);
  lua_pushcclosure(L, host_trampoline, 1);
}

void cc_sethook(lua_State *L, int count) {
  lua_sethook(L, count_hook, LUA_MASKCOUNT, count);
}

void *cc_alloc(size_t n) { return __builtin_malloc(n); }
void cc_free(void *p) { __builtin_free(p); }

/* The component has no WASI. libc's stdio and clock paths are only reached
 * through code Lua never runs, but the linker still wants definitions for
 * them, so provide ones that always report ENOSYS. */
#define WASI_ENOSYS 52
#define WASI_STUB(name, ...) \
  int __imported_wasi_snapshot_preview1_##name(__VA_ARGS__)
WASI_STUB(clock_time_get, int a, long long b, int c) { (void)a; (void)b; (void)c; return WASI_ENOSYS; }
WASI_STUB(fd_close, int a) { (void)a; return WASI_ENOSYS; }
WASI_STUB(fd_read, int a, int b, int c, int d) { (void)a; (void)b; (void)c; (void)d; return WASI_ENOSYS; }
WASI_STUB(fd_seek, int a, long long b, int c, int d) { (void)a; (void)b; (void)c; (void)d; return WASI_ENOSYS; }
WASI_STUB(fd_write, int a, int b, int c, int d) { (void)a; (void)b; (void)c; (void)d; return WASI_ENOSYS; }

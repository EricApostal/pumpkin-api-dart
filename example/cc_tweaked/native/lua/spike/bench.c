#include <stdio.h>
#include <time.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static void run(const char *name, const char *src) {
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  double t0 = now_ms();
  int rc = luaL_dostring(L, src);
  double t1 = now_ms();
  printf("%s: %.0f ms (rc=%d%s%s)\n", name, t1 - t0, rc, rc ? " " : "", rc ? lua_tostring(L, -1) : "");
  lua_close(L);
}

int main(void) {
  run("loop 5M adds", "local x=0 for i=1,5000000 do x = x + i end return x");
  run("fib(27)", "local function fib(n) if n<2 then return n end return fib(n-1)+fib(n-2) end return fib(27)");
  run("string concat 200k", "local t={} for i=1,200000 do t[#t+1]=tostring(i)..':x' end return #table.concat(t)");
  run("table insert/sort 100k", "local t={} for i=1,100000 do t[i]=(i*7919)%100003 end table.sort(t) return t[1]");
  run("error/pcall 100k", "local n=0 for i=1,100000 do local ok = pcall(error, 'x') if not ok then n=n+1 end end return n");
  run("goto", "local s=0 for i=1,10 do if i%2==0 then goto continue end s=s+i ::continue:: end return s");
  return 0;
}

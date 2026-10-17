/* The utf8 library of Lua 5.3, on the Lua 5.2 API (numbers are doubles). */
#include <assert.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define MAXUNICODE 0x10FFFF
#define iscont(p) ((*(p) & 0xC0) == 0x80)

typedef long long utfint;

/* from strlib: translate a relative string position */
static utfint u_posrelat (utfint pos, size_t len) {
  if (pos >= 0) return pos;
  else if (0u - (size_t)pos > len) return 0;
  else return (utfint)len + pos + 1;
}

/* Decode one UTF-8 sequence, returning NULL if the string is not a valid one
 * (overlong sequences and surrogates included). */
static const char *utf8_decode (const char *o, utfint *val) {
  static const unsigned int limits[] =
        {0xFF, 0x7F, 0x7FF, 0xFFFF};
  const unsigned char *s = (const unsigned char *)o;
  unsigned int c = s[0];
  unsigned int res = 0;  /* final result */
  if (c < 0x80)  /* ascii? */
    res = c;
  else {
    int count = 0;  /* to count number of continuation bytes */
    while (c & 0x40) {  /* still have continuation bytes? */
      int cc = s[++count];  /* read next byte */
      if ((cc & 0xC0) != 0x80)  /* not a continuation byte? */
        return NULL;  /* invalid byte sequence */
      res = (res << 6) | (cc & 0x3F);  /* add lower 6 bits from cont. byte */
      c <<= 1;  /* to test next bit */
    }
    res |= ((unsigned int)(c & 0x7F) << (count * 5));  /* add first byte */
    if (count > 3 || res > 0x7FFFFFFFu || res < limits[count])
      return NULL;  /* invalid byte sequence */
    s += count;  /* skip continuation bytes read */
  }
  if (res > MAXUNICODE || (0xD800u <= res && res <= 0xDFFFu))
    return NULL;
  if (val) *val = res;
  return (const char *)s + 1;  /* +1 to include first byte */
}

static int utflen (lua_State *L) {
  int n = 0;
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  utfint posi = u_posrelat((utfint)luaL_optnumber(L, 2, 1), len);
  utfint posj = u_posrelat((utfint)luaL_optnumber(L, 3, -1), len);
  luaL_argcheck(L, 1 <= posi && --posi <= (utfint)len, 2,
                   "initial position out of string");
  luaL_argcheck(L, --posj < (utfint)len, 3,
                   "final position out of string");
  while (posi <= posj) {
    const char *s1 = utf8_decode(s + posi, NULL);
    if (s1 == NULL) {  /* conversion error? */
      lua_pushnil(L);  /* return nil ... */
      lua_pushnumber(L, (lua_Number)(posi + 1));  /* ... and current position */
      return 2;
    }
    posi = s1 - s;
    n++;
  }
  lua_pushnumber(L, n);
  return 1;
}

static int codepoint (lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  utfint posi = u_posrelat((utfint)luaL_optnumber(L, 2, 1), len);
  utfint pose = u_posrelat((utfint)luaL_optnumber(L, 3, (lua_Number)posi), len);
  int n;
  const char *se;
  luaL_argcheck(L, posi >= 1, 2, "out of range");
  luaL_argcheck(L, pose <= (utfint)len, 3, "out of range");
  if (posi > pose) return 0;  /* empty interval; return no values */
  if (pose - posi >= INT_MAX)  /* (lua_Integer -> int) overflow? */
    return luaL_error(L, "string slice too long");
  n = (int)(pose - posi) + 1;
  luaL_checkstack(L, n, "string slice too long");
  n = 0;
  se = s + pose;
  for (s += posi - 1; s < se;) {
    utfint code;
    s = utf8_decode(s, &code);
    if (s == NULL)
      return luaL_error(L, "invalid UTF-8 code");
    lua_pushnumber(L, (lua_Number)code);
    n++;
  }
  return n;
}

static void pushutfchar (lua_State *L, int arg) {
  lua_Number code = luaL_checknumber(L, arg);
  luaL_argcheck(L, 0 <= code && code <= 0x7FFFFFFFu, arg, "value out of range");
  {
    unsigned long x = (unsigned long)code;
    char buff[8];
    int n = 1;
    if (x < 0x80)
      buff[7] = (char)x;
    else {
      unsigned int mfb = 0x3f;
      do {
        buff[8 - (n++)] = (char)(0x80 | (x & 0x3f));
        x >>= 6;
        mfb >>= 1;
      } while (x > mfb);
      buff[8 - n] = (char)((~mfb << 1) | x);
    }
    lua_pushlstring(L, buff + 8 - n, n);
  }
}

static int utfchar (lua_State *L) {
  int n = lua_gettop(L);  /* number of arguments */
  if (n == 1)  /* optimize common case of single char */
    pushutfchar(L, 1);
  else {
    int i;
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (i = 1; i <= n; i++) {
      pushutfchar(L, i);
      luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
  }
  return 1;
}

static int byteoffset (lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  utfint n = (utfint)luaL_checknumber(L, 2);
  utfint posi = (n > 0) ? 1 : (utfint)len + 1;
  posi = u_posrelat((utfint)luaL_optnumber(L, 3, (lua_Number)posi), len);
  luaL_argcheck(L, 1 <= posi && --posi <= (utfint)len, 3,
                   "position out of range");
  if (n == 0) {
    /* find beginning of current byte sequence */
    while (posi > 0 && iscont(s + posi)) posi--;
  }
  else {
    if (iscont(s + posi))
      luaL_error(L, "initial position is a continuation byte");
    if (n < 0) {
       while (n < 0 && posi > 0) {  /* move back */
         do {  /* find beginning of previous character */
           posi--;
         } while (posi > 0 && iscont(s + posi));
         n++;
       }
     }
     else {
       n--;  /* do not move for 1st character */
       while (n > 0 && posi < (utfint)len) {
         do {  /* find beginning of next character */
           posi++;
         } while (iscont(s + posi));  /* (cannot pass final '\0') */
         n--;
       }
     }
  }
  if (n == 0)  /* did it find given character? */
    lua_pushnumber(L, (lua_Number)(posi + 1));
  else  /* no such character */
    lua_pushnil(L);
  return 1;
}

static int iter_aux (lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  utfint n = (utfint)lua_tonumber(L, 2);
  if (n < 0) n = 0;  /* first iteration? */
  if (n < (utfint)len) {
    while (iscont(s + n)) n++;  /* go to next character */
  }
  if (n >= (utfint)len)  /* (also handles original 'n' being negative) */
    return 0;  /* no more codepoints */
  else {
    utfint code;
    const char *next = utf8_decode(s + n, &code);
    if (next == NULL || iscont(next))
      return luaL_error(L, "invalid UTF-8 code");
    lua_pushnumber(L, (lua_Number)(n + 1));
    lua_pushnumber(L, (lua_Number)code);
    return 2;
  }
}

static int iter_codes (lua_State *L) {
  luaL_checkstring(L, 1);
  lua_pushcfunction(L, iter_aux);
  lua_pushvalue(L, 1);
  lua_pushnumber(L, 0);
  return 3;
}

/* pattern to match a single UTF-8 character */
#define UTF8PATT	"[\0-\x7F\xC2-\xFD][\x80-\xBF]*"

static const luaL_Reg funcs[] = {
  {"offset", byteoffset},
  {"codepoint", codepoint},
  {"char", utfchar},
  {"len", utflen},
  {"codes", iter_codes},
  {NULL, NULL}
};

int luaopen_utf8 (lua_State *L) {
  luaL_newlib(L, funcs);
  lua_pushlstring(L, UTF8PATT, sizeof(UTF8PATT) / sizeof(char) - 1);
  lua_setfield(L, -2, "charpattern");
  return 1;
}

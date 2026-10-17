-- Run once per state: brings the Lua 5.2 base of the C module in line with
-- what CC: Tweaked's Cobalt runtime offers (Lua 5.1 with a few additions).
local type, error = type, error
local getupvalue, upvaluejoin, getinfo = debug.getupvalue, debug.upvaluejoin, debug.getinfo
local plainRunning, loadedModules = coroutine.running, debug.getregistry()._LOADED

_VERSION = "Lua 5.1"

local function envIndex(f)
  for i = 1, math.huge do
    local name = getupvalue(f, i)
    if not name then return nil end
    if name == "_ENV" then return i end
  end
end

function getfenv(f)
  if f == nil then f = 1 end
  if type(f) ~= "function" and type(f) ~= "number" then
    error("bad argument #1 to 'getfenv' (number expected, got " .. type(f) .. ")", 2)
  end
  if type(f) == "number" then
    local info = f >= 1 and getinfo(1 + f, "f")
    f = info and info.func
    if not f then return _G end
  end
  local index = envIndex(f)
  if index then
    local _, env = getupvalue(f, index)
    return env
  end
  return _G
end

function setfenv(f, env)
  if type(env) ~= "table" then
    error("bad argument #2 to 'setfenv' (table expected, got " .. type(env) .. ")", 2)
  end
  if type(f) ~= "function" or getinfo(f, "S").what == "C" then
    error("'setfenv' cannot change environment of given object", 2)
  end
  local index = envIndex(f)
  if index then
    upvaluejoin(f, index, function() return env end, 1)
  end
  return f
end

function table.getn(t) return #t end

function table.foreach(t, f)
  for k, v in pairs(t) do
    local r = f(k, v)
    if r ~= nil then return r end
  end
end

function table.foreachi(t, f)
  for i = 1, #t do
    local r = f(i, t[i])
    if r ~= nil then return r end
  end
end

-- `coroutine.running` reports the coroutine running the BIOS as the main one.
local root
function coroutine.running()
  local co = plainRunning()
  return co, co == root
end

function __cc_set_root(thread)
  root = thread
  __cc_set_root = nil
end

-- The debug library: no hooks (the host owns the hook), and a registry that
-- only holds what the ROM looks for.
local registry = { _LOADED = loadedModules }
function debug.getregistry() return registry end
function debug.sethook() end
function debug.gethook() return nil end

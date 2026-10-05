// A tiny BIOS used when the CC: Tweaked jar is not installed, so a computer
// still boots into a Lua prompt. It is not CraftOS and shares no code with
// it: it only provides `print`, `read`, `sleep`, `os.run` and a few commands.
const String fallbackBios = r'''
local function installBasics()
  function os.version() return "CraftOS-lite 1.0" end

  function os.pullEventRaw(filter) return coroutine.yield(filter) end

  function os.pullEvent(filter)
    local event = table.pack(os.pullEventRaw(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
  end

  function sleep(seconds)
    local timer = os.startTimer(seconds or 0)
    repeat
      local _, id = os.pullEvent("timer")
    until id == timer
  end
  os.sleep = sleep

  function write(text)
    text = tostring(text)
    local w, h = term.getSize()
    local x, y = term.getCursorPos()
    local lines = 0
    local function newline()
      if y < h then y = y + 1 else term.scroll(1) end
      x = 1
      term.setCursorPos(x, y)
      lines = lines + 1
    end
    for i = 1, #text do
      local c = text:sub(i, i)
      if c == "\n" then
        newline()
      else
        if x > w then newline() end
        term.setCursorPos(x, y)
        term.write(c)
        x = x + 1
      end
    end
    term.setCursorPos(x, y)
    return lines
  end

  function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    return write(table.concat(parts, "\t") .. "\n")
  end

  function printError(...) print(...) end

  function read(replace, history, complete, default)
    term.setCursorBlink(true)
    local line = default or ""
    local startX, startY = term.getCursorPos()
    local function draw(erase)
      term.setCursorPos(startX, startY)
      if erase then
        term.write(string.rep(" ", #line + 1))
      elseif replace then
        term.write(string.rep(replace:sub(1, 1), #line))
      else
        term.write(line)
      end
      term.setCursorPos(startX + #line, startY)
    end
    draw()
    while true do
      local event, param = os.pullEvent()
      if event == "char" or event == "paste" then
        draw(true)
        line = line .. param
        draw()
      elseif event == "key" then
        if param == 257 or param == 335 then break end
        if param == 259 and #line > 0 then
          draw(true)
          line = line:sub(1, -2)
          draw()
        end
      end
    end
    term.setCursorBlink(false)
    write("\n")
    return line
  end

  function loadfile(path, mode, env)
    if type(mode) == "table" and env == nil then mode, env = nil, mode end
    local file = fs.open(path, "r")
    if not file then return nil, "File not found" end
    local source = file.readAll()
    file.close()
    return load(source, "@/" .. fs.combine(path), mode, env)
  end

  function dofile(path)
    local fn, err = loadfile(path, nil, _G)
    if not fn then error(err, 2) end
    return fn()
  end

  function os.run(env, path, ...)
    setmetatable(env, { __index = _G })
    local fn, err = loadfile(path, nil, env)
    if not fn then
      printError(err)
      return false
    end
    local ok, err = pcall(fn, ...)
    if not ok then
      if err and err ~= "" then printError(err) end
      return false
    end
    return true
  end

  local nativeShutdown, nativeReboot = os.shutdown, os.reboot
  function os.shutdown()
    nativeShutdown()
    while true do coroutine.yield() end
  end
  function os.reboot()
    nativeReboot()
    while true do coroutine.yield() end
  end
end

installBasics()

local commands = {}
function commands.ls(arg)
  local path = arg ~= "" and arg or "/"
  for _, name in ipairs(fs.list(path)) do
    print(name .. (fs.isDir(fs.combine(path, name)) and "/" or ""))
  end
end
function commands.cat(arg)
  local file = fs.open(arg, "r")
  if not file then return printError("No such file") end
  print(file.readAll())
  file.close()
end
function commands.rm(arg) fs.delete(arg) end
function commands.mkdir(arg) fs.makeDir(arg) end
function commands.id() print("This is computer #" .. os.getComputerID()) end
function commands.label(arg)
  if arg ~= "" then os.setComputerLabel(arg) end
  print(os.getComputerLabel() or "No label")
end
function commands.clear()
  term.clear()
  term.setCursorPos(1, 1)
end
function commands.shutdown() os.shutdown() end
function commands.reboot() os.reboot() end
function commands.help()
  print("ls cat rm mkdir id label clear shutdown reboot")
  print("Anything else runs a program, or Lua code.")
end

term.clear()
term.setCursorPos(1, 1)
print(os.version() .. " (fallback BIOS)")
print("The CC: Tweaked jar is not installed, see the plugin README.")
for _, name in ipairs({ "startup", "startup.lua" }) do
  if fs.exists(name) and not fs.isDir(name) then
    os.run({}, name)
    break
  end
end

while true do
  write("> ")
  local line = read()
  local command, rest = line:match("^(%S+)%s*(.*)$")
  if command then
    if commands[command] then
      local ok, err = pcall(commands[command], rest)
      if not ok then printError(err) end
    elseif fs.exists(command) or fs.exists(command .. ".lua") then
      local path = fs.exists(command) and command or command .. ".lua"
      local args = {}
      for word in rest:gmatch("%S+") do args[#args + 1] = word end
      os.run({}, path, table.unpack(args))
    else
      local fn = load("return " .. line, "=lua") or load(line, "=lua")
      if fn then
        local results = table.pack(pcall(fn))
        if results[1] then
          for i = 2, results.n do print(tostring(results[i])) end
        else
          printError(results[2])
        end
      else
        printError("Syntax error")
      end
    end
  end
end
''';

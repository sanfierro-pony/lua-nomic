local u64compat = require'primitives/primitives-u64'
-- Not sure we need this to have a fallback, but pretty-print does it in luvit
local success, uv = pcall(require, 'uv')
if not success then
  success, uv = pcall(require, 'luv')
end
assert(success, uv)

-- Print a code string with line numbers for easy debugging.
---@param code string the code to print
---@param start number|integer|nil the line number to start at
local function printCode(code, start)
  if code[#code] ~= "\n" then
    code = code .. "\n"
  end
  if start == nil then
    start = 1
  end
  local lines = {}
  for line in code:gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  local max = #tostring(#lines) + start - 1
  for i, line in ipairs(lines) do
    local prefix = tostring(i + start - 1)
    while #prefix < max do
      prefix = " " .. prefix
    end
    print(prefix .. " " .. line)
  end
end

local function colorfulToString(value)
  local t = type(value)
  if t == "string" then
    return "\27[1;32m\"" .. value .. "\"\27[0m"
  elseif t == "number" then
    return "\27[1;33m" .. tostring(value) .. "\27[0m"
  elseif u64compat.isU64(value) then
    return "\27[1;31m" .. tostring(value) .. "\27[0m"
  elseif t == "boolean" then
    return "\27[1;34m" .. tostring(value) .. "\27[0m"
  elseif t == "table" then
    return "\27[1;35m" .. tostring(value) .. "\27[0m"
  elseif t == "function" then
    return "\27[1;36m" .. tostring(value) .. "\27[0m"
  elseif t == "nil" then
    return "\27[1;37m" .. tostring(value) .. "\27[0m"
  else
    return tostring(value)
  end
end

local function console_write(fs, s)
  if uv.guess_handle(uv.fileno(fs) --[[@as integer]]) == 'tty' then
    repeat
      local n, e = uv.try_write(fs, s)
      if n then
        s = s:sub(n+1)
        n = 0
      else
        ---@cast e string
        if e:match('^EAGAIN') then
          n = 0
        else
          assert(n, e)
        end
      end
    until n==#s
  else
    uv.write(fs, s)
  end
end

local stdout = require 'pretty-print'.stdout

local function prettyPrintCore(value, maxDepth, indent, recursiveCheck)
  if type(value) == "table" then
    if recursiveCheck[value] then
      print(colorfulToString(value) .. " (recursive)")
    else
      console_write(stdout, colorfulToString(value) .. " {")
      local keys = {}
      for k in pairs(value) do
        table.insert(keys, k)
      end
      if #keys == 1 and type(value[keys[1]]) ~= "table" then
        local k = keys[1]
        local v = value[k]
        print(" " .. colorfulToString(k) .. " = " .. colorfulToString(v) .. " }")
      elseif #keys > 0 then
        print("")
        table.sort(keys)
        local newMaxDepth = maxDepth
        if maxDepth ~= nil then
          newMaxDepth = maxDepth - 1
        end
        recursiveCheck[value] = true
        for _, k in ipairs(keys) do
          local v = value[k]
          console_write(stdout, indent .. "  " .. colorfulToString(k) .. " = ")
          if maxDepth == 0 and type(v) == "table" then
            print(colorfulToString(v) .. " (stopped at depth limit)")
          else
            prettyPrintCore(v, newMaxDepth, indent .. "  ", recursiveCheck)
          end
        end
        recursiveCheck[value] = nil
        print(indent .. "}")
      else
        print(" }")
      end
    end
  else
    print(colorfulToString(value))
  end
end

-- Pretty print a value.
---@param value any the value to print
---@param maxDepth number|integer|nil the maximum depth to print, nil for unlimited, 0 for no recursion
local function prettyPrint(value, maxDepth)
  prettyPrintCore(value, maxDepth, "", {})
end

return {
  printCode = printCode,
  prettyPrint = prettyPrint,
}

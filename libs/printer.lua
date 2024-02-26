local u64compat = require'primitives/primitives-u64'
local success, helper = pcall(require, "printer-helper-luvit")
if not success then
  helper = require "printer-helper-generic"
end

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

local function isTableToInspect(value)
  return type(value) == "table" and not u64compat.isU64(value)
end

local function buildPrettyString(builder, value, maxDepth, indent, recursiveCheck)
  if isTableToInspect(value) then
    if recursiveCheck[value] then
      helper.appendToString(builder, value)
      builder[#builder + 1] = " (recursive)\n"
    else
      helper.appendToString(builder, value)
      builder[#builder + 1] = " {"
      local keys = {}
      for k in pairs(value) do
        keys[#keys + 1] = k
      end
      if #keys == 1 and type(value[keys[1]]) ~= "table" then
        local k = keys[1]
        local v = value[k]
        builder[#builder + 1] = " "
        helper.appendToString(builder, k)
        builder[#builder + 1] = " = "
        helper.appendToString(builder, v)
        builder[#builder + 1] = " }\n"
      elseif #keys > 0 then
        builder[#builder + 1] = "\n"
        table.sort(keys)
        local newMaxDepth = maxDepth
        if maxDepth ~= nil then
          newMaxDepth = maxDepth - 1
        end
        recursiveCheck[value] = true
        for _, k in ipairs(keys) do
          local v = value[k]
          builder[#builder + 1] = indent
          builder[#builder + 1] = "  "
          helper.appendToString(builder, k)
          builder[#builder + 1] = " = "
          if maxDepth == 0 and isTableToInspect(v) then
            helper.appendToString(builder, v)
            builder[#builder + 1] = " (stopped at depth limit)\n"
          else
            buildPrettyString(builder, v, newMaxDepth, indent .. "  ", recursiveCheck)
          end
        end
        recursiveCheck[value] = nil
        builder[#builder + 1] = indent
        builder[#builder + 1] = "}\n"
      else
        builder[#builder + 1] = " }\n"
      end
    end
  else
    helper.appendToString(builder, value)
    builder[#builder + 1] = "\n"
  end
end

-- Get a pretty string for a value. This may contain ANSI color codes.
---@param value any the value to get a pretty string for
---@param maxDepth number|integer|nil the maximum depth to print, nil for unlimited, 0 for no recursion
local function toPrettyString(value, maxDepth)
  local builder = {}
  buildPrettyString(builder, value, maxDepth, "", {})
  -- Remove trailing newline
  if builder[#builder]:sub(-1) == "\n" then
    builder[#builder] = builder[#builder]:sub(1, -2)
  end
  return table.concat(builder)
end

-- Pretty print a value.
---@param value any the value to print
---@param maxDepth number|integer|nil the maximum depth to print, nil for unlimited, 0 for no recursion
local function prettyPrint(value, maxDepth)
  local string = toPrettyString(value, maxDepth)
  print(string)
end

return {
  toPrettyString = toPrettyString,
  printCode = printCode,
  prettyPrint = prettyPrint,
}

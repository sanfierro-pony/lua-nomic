local u64compat = require'primitives/primitives-u64'

local escapeUnprintable = require'printer-helper-generic'.escapeUnprintable

local function colorfulToString(value)
  local t = type(value)
  if t == "string" then
    return "\27[1;32m\"" .. escapeUnprintable(value) .. "\"\27[0m"
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
    return escapeUnprintable(tostring(value))
  end
end

local function appendToString(builder, value)
  builder[#builder + 1] = colorfulToString(value)
end

return {
  appendToString = appendToString,
}


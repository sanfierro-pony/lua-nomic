local bint = require 'libs/bint' (64)

---@param thing any the thing to check if it's a u64
---@return boolean if it's u64
local function isU64(thing)
  return bint.isbint(thing)
end

---@param u64 table bint to convert to hex
---@return string hex of u64
local function toHex(u64)
  return bint.tobase(u64, 16, true) --[[@as string]]
end

---@param text string hex string
---@return table bint
local function parseHex(text)
  local result = bint.frombase(text, 16)
  if result == nil then
    error("failed to parse text as hex: " .. require 'printer'.toPrettyString(text))
  end
  return result
end

return setmetatable({
  isU64 = isU64,
  toHex = toHex,
}, {
  __call = function (_, text)
    return parseHex(text)
  end,
})

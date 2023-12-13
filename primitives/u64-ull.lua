local ffi = require'ffi'

local uint64_t = ffi.typeof('uint64_t')

---@param thing any the thing to check if it's a u64
---@return boolean if it's u64
local function isU64(thing)
  return type(thing) == 'cdata' and ffi.istype(uint64_t, thing)
end


---@param u64 integer u64 to convert to hex
---@return string hex of u64
local function toHex(u64)
  if not isU64(u64) then
    error("expected u64, got " .. type(u64))
  end
  local result = ""
  for i = 0, 15 do
    local digit = bit.band(bit.rshift(u64, 60 - i * 4), 0xF)
    result = result .. string.format("%x", digit)
  end
  return result
end

---@param text string hex string
---@return integer
local function parseHex(text)
  if type(text) ~= "string" then
    error("expected string, got " .. type(text))
  end
  local result = 0ULL
  for i = 1, #text do
    local c = text:sub(i, i)
    local digit = tonumber(c, 16) + 0ULL
    if digit == nil then
      error("invalid hex digit " .. c)
    end
    result = bit.bor(bit.lshift(result, 4), digit)
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


-- future ptr types
-- hashed array mapped trie
-- vtable

-- local pointerkinds = {
--   [0] = "struct",
--   [1] = "list",
--   [2] = "reserved", -- reserved for future uses
--   [3] = "other", -- caps if lsw all zeroes except kind, else vtable (future use)
-- }

local bit = _G['bit'] or _G['bit32'] or require 'primitives/polyfill/bit'

---@class StructPointerInfo
---@field kind "struct"
---@field offset number the offset in words to the struct from the end of the pointer
---@field datasize number the size of the data section of the struct in words
---@field pointersize number the size of the pointer section of the struct in words


---@class ListPointerInfo
---@field kind "list"
---@field offset number the offset in words to the list from the end of the pointer
---@field elementsize number the size of each element, 0 for 0 bits, 1 for 1 bit, 2 for 8 bits, 3 for 16 bits, 4 for 32 bits, 5 for 64 bits, 6 for pointer, 7 for composite
---@field listsize number the number of elements in the list, or words in the list if elementsize is 7

---@class CapabilityPointerInfo
---@field kind "capability"
---@field capabilityindex number

---@class NullPointerInfo
---@field kind "null"

---@alias PointerInfo StructPointerInfo|ListPointerInfo|CapabilityPointerInfo|NullPointerInfo

local unpackStructPointer, unpackListPointer, unpackCapPointer
local packStructPointer, packListPointer, packCapabilityPointer

-- Unpack a pointer from the least significant word and most significant word
---@param lsw number least significant word
---@param msw number most significant word
---@return PointerInfo
local function unpackPointer(lsw, msw)
  if lsw == 0 and msw == 0 then
    return {
      kind = 'null',
    }
  end
  local kind_id = bit.band(lsw, 3)
  if kind_id == 0 then
    return unpackStructPointer(lsw, msw)
  elseif kind_id == 1 then
    return unpackListPointer(lsw, msw)
  elseif lsw == 3 then -- intentionally check lsw, other bits must be 0 to mean cap ptr
    return unpackCapPointer(lsw, msw)
  end
  error("unhandled pointer kind " .. tostring(kind_id))
end

function unpackStructPointer(lsw, msw)
  local b = bit.arshift(bit.band(lsw, 0xFFFFFFFC), 2)
  local c = bit.band(msw, 0xFFFF)
  local d = bit.rshift(bit.band(msw, 0xFFFF0000), 16)
  return {
    kind = 'struct',
    offset = b,
    datasize = c,
    pointersize = d,
  }
end

function unpackListPointer(lsw, msw)
  local b = bit.arshift(bit.band(lsw, 0xFFFFFFFC), 2)
  local c = bit.band(msw, 0x7)
  local d = bit.rshift(bit.band(msw, 0xFFFFFFF8), 3)

  return {
    kind = 'list',
    offset = b,
    elementsize = c,
    listsize = d,
  }
end

function unpackCapPointer(lsw, msw)
  assert(lsw == 3, "must be a cap pointer")
  return {
    kind = 'capability',
    capabilityindex = msw,
  }
end

-- Pack a pointer into a least significant word and most significant word
---@param pointer PointerInfo the pointer to pack
---@return number lsw, number msw
local function packPointer(pointer)
  if pointer.kind == "list" then
    return packListPointer(pointer)
  elseif pointer.kind == "struct" then
    return packStructPointer(pointer)
  elseif pointer.kind == "capability" then
    return packCapabilityPointer(pointer)
  elseif pointer.kind == "null" then
    return 0, 0
  end
  error("unhandled pointer kind " .. pointer.kind)
end

function packStructPointer(pointer)
  if pointer.datasize < 0 then
    error("data size must be positive")
  end
  if pointer.datasize > 0xFFFF then
    error("data size must be less than 0xFFFF")
  end
  if pointer.pointersize < 0 then
    error("pointer size must be positive")
  end
  if pointer.pointersize > 0xFFFF then
    error("pointer size must be less than or equal to 0xFFFF")
  end
  -- Offset is 30 bits, signed
  if pointer.offset < -0x40000000 then
    error("offset must be greater than or equal to -0x40000000")
  end
  if pointer.offset > 0x3FFFFFFF then
    error("offset must be less than or equal to 0x3FFFFFFF")
  end
  local lsw = bit.lshift(pointer.offset, 2)
  local msw = bit.bor(pointer.datasize, bit.lshift(pointer.pointersize, 16))
  return lsw, msw
end

function packListPointer(pointer)
  if pointer.listsize < 0 then
    error("list size must be positive")
  end
  if pointer.listsize > 0x1FFFFFFF then
    error("list size must be less than or equal to 0x1FFFFFFF")
  end
  if pointer.elementsize < 0 then
    error("element size must be positive")
  end
  if pointer.elementsize > 0x7 then
    error("element size must be less than or equal to 0x7")
  end
  -- Offset is 30 bits, signed
  if pointer.offset < -0x40000000 then
    error("offset must be greater than or equal to -0x40000000")
  end
  if pointer.offset > 0x3FFFFFFF then
    error("offset must be less than or equal to 0x3FFFFFFF")
  end
  local lsw = bit.bor(1, bit.lshift(pointer.offset, 2))
  local msw = bit.bor(pointer.elementsize, bit.lshift(pointer.listsize, 3))
  return lsw, msw
end

function packCapabilityPointer(pointer)
  return 3, pointer.capabilityindex
end

return {
  packPointer = packPointer,
  unpackPointer = unpackPointer,
}

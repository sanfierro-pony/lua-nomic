-- future ptr types
-- hashed array mapped trie
-- vtable

-- local pointerkinds = {
--   [0] = "struct",
--   [1] = "list",
--   [2] = "reserved", -- reserved for future uses
--   [3] = "other", -- caps if lsw all zeroes except kind, else vtable (future use)
-- }

local bit = _G['bit'] or _G['bit32'] or require 'primitives.polyfill.bit'

local unpackStructPointer, unpackListPointer, unpackCapPointer
local packStructPointer, packListPointer, packCapabilityPointer

local function unpackPointer(lsw, msw)
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
  local b = bit.rshift(bit.band(lsw, 0xFFFFFFFC), 2)
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
  local b = bit.rshift(bit.band(lsw, 0xFFFFFFFC), 2)
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
  local lsw = bit.lshift(pointer.offset, 2)
  local msw = bit.bor(pointer.datasize, bit.lshift(pointer.pointersize, 16))
  return lsw, msw
end

function packListPointer(pointer)
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

local success, bit, bxor, ffi
success, bit  = pcall(require, "bit")
bit = success and bit or require "primitives/polyfill/bit"
bxor = bit.bxor
success, ffi = pcall(require, "ffi")
ffi = success and ffi or nil

local bint64 = (require "bint")(64)
local pointers = require "primitives/primitives-pointer"
local band = bit and bit.band

local stringBuffer = require "primitives/string-buffer"

-- if we have math.type we have a lua that has separate int and float types
-- if type(large int) is 'integer' then we have at least 64 bit int
-- if it's 'float' we don't
local hasInt64 = math.type and math.type(922337203685480000) == 'integer' or false

local WORD_SIZE_BYTES = 8


local function toHex(str)
  return (str:gsub(".", function(char) return string.format("%02x", char:byte()) end))
end

local function xorDefault(buf, offset, defaultBuf)
  local bufPart = stringBuffer.createStringBuffer()
  for i = 1, #defaultBuf do
    local first, second = string.byte(buf:sub(offset + i - 1, offset + i - 1)), string.byte(defaultBuf:sub(i, i))
    bufPart:append(string.char(bxor(first, second)))
  end
  return bufPart:toString()
end

-- Read a value from `buf`, xor'ing with `defaultBuf` to retrieve the original value buffer.
---@param buf string the buffer to read from
---@param offset integer the offset into the buffer to start at
---@param length integer the length of the value buffer
---@param defaultBuf string|nil the default value buffer
local function readValue(buf, offset, length, defaultBuf)
  if defaultBuf == nil then
    return string.sub(buf, offset, offset + length - 1)
  end
  return xorDefault(buf, offset, defaultBuf)
end

-- Append the value given in `valBuf` to `buf`, xor'd with `defaultBuf`
---@param buf StringBuffer buffer to append to
---@param valBuf string value to append
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
---@param defaultBuf string|nil buffer with default value for this field
local function appendValueXorDefault(buf, valBuf, reservation, defaultBuf)
  if defaultBuf ~= nil then
    valBuf = xorDefault(valBuf, 1, defaultBuf)
  end
  if reservation ~= nil then
    buf:fill(reservation, valBuf)
  else
    buf:append(valBuf)
  end
end

local function checkFieldIsWithinStruct(structLength, fieldOffset, numBytes)
  if fieldOffset * numBytes >= structLength then
    -- entirely outside
    return false
  end
  if (fieldOffset + 1) * numBytes > structLength then
    -- partially outside
    error("field is partially outside struct, probably wrong" .. structLength .. " " .. fieldOffset .. " " .. numBytes)
  end
  return true
end

---@param numBytes integer byte width of int type
---@param signed boolean whether int is signed or unsigned
---@param buf string buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function readLuaInt(numBytes, signed, buf, structOffset, structLength, fieldOffset, defaultBuf)
  -- pile of preconditions
  if numBytes > (hasInt64 and 8 or 4) then
    error("readLuaInt: numBytes must be <= lua int size to fit in lua int")
  end
  structOffset, structLength = structOffset * WORD_SIZE_BYTES, structLength * WORD_SIZE_BYTES

  local val, _
  local unpackFmt = '<' .. (signed and 'i' or 'I') .. tostring(numBytes)
  if not checkFieldIsWithinStruct(structLength, fieldOffset, numBytes) then
    -- entirely outside the range so load the default
    if defaultBuf == nil then
      return 0
    end
    val, _ = string.unpack(unpackFmt, defaultBuf)
    return val
  end
  local bufPart = readValue(buf, structOffset + fieldOffset * numBytes + 1, numBytes, defaultBuf)
  val, _ = string.unpack(unpackFmt, bufPart)
  return val
end

---@param numBytes integer byte width of int type
---@param signed boolean whether int is signed or unsigned
---@param val integer value to append
---@param buf StringBuffer buffer to append to
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function packLuaInt(numBytes, signed, val, buf, reservation, defaultBuf)
  if type(val) ~= 'number' then
    error("packLuaInt: val must be a number")
  end
  local result = string.pack("<" .. (signed and 'i' or 'I') .. tostring(numBytes), val)
  appendValueXorDefault(buf, result, reservation, defaultBuf)
end

-- Read a series of bools from a single u8
---@param buf string buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param default integer packed default of all bools in this u8
local function readBools(buf, structOffset, structLength, fieldOffset, default)
  local val = readLuaInt(1, false, buf, structOffset, structLength, fieldOffset, string.char(default))
  local result = {}
  for i = 0, 7 do
    result[i + 1] = band(val, (2 ^ i)) ~= 0
  end
  return result
end

-- Write a series of bools to a single u8
---@param bools boolean[] array of bools to append
---@param buf StringBuffer buffer to append to
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
---@param default integer packed default of all bools in this u8
local function packBools(bools, buf, reservation, default)
  local val = 0
  for i = 1, #bools do
    if bools[i] then
      val = val + (2 ^ (i - 1))
    end
  end
  packLuaInt(1, false, val, buf, reservation, string.char(default))
end

---@param isDouble boolean true if double, false if float
---@param buf string buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function readFp(isDouble, buf, structOffset, structLength, fieldOffset, defaultBuf)
  local numBytes = isDouble and 8 or 4
  structOffset, structLength = structOffset * WORD_SIZE_BYTES, structLength * WORD_SIZE_BYTES
  local val, _
  local unpackFmt = isDouble and 'd' or 'f'
  if not checkFieldIsWithinStruct(structLength, fieldOffset, numBytes) then
    -- entirely outside the range so load the default
    if defaultBuf == nil then
      return 0
    end
    val, _ = string.unpack(unpackFmt, defaultBuf)
    return val
  end
  local bufPart = readValue(buf, structOffset + fieldOffset * numBytes + 1, numBytes, defaultBuf)
  val, _ = string.unpack(unpackFmt, bufPart)
  return val
end

---@param isDouble boolean true if double, false if float
---@param val number value to append
---@param buf StringBuffer buffer to append to
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function packFp(isDouble, val, buf, reservation, defaultBuf)
  if type(val) ~= 'number' then
    error("packFp: val must be a number")
  end
  local result = string.pack("<" .. (isDouble and 'd' or 'f'), val)
  appendValueXorDefault(buf, result, reservation, defaultBuf)
end

local function partsToBigInt64(lsw, msw)
  local result = bint64.new(msw)
  result = bint64.__shl(result, 32)
  result = result + lsw
  return result
end

local function bigInt64ToParts(val)
  local lsw = bint64.touinteger(bint64.__band(val, 0xFFFFFFFF))
  local msw = bint64.touinteger(bint64.__shr(val, 32))
  return lsw, msw
end

---@param signed boolean whether int is signed or unsigned
---@param buf string buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function readBigInt64(signed, buf, structOffset, structLength, fieldOffset, defaultBuf)
  structOffset, structLength = structOffset * WORD_SIZE_BYTES, structLength * WORD_SIZE_BYTES
  -- pile of preconditions
  local first, second, _
  local numBytes = 8
  local unpackFmt = "<I4" .. (signed and 'i' or 'I') .. "4"
  if not checkFieldIsWithinStruct(structLength, fieldOffset, numBytes) then
    -- entirely outside the range so load the default
    if defaultBuf == nil then
      return 0
    end
    first, second, _ = string.unpack(unpackFmt, defaultBuf)
    return partsToBigInt64(first, second)
  end
  local bufPart = readValue(buf, structOffset + fieldOffset * numBytes + 1, numBytes, defaultBuf)
  first, second, _ = string.unpack(unpackFmt, bufPart)
  return partsToBigInt64(first, second)
end

---@param signed boolean whether int is signed or unsigned
---@param val integer value to append
---@param buf StringBuffer buffer to append to
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function packBigInt64(signed, val, buf, reservation, defaultBuf)
  -- FIXME: bint64 doesn't have an unsigned version
  if type(val) ~= 'number' and not bint64.isbint(val) then
    error("packBigInt64: val must be a number or bint64, got " .. type(val))
  end
  local lsw, msw = bigInt64ToParts(val)
  local result = string.pack("<I4" .. (signed and 'i' or 'I') .. "4", lsw, msw)
  appendValueXorDefault(buf, result, reservation, defaultBuf)
end

---@param buf string buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
---@return number lsw, number msw
local function readPointer(buf, structOffset, structLength, fieldOffset, defaultBuf)
  local bigPointer = readBigInt64(false, buf, structOffset, structLength, fieldOffset, defaultBuf)
  return bigInt64ToParts(bigPointer)
end

---@param lsw number low 32 bits of pointer
---@param msw number high 32 bits of pointer
---@param buf StringBuffer buffer to append to
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
---@param defaultBuf string|nil buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function packPointer(lsw, msw, buf, reservation, defaultBuf)
  packBigInt64(false, partsToBigInt64(lsw, msw), buf, reservation, defaultBuf)
end

---@param amount number bytes of padding to append
---@param buf StringBuffer buffer to append to
local function packPadding(amount, buf)
  buf:append(string.rep("\0", amount))
end

---@param buf string buffer we're decoding from
---@param offset integer offset into buf
---@param length integer length of bytes to read
---@return string
local function readBytes(buf, offset, length)
  local realOffset = offset * WORD_SIZE_BYTES
  return string.sub(buf, realOffset + 1, realOffset + length)
end

---@param bytes string bytes to append
---@param buf StringBuffer buffer to append to
---@param reservation SlotReservation|nil reservation in buffer for this field, if any
local function packBytes(bytes, buf, reservation)
  if reservation ~= nil then
    buf:fill(reservation, bytes)
  else
    buf:append(bytes)
  end
end

local primitives = {
  createBuffer = stringBuffer.createStringBuffer,

  readBools = readBools,
  readi8 = function(...) return readLuaInt(1, true, ...) end,
  readu8 = function(...) return readLuaInt(1, false, ...) end,
  readi16 = function(...) return readLuaInt(2, true, ...) end,
  readu16 = function(...) return readLuaInt(2, false, ...) end,
  readi32 = function(...) return readLuaInt(4, true, ...) end,
  readu32 = function(...) return readLuaInt(4, false, ...) end,
  readi64 = function(...) return readBigInt64(true, ...) end,
  readu64 = function(...) return readBigInt64(false, ...) end,
  readPointer = readPointer,
  readBytes = readBytes,

  writeBools = packBools,
  writei8 = function(...) return packLuaInt(1, true, ...) end,
  writeu8 = function(...) return packLuaInt(1, false, ...) end,
  writei16 = function(...) return packLuaInt(2, true, ...) end,
  writeu16 = function(...) return packLuaInt(2, false, ...) end,
  writei32 = function(...) return packLuaInt(4, true, ...) end,
  writeu32 = function(...) return packLuaInt(4, false, ...) end,
  writei64 = function(...) return packBigInt64(true, ...) end,
  writeu64 = function(...) return packBigInt64(false, ...) end,
  writePointer = packPointer,
  writeBytes = packBytes,
  writePadding = packPadding,

  readFloat = function(...) return readFp(false, ...) end,
  readDouble = function(...) return readFp(true, ...) end,
  writeFloat = function(...) return packFp(false, ...) end,
  writeDouble = function(...) return packFp(true, ...) end,
}

-- FIXME: is there a lua property testing thing?
-- can we run this fast enough to exhaustively test the 32 bit types and lower survive roundtrips?
local function selfTest()
  local function eq(expected, actual)
    if expected == actual then
      return
    end
    local printer = require 'printer'
    error(printer.toPrettyString(expected) .. " != " .. printer.toPrettyString(actual))
  end

  local function arrayEq(expected, actual)
    if #expected ~= #actual then
      error("arrayEq: expected length " .. #expected .. " but got " .. #actual)
    end
    for i = 1, #expected do
      if expected[i] ~= actual[i] then
        local printer = require 'printer'
        error("arrayEq: expected " .. printer.toPrettyString(expected[i]) .. " but got " .. printer.toPrettyString(actual[i]))
      end
    end
  end

  eq(0, primitives.readi8("\0", 0, 1, 0, "\0"))
  eq(-1, primitives.readi8("\255", 0, 1, 0, "\0"))
  eq(-1, primitives.readi8("\0", 0, 1, 0, "\255"))
  eq(bint64.tobint(1), primitives.readu64("\1\0\0\0\0\0\0\0", 0, 1, 0, nil))
  arrayEq({false, false, false, false, false, false, false, false}, primitives.readBools("\0", 0, 1, 0, 0))
  arrayEq({true, false, false, false, false, false, false, false}, primitives.readBools("\1", 0, 1, 0, 0))
  arrayEq({false, false, false, false, false, false, false, false}, primitives.readBools("\1", 0, 1, 0, 1))
  eq(0, primitives.readFloat("\0\0\0\0", 0, 1, 0, nil))
  -- struct.pack("<f", 0.1234).hex() in python
  assert(math.abs(primitives.readFloat("\x24\xb9\xfc\x3d", 0, 1, 0, nil) - 0.1234) < 0.00001)
  assert(0 == primitives.readDouble("\0\0\0\0\0\0\0\0", 0, 1, 0, nil))
  assert(math.abs(primitives.readDouble("\xf3\x8e\x53\x74\x24\x97\xbf\x3f", 0, 1, 0, nil) - 0.1234) < 0.000000001)

  local buffer = primitives.createBuffer()
  primitives.writeFloat(0.1234, buffer, nil)
  assert("24b9fc3d" == toHex(buffer:toString()))

  buffer = primitives.createBuffer()
  primitives.writeDouble(0.1234, buffer, nil)
  assert("f38e53742497bf3f" == toHex(buffer:toString()))

  buffer = primitives.createBuffer()
  primitives.writeu8(123, buffer, nil)
  assert("7b" == toHex(buffer:toString()))

  buffer = primitives.createBuffer()
  primitives.writeu16(1234, buffer, nil)
  assert("d204" == toHex(buffer:toString()))

  buffer = primitives.createBuffer()
  primitives.writeu32(1234, buffer, nil)
  assert("d2040000" == toHex(buffer:toString()))

  buffer = primitives.createBuffer()
  primitives.writeu64(bint64.tobint(1234), buffer, nil)
  eq("d204000000000000", toHex(buffer:toString()))

  buffer = primitives.createBuffer()
  primitives.writei8(-128, buffer, nil)
  assert("80" == toHex(buffer:toString()))

  local bigInt = partsToBigInt64(0, 65537)
  local lsw, msw = bigInt64ToParts(bigInt)
  eq(0, lsw)
  eq(65537, msw)
end

selfTest()

return primitives

local success, bit, bxor, ffi, bint64
success, bit  = pcall(require, "bit")
bit = success and bit or require "primitives.polyfill.bit"
bxor = bit.bxor
success, ffi = pcall(require, "ffi")
ffi = success and ffi or nil

success, bint64 = pcall(require, "bint")
bint64 = success and bint64(64) or nil

local pow = math.pow or require "primitives.polyfill.math_pow"
local pointers = require "primitives.primitives-pointer"
local band = bit and bit.band

-- if we have math.type we have a lua that has separate int and float types
-- if type(large int) is 'integer' then we have at least 64 bit int
-- if it's 'float' we don't
local hasInt64 = math.type and math.type(922337203685480000) == 'integer' or false

local WORD_SIZE_BYTES = 8


local function toHex(str)
  return (str:gsub(".", function(char) return string.format("%02x", char:byte()) end))
end


local function xorBufPart(buf, offset, length, defaultBuf)
  if defaultBuf == nil then
    return  string.sub(buf, offset, offset + length - 1)
  end
  local bufPart = ""
  for i = 1, #defaultBuf do
    local first, second = string.byte(buf:sub(offset + i - 1, offset + i - 1)), string.byte(defaultBuf:sub(i, i))
    bufPart = bufPart .. string.char(bxor(first, second))
  end
  return bufPart
end

local function readPointer(buf, pointerOffset)
  local lsw, msw, _ = string.unpack("<I2", buf:sub(pointerOffset + 1, pointerOffset + 1 + 8))
  return pointers.readPointer(lsw, msw)
end

-- this function is special and takes offset and length in bits
local function readBool(buf, structOffset, structLength, fieldOffset, default)
  structOffset, structLength = structOffset * WORD_SIZE_BYTES, structLength * WORD_SIZE_BYTES
  local start = math.floor(fieldOffset / 8)
  if start >= structLength then
    error("readBool: fieldOffset > structLength")
  end
  local val, _ = string.unpack("<I1", buf:sub(structOffset + start + 1, structOffset + start + 1))
  val = band(val, pow(2, fieldOffset % 8))
  val = val ~= 0
  if default then
    val = not val
  end
  return val
end

-- Not used - codegen is responsible for this as it gets fiddly otherwise as
-- there are multiple bools per byte
-- function packBool()

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

-- numBytes = byte width of int type
-- signed = whether int is signed or unsigned
-- buf = buffer we're decoding from (as lua string)
-- structOffset - offset into buf struct starts at (64bit aligned)
-- structLength - length of struct (64bit aligned)
-- (offset and length = capnproto pointer which is both ptr + length?)
-- defaultBuf = buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
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
  local bufPart = xorBufPart(buf, structOffset + fieldOffset * numBytes + 1, numBytes, defaultBuf)
  val, _ = string.unpack(unpackFmt, bufPart)
  return val
end

local function packLuaInt(numBytes, val, signed, defaultBuf)
  if type(val) ~= 'number' then
    error("packLuaInt: val must be a number")
  end
  local result = string.pack("<" .. (signed and 'i' or 'I') .. tostring(numBytes), val)
  return xorBufPart(result, 1, numBytes, defaultBuf)
end

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
  local bufPart = xorBufPart(buf, structOffset + fieldOffset * numBytes + 1, numBytes, defaultBuf)
  val, _ = string.unpack(unpackFmt, bufPart)
  return val
end

local function packFp(isDouble, val, defaultBuf)
  if type(val) ~= 'number' then
    error("packFp: val must be a number")
  end
  local result = string.pack("<" .. (isDouble and 'd' or 'f'), val)
  return xorBufPart(result, 1, (isDouble and 8 or 4), defaultBuf)
end

local function partsToBigInt64(_signed, lsw, msw)
  local result = bint64.new(msw)
  result = bint64.__shl(result, 32)
  result = result + lsw
  -- TODO: do something about signedness? would need to specialize a signed and unsigned bint
  -- type so tostring and some other ops default to right thing
  return result
end

local function bigInt64ToParts(val)
  return val[1], val[2]
  -- lsw = bint64.__shr(val, 32)
  -- msw = bint64.sub(val, right)
  -- return bint64.tointeger(lsw), bint64.tointeger(msw)
end

-- signed = whether int is signed or unsigned
-- buf = buffer we're decoding from (as lua string)
-- structOffset - beginning of struct in buf (* WORD_SIZE for bytes)
-- structLength - length of struct in buf (* WORD_SIZE for bytes)
-- fieldOffset - offset of field in struct, in field's alignment
-- defaultBuf = buffer with default value for this field (can pass nil instead of all zeroes if default is zeroes)
local function readBigInt64(signed, buf, structOffset, structLength, fieldOffset, defaultBuf)
  structOffset, structLength = structOffset * WORD_SIZE_BYTES, structLength * WORD_SIZE_BYTES
  -- pile of preconditions
  local first, second, _
  local numBytes = 8
  local unpackFmt = "<" .. "I4I4"
  if not checkFieldIsWithinStruct(structLength, fieldOffset, numBytes) then
    -- entirely outside the range so load the default
    if defaultBuf == nil then
      return 0
    end
    first, second, _ = string.unpack(unpackFmt, defaultBuf)
    return partsToBigInt64(signed, first, second)
  end
  local bufPart = xorBufPart(buf, structOffset + fieldOffset * numBytes + 1, numBytes, defaultBuf)
  first, second, _ = string.unpack(unpackFmt, bufPart)
  return partsToBigInt64(signed, first, second)
end

local ffi_ll = ffi and ffi.typeof("int64_t *")
local ffi_ull = ffi and ffi.typeof("uint64_t *")
local ffi_const_str = ffi and ffi.typeof("const char *")
local ffi_temp_buf = ffi and ffi.new("uint64_t[?]", 1)

local function readLongLong(signed, buf, structOffset, structLength, fieldOffset, defaultBuf)
  structOffset, structLength = structOffset * WORD_SIZE_BYTES, structLength * WORD_SIZE_BYTES
  -- pile of preconditions
  local numBytes = 8
  if not checkFieldIsWithinStruct(structLength, fieldOffset, numBytes) then
    buf, defaultBuf = defaultBuf, nil
    fieldOffset, structOffset = 0, 0
  end

  buf = ffi.cast(ffi_const_str, buf)

  if defaultBuf ~= nil then
    local tmpBuf = ffi.cast("char *", ffi_temp_buf)
    for i = 0,7 do
      tmpBuf[i] = bxor(buf[i], defaultBuf[i])
    end
    buf = tmpBuf
  end

  buf = ffi.cast(signed and ffi_ll or ffi_ull, buf + structOffset)
  return buf[fieldOffset]
end

local function packLongLong(val, signed, defaultBuf)
  local buf = ffi.cast(signed and ffi_ll or ffi_ull, ffi_temp_buf)
  buf[0] = val
  if defaultBuf ~= nil then
    for i=0,7 do
      buf[i] = bxor(buf[i], defaultBuf[i])
    end
  end
  return ffi.string(buf, 8)
end

local function packBigInt64(val, _signed, defaultBuf)
  -- FIXME: bint64 doesn't have an unsigned version
  if type(val) ~= 'number' and getmetatable(val) ~= bint64 then
    error("packBigInt64: val must be a number or bint64, got", type(val))
  end
  local lsw, msw = bigInt64ToParts(val)
  local result = string.pack("<I4I4", lsw, msw)
  return xorBufPart(result, 1, 8, defaultBuf)
end

local primitives = {
  readbool = readBool,
  readi8 = function(...) return readLuaInt(1, true, ...) end,
  readu8 = function(...) return readLuaInt(1, false, ...) end,
  readi16 = function(...) return readLuaInt(2, true, ...) end,
  readu16 = function(...) return readLuaInt(2, false, ...) end,
  readi32 = function(...) return readLuaInt(4, true, ...) end,
  readu32 = function(...) return readLuaInt(4, false, ...) end,
  readi64 = function(...) return readLuaInt(8, true, ...) end,
  readu64 = function(...) return readLuaInt(8, false, ...) end,

  packbool = packBool,
  packi8 = function(...) return packLuaInt(1, true, ...) end,
  packu8 = function(...) return packLuaInt(1, false, ...) end,
  packi16 = function(...) return packLuaInt(2, true, ...) end,
  packu16 = function(...) return packLuaInt(2, false, ...) end,
  packi32 = function(...) return packLuaInt(4, true, ...) end,
  packu32 = function(...) return packLuaInt(4, false, ...) end,
  packi64 = function(...) return packLuaInt(8, true, ...) end,
  packu64 = function(...) return packLuaInt(8, false, ...) end,

  readBool = readBool,
  readInt8 = function(...) return readLuaInt(1, ...) end,
  readInt16 = function(...) return readLuaInt(2, ...) end,
  readInt32 = function(...) return readLuaInt(4, ...) end,
  readInt64 = ffi and readLongLong or (hasInt64 and function(...) return readLuaInt(8, ...) end or readBigInt64),
  packInt8 = function(...) return packLuaInt(1, ...) end,
  packInt16 = function(...) return packLuaInt(2, ...) end,
  packInt32 = function(...) return packLuaInt(4, ...) end,
  packInt64 = ffi and packLongLong or (hasInt64 and function(...) return packLuaInt(8, ...) end or packBigInt64),
  readFloat = function(...) return readFp(false, ...) end,
  readDouble = function(...) return readFp(true, ...) end,
  packFloat = function(...) return packFp(false, ...) end,
  packDouble = function(...) return packFp(true, ...) end,
}

-- FIXME: is there a lua property testing thing?
-- can we run this fast enough to exhaustively test the 32 bit types and lower survive roundtrips?
local function selfTest()
  local function eq(expected, actual)
    assert(expected == actual, tostring(expected) .. "!=" .. tostring(actual))
  end

  eq(0, primitives.readInt8(true, "\0", 0, 1, 0, "\0"))
  eq(-1, primitives.readInt8(true, "\255", 0, 1, 0, "\0"))
  eq(-1, primitives.readInt8(true, "\0", 0, 1, 0, "\255"))
  eq(1, primitives.readInt64(false, "\1\0\0\0\0\0\0\0", 0, 1, 0, nil))
  eq(true, primitives.readBool("\1", 0, 1, 0, false))
  assert(false == primitives.readBool("\1", 0, 1, 0, true))
  assert(0 == primitives.readFloat("\0\0\0\0", 0, 1, 0, nil))
  -- struct.pack("<f", 0.1234).hex() in python
  assert(math.abs(primitives.readFloat("\x24\xb9\xfc\x3d", 0, 1, 0, nil) - 0.1234) < 0.00001)
  assert(0 == primitives.readDouble("\0\0\0\0\0\0\0\0", 0, 1, 0, nil))
  assert(math.abs(primitives.readDouble("\xf3\x8e\x53\x74\x24\x97\xbf\x3f", 0, 1, 0, nil) - 0.1234) < 0.000000001)

  assert("24b9fc3d" == toHex(packFp(false, 0.1234, nil)))
  assert("f38e53742497bf3f" == toHex(packFp(true, 0.1234, nil)))
  assert("7b" == toHex(packLuaInt(1, 123, true, nil)))
  assert("d204" == toHex(packLuaInt(2, 1234, true, nil)))
  assert("d2040000" == toHex(packLuaInt(4, 1234, true, nil)))
  eq("d204000000000000", toHex(primitives.packInt64(1234, false, nil)))
  assert("80" == toHex(packLuaInt(1, -128, true, nil)))
end

selfTest()

return primitives

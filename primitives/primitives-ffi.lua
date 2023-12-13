local ffi = require"ffi"
local bit = require"bit"
local typeof = ffi.typeof

local WORD_SIZE = 8
assert(ffi.abi("le") == true)
assert(ffi.sizeof("float") == 4)
assert(ffi.sizeof("double") == 8)

local int8    = typeof("int8_t *")
local int16   = typeof("int16_t *")
local int32   = typeof("int32_t *")
local int64   = typeof("int64_t *")
local uint8   = typeof("uint8_t *")
local uint16  = typeof("uint16_t *")
local uint32  = typeof("uint32_t *")
local uint64  = typeof("uint64_t *")
local float32 = typeof("float *")
local float64 = typeof("double *")
local charbuf = typeof("const char *")

local xorBuf = ffi.new("uint8_t[?]", 8)
local emptyBuf = ffi.new("uint8_t[?]", 8)

local tunpack = table.unpack or unpack

-- FIXME: when buf is a ctype buf we don't know the length -> need to add that for proper bounds checking

---@param ty ffi.ctype* type to read
---@param numBytes integer number of bytes to read
---@param buf string|ffi.cdata* buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param defaultXorBuf string|ffi.cdata*|nil default value to xor with
---@return number
local function readVal(ty, numBytes, buf, structOffset, structLength, fieldOffset, defaultXorBuf)
  if type(buf) == 'string' then
    buf = ffi.cast(charbuf, buf)
  end
  if type(defaultXorBuf) == 'string' then
    defaultXorBuf = ffi.cast(charbuf, defaultXorBuf)
  end

  structOffset, structLength = structOffset * WORD_SIZE, structLength * WORD_SIZE

  if fieldOffset >= structLength then
    -- entirely outside struct, use default only
    buf = defaultXorBuf or emptyBuf
    structOffset = 0
    fieldOffset = 0
  elseif (fieldOffset + 1) * numBytes > structLength then
    -- partially outside struct, fail
    error("readVal: end of field is outside struct")
  end

  local reader = ffi.cast(uint8, buf + structOffset + fieldOffset * numBytes)
  if defaultXorBuf ~= nil then
    for i = 0, numBytes -1 do
      xorBuf[i] = bit.bxor(defaultXorBuf[i], reader[i])
    end
    reader = ffi.cast(uint8, xorBuf)
  end
  -- for float* test for NaN tags that luajit will interpret as objects
  -- https://github.com/LuaJIT/LuaJIT/blob/d0e88930ddde28ff662503f9f20facf34f7265aa/src/lj_obj.h#L224-L259
  -- and convert to plain NaN / inf / -inf
  if ty == float64 or ty == float32 then
    if (reader[0] == 0xFF or reader[0] == 0x7F) and reader[1] > 0xF8 then
      if reader[1] == 0xF8 then
         local all_zero = true
         for i = 2, numBytes do
           if reader[i] ~= 0 then
             all_zero = false
             break
           end
         end
         if all_zero then
           return reader[0] == 0x7F and 1/0 or -1/0
         end
      end
      return 0 / 0
    end
  end
  reader = ffi.cast(ty, reader)
  return reader[0]
end

local function writeValToBuffer(writer, numBytes, val, defaultXorBuf)
  writer[0] = val
  if defaultXorBuf ~= nil then
    writer = ffi.cast(uint8, writer)
    for i = 0, numBytes - 1 do
      writer[i] = bit.bxor(writer[i], defaultXorBuf[i])
    end
  end
end

---@param ty ffi.ctype* type to write
---@param numBytes integer number of bytes to write
---@param val number value to write
---@param buf ByteBuffer buffer to write to
---@param reservation SliceReservation|nil reservation to write to
---@param defaultXorBuf string|ffi.cdata*|nil default value to xor with
local function writeVal(ty, numBytes, val, buf, reservation, defaultXorBuf)
  local slice
  if reservation ~= nil then
    slice = buf:fill(reservation)
  else
    slice = buf:write(numBytes)
  end
  writeValToBuffer(ffi.cast(ty, slice), numBytes, val, defaultXorBuf)
end

-- Read a series of bools from a single u8
---@param buf string|ffi.cdata* buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param default integer packed default of all bools in this u8
local function readBools(buf, structOffset, structLength, fieldOffset, default)
  local writer = ffi.cast(uint8, xorBuf)
  writer[0] = default
  local val = readVal(uint8, 1, buf, structOffset, structLength, fieldOffset, xorBuf)
  local result = {}
  for i = 0, 7 do
    result[i + 1] = bit.band(val, math.pow(2, i)) ~= 0
  end
  return tunpack(result)
end

-- Write a series of bools to a single u8
---@param bools boolean[] array of bools to append
---@param buf any buffer to append to
---@param reservation SliceReservation|nil reservation to write to
---@param default integer packed default of all bools in this u8
local function writeBools(bools, buf, reservation, default)
  if #bools > 8 then
    error("writeBools: expected up to 8 bools")
  end
  local val = 0
  for i = 1, #bools do
    if bools[i] then
      val = val + math.pow(2, i - 1)
    end
  end
  local writer = ffi.cast(uint8, xorBuf)
  writer[0] = default
  writeVal(uint8, 1, val, buf, reservation, xorBuf)
end

---@param buf string|ffi.cdata* buffer we're decoding from
---@param structOffset integer offset into buf struct starts at (64bit aligned)
---@param structLength integer length of struct (64bit aligned)
---@param fieldOffset integer (offset and length = capnproto pointer which is both ptr + length?)
---@param defaultXorBuf string|ffi.cdata*|nil default value to xor with
---@return number lsw, number msw
local function readPointer(buf, structOffset, structLength, fieldOffset, defaultXorBuf)
  local bigPointer = readVal(uint64, 8, buf, structOffset, structLength, fieldOffset, defaultXorBuf)
  return bit.band(bigPointer, 0xFFFFFFFF), bit.rshift(bigPointer, 32)
end

---@param lsw number low 32 bits of pointer
---@param msw number high 32 bits of pointer
---@param buf ByteBuffer buffer to write to
---@param reservation SliceReservation|nil reservation to write to
---@param defaultXorBuf string|ffi.cdata*|nil default value to xor with
local function writePointer(lsw, msw, buf, reservation, defaultXorBuf)
  local bigPointer = bit.bor(bit.lshift(msw + 0ULL, 32), bit.band(lsw, 0xFFFFFFFF))
  writeVal(uint64, 8, bigPointer, buf, reservation, defaultXorBuf)
end

---@param buf string|ffi.cdata* buffer we're decoding from
---@param offset number offset into buf
---@param length number length of bytes to read
---@return string
local function readBytes(buf, offset, length)
  if type(buf) == 'string' then
    buf = ffi.cast(charbuf, buf)
  end
  return ffi.string(buf + offset, length)
end

---@param bytes string bytes to write
---@param buf ByteBuffer buffer to write to
---@param reservation SliceReservation|nil reservation to write to
local function writeBytes(bytes, buf, reservation)
  local slice
  if reservation ~= nil then
    slice = buf:fill(reservation)
  else
    slice = buf:write(#bytes)
  end
  ffi.copy(slice, bytes, #bytes)
end

---@param existingLen number the byte length of the existing content, padding will be emitted to make this fit word alignment
---@param buf ByteBuffer buffer to write to
local function writePadding(existingLen, buf)
  local padding = (WORD_SIZE - (existingLen % WORD_SIZE)) % WORD_SIZE
  local slice = ffi.cast(uint8, buf:write(padding))
  for i = 1, padding do
    slice[i - 1] = 0
  end
end

local pffi = {
  createBuffer = require 'primitives.byte-buffer'.createByteBuffer,

  readBools = readBools,
  writeBools = writeBools,

  readi8 = function(...) return readVal(int8, 1, ...) end,
  writei8 = function(...) return writeVal(int8, 1, ...) end,
  readu8 = function(...) return readVal(uint8, 1, ...) end,
  writeu8 = function(...) return writeVal(uint8, 1, ...) end,

  readi16 = function(...) return readVal(int16, 2, ...) end,
  writei16 = function(...) return writeVal(int16, 2, ...) end,
  readu16 = function(...) return readVal(uint16, 2, ...) end,
  writeu16 = function(...) return writeVal(uint16, 2, ...) end,

  readi32 = function(...) return readVal(int32, 4, ...) end,
  writei32 = function(...) return writeVal(int32, 4, ...) end,
  readu32 = function(...) return readVal(uint32, 4, ...) end,
  writeu32 = function(...) return writeVal(uint32, 4, ...) end,

  readi64 = function(...) return readVal(int64, 8, ...) end,
  writei64 = function(...) return writeVal(int64, 8, ...) end,
  readu64 = function(...) return readVal(uint64, 8, ...) end,
  writeu64 = function(...) return writeVal(uint64, 8, ...) end,

  readPointer = readPointer,
  writePointer = writePointer,

  readBytes = readBytes,
  writeBytes = writeBytes,

  writePadding = writePadding,

  readFloat = function(...) return readVal(float32, 4, ...) end,
  writeFloat = function(...) return writeVal(float32, 4, ...) end,
  readDouble = function(...) return readVal(float64, 8, ...) end,
  writeDouble = function(...) return writeVal(float64, 8, ...) end,
}

local function isnan(a)
  return a ~= a
end

local function selfTest()
  local buf = ffi.new("uint8_t[?]", 8)
  buf[0] = 1
  buf[1] = 0
  buf[2] = 0
  buf[3] = 0
  assert(1 == pffi.readi8(buf, 0, 1, 0, nil))
  buf[0], buf[1], buf[2], buf[3] = 0x24, 0xb9, 0xfc, 0x3d
  assert(math.abs(pffi.readFloat(buf, 0, 1, 0, nil) - 0.1234) < 0.0000001)
  for i = 0, 7 do
    buf[i] = 0xFF
  end
  assert(isnan(pffi.readFloat(buf, 0, 1, 0, nil)))
  assert(isnan(pffi.readDouble(buf, 0, 1, 0, nil)))
end

selfTest()

return pffi

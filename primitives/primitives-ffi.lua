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
local charbuf = typeof("char *")

local xorBuf = ffi.new("uint8_t[?]", 8)
local emptyBuf = ffi.new("uint8_t[?]", 8)

-- FIXME: when buf is a ctype buf we don't know the length -> need to add that for proper bounds checking

local function readVal(ty, numBytes, buf, structOffset, structLength, fieldOffset, defaultXorBuf)
  if type(buf) == 'string' then
    buf = ffi.cast(charbuf, buf)
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

local function writeVal(ty, numBytes, val, buf, structOffset, structLength, fieldOffset, defaultXorBuf)
  structOffset, structLength = structOffset * WORD_SIZE, structLength * WORD_SIZE

  if fieldOffset >= structLength then
    -- entirely outside struct, fail
    error("writeVal: start of field is outside struct")
  end
  if (fieldOffset + 1) * numBytes > structLength then
    -- partially outside struct, fail
    error("writeVal: end of field is outside struct")
  end


  local writer = ffi.cast(ty, buf + structOffset + fieldOffset * numBytes)
  writer[0] = val
  if defaultXorBuf ~= nil then
    writer = ffi.cast(uint8, writer)
    for i = 0, numBytes - 1 do
      writer[i] = bit.bxor(writer[i], defaultXorBuf[i])
    end
  end
end

local function readbool(buf, structOffset, structLength, fieldOffset, defaultIsTrue)
  -- p("readBool:", buf, structOffset, structLength, fieldOffset, defaultIsTrue)
  local val = readVal(uint8, 1, buf, structOffset, structLength, math.floor(fieldOffset / 8))
  val = bit.band(val, math.pow(2, fieldOffset % 8)) ~= 0
  if defaultIsTrue then
    val = not val
  end
  return val
end

local pffi = {
  readbool = readbool,
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

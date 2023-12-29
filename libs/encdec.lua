local canffi, ffi = pcall(require, 'ffi')
ffi = canffi and ffi or nil
local primitives = canffi and require'primitives/primitives-ffi' or require'primitives/primitives'
local u64compat = require 'primitives/primitives-u64'
local tableutil = require('tableutil')

local codegen = require'codegen'
local schemaLayout = require'schema-layout'
local pointers = require'primitives/primitives-pointer'

local cg = codegen:new()

local schemaLayoutCache = {}
---@return StructLayout
local function layout(schema)
  local layout = schemaLayoutCache[schema]
  if not layout then
    layout = schemaLayout.layoutstruct(schema)
    schemaLayoutCache[schema] = layout
  end
  return layout
end

local schemaReaderCodegenCache = {}

---@return fun(buf: any, structoffset: number, datalength: number, ptrlength: number): any
local function reader(layout)
  local code = schemaReaderCodegenCache[layout]
  if not code then
    code = cg:structreader(layout)
    schemaReaderCodegenCache[layout] = code
  end
  return code
end

local schemaWriterCodegenCache = {}

---@return fun(val: any, buf: any)
local function writer(layout)
  local code = schemaWriterCodegenCache[layout]
  if not code then
    code = cg:structwriter(layout)
    schemaWriterCodegenCache[layout] = code
  end
  return code
end

-- Encode a struct to a string.
---@param schema table the schema to encode with
---@param struct table the struct to encode
---@return string
local function encode(schema, struct)
  local buf = primitives.createBuffer()
  local rootPointerReservation = buf:reserve(8)
  local structWriter = writer(layout(schema))
  local rootWriter = function(s, b)
    b:pushPointerQueue()
    local datasize, pointersize = structWriter(s, b)
    return {
      kind = "struct",
      offset = 0,
      datasize = datasize,
      pointersize = pointersize,
    }
  end
  local queue = buf:pushPointerQueue()
  queue:pushBack({
    key = { area = "struct[" .. u64compat.toHex(schema.id) .. "]", thing = struct },
    reservation = rootPointerReservation,
    writer = rootWriter,
  })
  while true do
    local nextQueue = buf:popPointerQueue()
    if nextQueue == nil then
      break
    end
    while true do
      ---@type DelayedPointerWrite?
      local next = nextQueue:popFront()
      if next == nil then
        break
      end
      local pointerInfo = buf:getPointer(next.key)
      if pointerInfo == nil then
        local byteOffset = buf:length()
        local newPointerInfo = next.writer(next.key.thing, buf)
        -- absolute offset for sharing
        newPointerInfo.offset = byteOffset / 8
        buf:addPointer(next.key, newPointerInfo)
        pointerInfo = tableutil.copy(newPointerInfo)
      end
      -- translate offset back using reservation, adding one to move to the word after the pointer
      pointerInfo.offset = pointerInfo.offset - (next.reservation.offset / 8 + 1)
      local lsw, msw = pointers.packPointer(pointerInfo)
      primitives.writePointer(lsw, msw, buf, next.reservation, next.default)
    end
  end
  return buf:toString()
end

-- Decode a struct from a string.
---@param schema table the schema to decode with
---@param buf string the string to decode
---@return table
local function decode(schema, buf)
  local reader = reader(layout(schema))
  local rootPointerLsw, rootPointerMsw = primitives.readPointer(buf, 0, 1, 0, nil)
  local rootPointer = pointers.unpackPointer(rootPointerLsw, rootPointerMsw)
  return reader(buf, 1 + rootPointer.offset, rootPointer.datasize, rootPointer.pointersize)
end

return {
  encode = encode,
  decode = decode,
}

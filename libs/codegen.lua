local acg = require 'abstract-codegen'
local schema = require 'schema'
local u64compat = require 'primitives/primitives-u64'
local tableutil = require 'tableutil'

local parser_gen = acg.generator {
   block = [[
return function (prims, ptrs, u64compat, cg, runtimedata)
  local function read_struct(buf, structoffset, datalength, ptrlength, path)
    local result = {}
    $(
    )fields
    local pointerInfo, pointerLsw, pointerMsw
    $(
    )pointers
    return result
  end
  return read_struct
end
]],
  field = "result.$fieldname = $readermethod(buf, structoffset, datalength, $fieldoffset, $default)",
  padding = "-- padding is skipped automatically",
  bools = [[
    $(, )boolfields = prims.readBools(buf, structoffset, datalength, $fieldoffset, $default)
  ]],
  boolfield = "result.$fieldname",
  variant = [[
    if result.$discriminatorname == "$discriminanttext" then
      $inner
    end
  ]],
  pointer = [[
    pointerLsw, pointerMsw = prims.readPointer(buf, structoffset, datalength + ptrlength, datalength + $fieldoffset, $default)
    pointerInfo = ptrs.unpackPointer(pointerLsw, pointerMsw)
    if pointerInfo.kind == "$pointerkind" then
      local offsetbase = structoffset + datalength + $fieldoffset + 1
      local value
      $pointertype
      result.$fieldname = value
    elseif pointerInfo.kind ~= "null" then
      error("pointer kind mismatch: expected $pointerkind, got " .. pointerInfo.kind)
    end
  ]],
  struct = [[
    value = $codec(
      buf, offsetbase + pointerInfo.offset, pointerInfo.datasize, pointerInfo.pointersize
    )
  ]],
  structcodec = 'cg.structreaderlazy(cg, u64compat"$id", runtimedata.layouts["$id"])',
  listgeneric = [[
    do
      value = {}
      local listoffset = offsetbase + pointerInfo.offset
      local listlength = cg.listlength(pointerInfo.elementsize, pointerInfo.listsize)
      for i=1, pointerInfo.listsize do
        value[i] = $readermethod(buf, listoffset, listlength, i - 1, nil)
      end
    end
  ]],
  listtext = [[
    do
      local listoffset = offsetbase + pointerInfo.offset
      value = prims.readBytes(buf, listoffset, pointerInfo.listsize)
    end
  ]],
  listbool = [[
    do
      value = {}
      local listoffset = offsetbase + pointerInfo.offset
      local listlength = cg.listlength(pointerInfo.elementsize, pointerInfo.listsize)
      for i=1, pointerInfo.listsize, 8 do
        local bools = prims.readBools(buf, listoffset, listlength, (i - 1) / 8, nil)
        for j=1, math.min(#bools, pointerInfo.listsize - i + 1) do
          value[i - 1 + j] = bools[j]
        end
      end
    end
  ]],
  liststruct = [[
    do
      if pointerInfo.elementsize ~= 7 then
        error("liststruct: expected elementsize 7 for $fieldname")
      end
      value = {}
      local listoffset = offsetbase + pointerInfo.offset
      local tagLsw, tagMsw = prims.readPointer(buf, listoffset, 1, 0, nil)
      local tag = ptrs.unpackPointer(tagLsw, tagMsw)
      for i=1, tag.offset do
        value[i] = $codec(
          buf, listoffset + 1 + (tag.datasize + tag.pointersize) * (i - 1), tag.datasize, tag.pointersize
        )
      end
    end
  ]]
}

local writer_gen = acg.generator {
   block = [[
return function (prims, ptrs, u64compat, cg, runtimedata)
  $(
)pointervalues

  local function write_struct(struct, buf)
    local start = buf:length()

    $(
    )fields
    local dataoffset = buf:length() / 8

    $pointerqueue
    $()pointers
    local pointeroffset = buf:length() / 8

    local datalength = dataoffset - start / 8
    local ptrlength = pointeroffset - dataoffset

    return datalength, ptrlength
  end
  return write_struct
end
]],
  field = "$writermethod(struct.$fieldname, buf, nil, $default)",
  padding = "prims.writePadding($filledbytecount, buf)",
  bools = [[
    prims.writeBools({ $(, )boolfields }, buf, nil, $default)
  ]],
  boolfield = "struct.$fieldname",
  variant = [[
    if struct.$discriminatorname == "$discriminanttext" then
        $inner
    end
]],
  pointer = [[
    if struct.$fieldname == nil then
      prims.writePointer(0, 0, buf, nil, $default)
    else
      pointerqueue:pushBack({
        key = { area = "$area", thing = struct.$fieldname },
        reservation = buf:reserve(8),
        writer = writepointer$idx,
        default = $default,
      })
    end
  ]],
  -- The code for writing the value of a pointer, if it is necessary
  pointervalue = [[
    local function writepointer$idx(value, buf, path)
      local pointerInfo = {
        kind = "$pointerkind"
      }

      local start = buf:length()
      $pointertype
      -- I'm not sure we actually need this, since structs should always be word-aligned...
      -- Lists might need it, but we can move it in to the list writer if so.
      prims.writePadding(buf:length() - start, buf)

      return pointerInfo
    end
  ]],
  struct = [[
    do
      buf:pushPointerQueue()
      local datasize, pointersize = $codec(value, buf)
      pointerInfo.datasize = datasize
      pointerInfo.pointersize = pointersize
    end
  ]],
  structcodec = 'cg.structwriterlazy(cg, u64compat"$id", runtimedata.layouts["$id"])',
  listgeneric = [[
    for _, v in ipairs(value) do
      $writermethod(v, buf, nil, nil)
    end
    pointerInfo.elementsize = $elementsize
    pointerInfo.listsize = #value
  ]],
  listbool = [[
    do
      local tempbools = {}
      for i=1, #value, 8 do
        local max = math.min(#value - i, 7)
        for j=0, max do
          tempbools[j + 1] = value[i + j]
        end
        if max < 7 then
          for j=max + 1, 7 do
            tempbools[j + 1] = nil
          end
        end
        prims.writeBools(tempbools, buf, nil, nil)
      end

      pointerInfo.elementsize = 1
      pointerInfo.listsize = #value
    end
  ]],
  listtext = [[
    prims.writeBytes(value, buf, nil)
    prims.writeBytes("\0", buf, nil)
    pointerInfo.elementsize = 2
    pointerInfo.listsize = #value
  ]],
  liststruct = [[
    do
      local tag = buf:reserve(8)
      local fieldstart = buf:length()

      buf:pushPointerQueue()
      local datasize = nil
      local pointersize = nil
      for _, v in ipairs(value) do
        local vdatasize, vpointersize = $codec(v, buf)
        if datasize == nil then
          datasize = vdatasize
          pointersize = vpointersize
        else
          if vdatasize ~= datasize then
            error("liststruct: inconsistent datasize")
          end
          if vpointersize ~= pointersize then
            error("liststruct: inconsistent pointersize")
          end
        end
      end
      if datasize == nil then
        datasize = 0
        pointersize = 0
      end

      local pointerLsw, pointerMsw = ptrs.packPointer({
        kind = "struct",
        offset = #value,
        datasize = datasize,
        pointersize = pointersize,
      })
      prims.writePointer(pointerLsw, pointerMsw, buf, tag, nil)

      pointerInfo.elementsize = 7
      pointerInfo.listsize = (buf:length() - fieldstart) / 8
    end
  ]]
}

local canffi, ffi = pcall(require, 'ffi')
ffi = canffi and ffi or nil
local primitives = canffi and require'primitives/primitives-ffi' or require'primitives/primitives'
local primtivesPointer = require'primitives/primitives-pointer'

---@alias StructReader fun(buf: any, structoffset: number, datalength: number, ptrlength: number): any
---@alias StructWriter fun(val: any, buf: any): number, number returns datalength, ptrlength

---@class codegen
---@field package structreaders table<string, StructReader>
---@field package structwriters table<string, StructWriter>
local codegen = {}

---@param cg codegen
---@param id U64 struct id
---@param layout fun(): StructLayout struct layout generator
---@return fun(buf: any): any
local function structreaderlazy(cg, id, layout)
  if cg.structreaders[id] then
    return cg.structreaders[id]
  end
  return cg:structreader(layout())
end

---@param cg codegen
---@param id U64 struct id
---@param layout fun(): StructLayout struct layout generator
---@return fun(val: any, buf: any)
local function structwriterlazy(cg, id, layout)
  if cg.structwriters[id] then
    return cg.structwriters[id]
  end
  if layout == nil then
    error("codegen:structwriterlazy: layout is nil for id " .. u64compat.toHex(id))
  end
  return cg:structwriter(layout())
end

local function listelementsizeToBytes(elementsize)
  if elementsize == 2 then
    return 1
  elseif elementsize == 3 then
    return 2
  elseif elementsize == 4 then
    return 4
  elseif elementsize == 5 then
    return 8
  else
    error("listelementsizeToBytes: invalid elementsize " .. tostring(elementsize))
  end
end

-- Compute the length of a list given the size of the elements and the number of elements.
-- Returns the length in words (8 bytes).
local function listlength(elementsize, listsize)
  local sizeInBytes = listelementsizeToBytes(elementsize) * listsize
  return math.floor((sizeInBytes + 7) / 8)
end

function codegen:new()
  return setmetatable({
      structreaders = {}, structwriters = {},
      structreaderlazy = structreaderlazy,
      structwriterlazy = structwriterlazy,
      listlength = listlength,
  }, {__index = codegen, __proxy_private = true})
end

local function codec(layout, fieldname, ty)
  if ty.kind == "primitive" then
    return {
      readermethod = "prims.read" .. ty.name,
      writermethod = "prims.write" .. ty.name,
      logbitwidth = ty.logbitwidth,
    }
  end
  if ty.kind == "enum" then
    -- discriminator is initially read as u16 and converted to friendly name if one matches
    local idstr = u64compat.toHex(ty.id)
    return {
      readermethod = string.format("runtimedata.readenum[%q]", idstr),
      writermethod = string.format("runtimedata.writeenum[%q]", idstr),
      logbitwidth = 4,
    }
  end
  if ty.kind == "newtype" then
    return codec(layout, fieldname, ty.basetype)
  end
  error("codegen:codec: not sure how to handle " .. ty.kind .. " for field " .. fieldname .. " of struct " .. layout.name)
end

local function setfieldinfo(layout, packed, field)
  local c = codec(layout, field.name, field.type)
  packed.readermethod = c.readermethod
  packed.writermethod = c.writermethod
  packed.fieldoffset = field.offset
  packed.default = field.default
  packed.fieldname = field.name
  return packed
end

local function structcodec(ty)
  return {
    kind = "structcodec",
    id = u64compat.toHex(ty.id),
  }
end

local function offset_in_bits(field)
  return field.offset * math.pow(2, field.logbitwidth)
end

-- Wrap an item in a variant check if necessary.
---@param fields table[] the fields in the layout area
---@param field table the field that the content is for
---@param content table the content to wrap if needed
---@return table the content, possibly wrapped
local function wrapvariant(fields, field, content)
  if field.discriminator then
    local discriminatorField = fields[field.discriminator]
    return wrapvariant(fields, discriminatorField, {
      kind = "variant",
      discriminatorname = discriminatorField.name,
      discriminanttext = discriminatorField.type.variants[field.discriminant + 1].name,
      inner = content,
    })
  else
    return content
  end
end

local function combine_boolfields(layout, boolfields)
  local parser_boolfields = {}
  for i, f in ipairs(boolfields) do
    -- sanity check that all fields are offset properly
    if f.offset ~= boolfields[1].offset + i - 1 then
      error("combine_boolfields: boolfields not contiguous")
    end
    parser_boolfields[#parser_boolfields + 1] = {
      kind = "boolfield",
      fieldname = f.name,
    }
  end
  local combined_default = 0
  for i, f in ipairs(boolfields) do
    combined_default = combined_default + (f.default or 0) * math.pow(2, i - 1)
  end
  return wrapvariant(layout.data, boolfields[1], setfieldinfo(layout, {
    kind = "bools",
    boolfields = parser_boolfields,
  }, {
    offset = boolfields[1].offset / 8,
    default = combined_default,
    type = schema.u8,
  }))
end

local function same_variant(a, b)
  return a.discriminator == b.discriminator and a.discriminant == b.discriminant
end

-- Handle adding a field to a given layout area.
---@param layout StructLayout the layout
---@param runtimedata table the runtimedata to add to
---@param fields table[] the fields in the layout area
---@param boolfields table[] the bool fields in the layout area
---@param field table the field to add
local function addfield(layout, runtimedata, fields, boolfields, field)
  local is_bool = field.logbitwidth == 0
  if not is_bool or #boolfields == 8 or (#boolfields > 0 and not same_variant(boolfields[#boolfields], field)) then
    -- convert bools collected to a single u8 field
    if #boolfields > 0 then
      fields[#fields + 1] = combine_boolfields(layout, boolfields)
      boolfields = {}
    end
  end
  if is_bool then
    boolfields[#boolfields + 1] = field
  else
    if field.kind == "padding" then
      fields[#fields + 1] = wrapvariant(layout.data, field, {
        kind = "padding",
        filledbytecount = 8 - math.pow(2, field.logbitwidth - 3),
      })
    else
      if field.type.kind == "enum" then
        local idstr = u64compat.toHex(field.type.id)
        runtimedata.readenum[idstr] = function(buf, structOffset, structLength, fieldOffset, defaultXorBuf)
          local fieldnum = primitives.readu16(buf, structOffset, structLength, fieldOffset, defaultXorBuf)
          local variant = field.type.variants[fieldnum + 1]
          if variant == nil then
            error("codegen:structtree: enum variant " .. fieldnum .. " not found for field '" .. field.name .. "'")
          end
          local value = field.type.variants[fieldnum + 1].name
          return value
        end
        runtimedata.writeenum[idstr] = function(variantname, buf, reservation, defaultXorBuf)
          local fieldnum = field.vindex[variantname]
          if fieldnum == nil then
            if variantname == nil then
              error("codegen:structtree: enum variant is nil for field '" .. field.name .. "'")
            else
              error("codegen:structtree: enum variant '" .. variantname .. "' not found for field '" .. field.name .. "'")
            end
          end
          return primitives.writeu16(fieldnum, buf, reservation, defaultXorBuf)
        end
      end
      local fieldInfo = setfieldinfo(layout, {kind = "field"}, field)
      fields[#fields + 1] = wrapvariant(layout.data, field, fieldInfo)
    end
  end
end

-- Handle finishing a layout area.
---@param layout StructLayout the layout
---@param fields table[] the fields in the layout area
---@param boolfields table[] the bool fields in the layout area
local function finishfields(layout, fields, boolfields)
  if #boolfields > 0 then
    fields[#fields + 1] = combine_boolfields(layout, boolfields)
    boolfields = {}
  end
end

-- Add a pointer to a layout area
---@param layout StructLayout the layout
---@param runtimedata table the runtimedata to add to
---@param pointers table[] the pointers in the layout area
---@param pointervalues table[] the pointervalues in the layout area
---@param pointer table the pointer to add
local function addpointer(layout, runtimedata, pointers, pointervalues, pointer)
  local i = #pointers + 1
  local area
  local pointertype
  local pointerkind = pointer.type.kind
  if pointer.type.kind == "struct" then
    area = "struct[" .. u64compat.toHex(pointer.type.id) .. "]"
    pointertype = {
      kind = "struct",
      codec = structcodec(pointer.type),
      fieldname = pointer.name,
    }
    runtimedata.layouts[u64compat.toHex(pointer.type.id)] = pointer.layout
  elseif pointer.type.kind == "generic" and pointer.type.basetype.kind == "list" then
    pointerkind = "list"
    local elementtype = pointer.type.args[1]
    if elementtype.kind == "struct" then
      area = "liststruct[" .. u64compat.toHex(elementtype.id) .. "]"
      pointertype = {
        kind = "liststruct",
        codec = structcodec(elementtype),
        fieldname = pointer.name,
      }
      runtimedata.layouts[u64compat.toHex(elementtype.id)] = pointer.layout
    elseif elementtype.kind == "primitive" and elementtype.name == "bool" then
      area = "listbool"
      pointertype = {
        kind = "listbool",
      }
    elseif elementtype.kind == "primitive" then
      area = "listgeneric"
      local c = codec(layout, pointer.name, elementtype)
      pointertype = {
        kind = "listgeneric",
        readermethod = c.readermethod,
        writermethod = c.writermethod,
        elementsize = c.logbitwidth - 1,
      }
    else
      error("codegen:structtree: element type not supported: " .. elementtype.kind)
    end
  elseif pointer.type == schema.text then
    area = "text"
    pointerkind = "list"
    pointertype = {
      kind = "listtext",
    }
  else
    error("codegen:structtree: pointer type not supported: " .. pointer.type.kind)
  end
  pointers[i] = wrapvariant(layout.data, pointer, {
    kind = "pointer",
    idx = i,
    fieldname = pointer.name,
    fieldoffset = pointer.offset,
    default = nil,
    area = area,
    pointerkind = pointerkind,
    pointertype = pointertype,
  })
  pointervalues[i] = {
    kind = "pointervalue",
    idx = i,
    pointerkind = pointerkind,
    pointertype = pointertype,
  }
end

---@param layout StructLayout
function codegen:structtree(layout)
  local fields = {}
  local enums = {}
  local runtimedata = {
    layouts = {},
    readenum = {},
    writeenum = {},
    vindex = {},
  }
  local boolfields = {}
  table.sort(layout.data, function(a, b)
    return offset_in_bits(a) < offset_in_bits(b)
  end)
  for _, field in ipairs(layout.data) do
    addfield(layout, runtimedata, fields, boolfields, field)
  end
  finishfields(layout, fields, boolfields)

  local pointers = {}
  local pointervalues = {}
  for i, pointer in ipairs(layout.pointers) do
    addpointer(layout, runtimedata, pointers, pointervalues, pointer)
  end

  local pointerqueue = ""
  if #pointervalues > 0 then
    pointerqueue = "local pointerqueue = buf:getPointerQueue()"
  end

  return {
    kind = "block",
    fields = fields,
    pointers = pointers,
    pointerqueue = pointerqueue,
    pointervalues = pointervalues,
  }, runtimedata
end

---@param layout StructLayout
---@return StructReader
function codegen:structreader(layout)
  if layout.id == nil then
    error("codegen:structreader: layout.id must be set")
  end
  if self.structreaders[layout.id] then
    return self.structreaders[layout.id]
  end
  local structtree, runtimedata = self:structtree(layout)
  local code = parser_gen(structtree)
  local result = assert(load(code, "codegen:structreader_"..layout.name.."_"..u64compat.toHex(layout.id)))()(
    primitives, primtivesPointer, u64compat, self, runtimedata
  )
  self.structreaders[layout.id] = result
  return result
end

---@param layout StructLayout
---@return StructWriter
function codegen:structwriter(layout)
  if layout.id == nil then
    error("codegen:structwriter: layout.id must be set")
  end
  if self.structwriters[layout.id] then
    return self.structwriters[layout.id]
  end
  local structtree, runtimedata = self:structtree(layout)
  local code = writer_gen(structtree)
  local result = assert(load(code, "codegen:structwriter_"..layout.name.."_"..u64compat.toHex(layout.id)))()(
    primitives, primtivesPointer, u64compat, self, runtimedata
  )
  self.structwriters[layout.id] = result
  return result
end

return codegen

local acg = require 'libs.abstract-codegen'
local schema = require 'schema'
local u64compat = require 'primitives.primitives-u64'
local printCode = require 'print-code'.printCode

local parser_gen = acg.generator {
   block = [[
return function (prims, ptrs, u64compat, cg, runtimedata)
  local function read_struct(buf, structoffset, datalength, ptrlength)
    local result = {}
    $(
    )fields
    local pointerInfo, pointerLsw, pointerMsw
    $(
    )pointervalues
    return result
  end
  return read_struct
end
]],
  field = "result.$fieldname = $readermethod(buf, structoffset, datalength, $fieldoffset, $default)",
  bools = [[
    $(, )boolfields = prims.readBools(buf, structoffset, datalength, $fieldoffset, $default)
  ]],
  boolfield = "result.$fieldname",
  union = [[
    local $fieldname = $readermethod(buf, structoffset, datalength, $fieldoffset, $default)
    $variants
    result.$fieldname = $fieldname
  ]],
  variants = [[
    $()variants
  end
]],
  variant = [[if $unionname == $discriminant then
$unionname = $name
    $(
)fields
else]],
  novariant = "if true then",
  -- No `pointer` here, since we don't need the separation between pointer and pointervalue.
  pointervalue = [[
    pointerLsw, pointerMsw = prims.readPointer(buf, structoffset, datalength + ptrlength, datalength + $fieldoffset, $default)
    pointerInfo = ptrs.unpackPointer(pointerLsw, pointerMsw)
    if pointerInfo.kind == "$pointerkind" then
      $pointertype
    else
      error("pointer kind mismatch")
    end
  ]],
  struct = [[
    result.$fieldname = $codec(
      buf, structoffset + datalength + $fieldoffset + 1 + pointerInfo.offset, pointerInfo.datasize, pointerInfo.pointersize
    )
  ]],
  structcodec = 'cg.structreaderlazy(cg, u64compat"$id", runtimedata.layouts["$id"])',
  listgeneric = [[
    do
      result.$fieldname = {}
      local listoffset = structoffset + datalength + $fieldoffset + 1 + pointerInfo.offset
      local listlength = cg.listlength(pointerInfo.elementsize, pointerInfo.listsize)
      for i=1, pointerInfo.listsize do
        result.$fieldname[i] = $readermethod(buf, listoffset, listlength, i - 1, nil)
      end
    end
  ]],
  listtext = [[
    do
      local listoffset = structoffset + datalength + $fieldoffset + 1 + pointerInfo.offset
      result.$fieldname = prims.readString(buf, listoffset, pointerInfo.listsize)
    end
  ]],
  listbool = [[
    do
      result.$fieldname = {}
      local listoffset = structoffset + datalength + $fieldoffset + 1 + pointerInfo.offset
      local listlength = cg.listlength(pointerInfo.elementsize, pointerInfo.listsize)
      for i=1, pointerInfo.listsize, 8 do
        local bools = prims.readBools(buf, listoffset, listlength, (i - 1) / 8, nil)
        for j=1, math.min(#bools, pointerInfo.listsize - i + 1) do
          result.$fieldname[i - 1 + j] = bools[j]
        end
      end
    end
  ]],
  liststruct = [[
    do
      if pointerInfo.elementsize ~= 7 then
        error("liststruct: expected elementsize 7 for $fieldname")
      end
      result.$fieldname = {}
      local listoffset = structoffset + datalength + $fieldoffset + 1 + pointerInfo.offset
      local tagLsw, tagMsw = prims.readPointer(buf, listoffset, 1, 0, nil)
      local tag = ptrs.unpackPointer(tagLsw, tagMsw)
      for i=1, tag.offset do
        result.$fieldname[i] = $codec(
          buf, listoffset + (tag.datasize + tag.pointersize) * (i - 1), tag.datasize, tag.pointersize
        )
      end
    end
  ]]
}

local writer_gen = acg.generator {
   block = [[
return function (prims, ptrs, u64compat, cg, runtimedata)
  local function write_struct(struct, buf)
    local start = buf:length()
    $(
    )fields

    local fieldlen = buf:length() - start
    prims.writePadding(fieldlen, buf)

    local dataoffset = buf:length() / 8
    local pointerInfo, pointerLsw, pointerMsw
    $()pointers
    local pointeroffset = buf:length() / 8
    $()pointervalues

    return dataoffset - start / 8, pointeroffset - dataoffset
  end
  return write_struct
end
]],
  field = "$writermethod(struct.$fieldname, buf, nil, $default)",
  bools = [[
    prims.writeBools({ $(, )boolfields }, buf, nil, $default)
  ]],
  boolfield = "struct.$fieldname",
  union = [[
    $writermethod(struct.$fieldname, buf, nil, $default)
    $variants
  ]],
  variants = [[
    $()variants
  end
]],
  variant = [[if struct.$unionname == $name then
    $(
)fields
else]],
  novariant = "if true then",
  pointer = [[
    local pointerReservation$idx = buf:reserve(8)
  ]],
  -- The code for writing the value of a pointer, if it is necessary, followed by filling in the pointer.
  pointervalue = [[
    if struct.$fieldname == nil then
      pointerInfo = {
        kind = "null"
      }
    else
      if buf.knownPointers[struct.$fieldname] then
        pointerInfo = buf.knownPointers[struct.$fieldname]
      else
        pointerInfo = {
          kind = "$pointerkind"
        }

        pointerInfo.byteOffset = buf:length()
        $pointertype
        prims.writePadding(buf:length() - pointerInfo.byteOffset, buf)

        buf.knownPointers[struct.$fieldname] = pointerInfo
      end
      pointerInfo.offset = (pointerInfo.byteOffset - pointerReservation$idx.offset) / 8
    end
    pointerLsw, pointerMsw = ptrs.packPointer(pointerInfo)
    prims.writePointer(pointerLsw, pointerMsw, buf, pointerReservation$idx, $default)
  ]],
  struct = [[
    local datasize, pointersize = $codec(struct.$fieldname, buf)
    pointerInfo.byteOffset = buf:length()
    pointerInfo.datasize = datasize
    pointerInfo.pointersize = pointersize
  ]],
  structcodec = 'cg.structwriterlazy(cg, u64compat"$id", runtimedata.layouts["$id"])',
  listgeneric = [[
    for _, v in ipairs(struct.$fieldname) do
      $writermethod(v, buf, nil, nil)
    end
    pointerInfo.elementsize = $elementsize
    pointerInfo.listsize = #struct.$fieldname
  ]],
  listbool = [[
    do
      local tempbools = {}
      for i=1, #struct.$fieldname, 8 do
        local max = math.min(#struct.$fieldname - i, 7)
        for j=0, max do
          tempbools[j + 1] = struct.$fieldname[i + j]
        end
        if max < 7 then
          for j=max + 1, 7 do
            tempbools[j + 1] = nil
          end
        end
        prims.writeBools(tempbools, buf, nil, nil)
      end

      pointerInfo.elementsize = 1
      pointerInfo.listsize = #struct.$fieldname
    end
  ]],
  listtext = [[
    prims.writeBytes(struct.$fieldname, buf, nil)
    prims.writeBytes("\0", buf, nil)
    pointerInfo.elementsize = 2
    pointerInfo.listsize = #struct.$fieldname
  ]],
  liststruct = [[
    do
      local tag = buf:reserve(8)
      local fieldstart = buf:length()
      local datasize = nil
      local pointersize = nil
      for _, v in ipairs(struct.$fieldname) do
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
        offset = #struct.$fieldname,
        datasize = datasize,
        pointersize = pointersize,
      })
      prims.writePointer(pointerLsw, pointerMsw, buf, tag, nil)

      pointerInfo.elementsize = 7
      pointerInfo.listsize = (pointerInfo.byteOffset - fieldstart) / 8
    end
  ]]
}

local canffi, ffi = pcall(require, 'ffi')
ffi = canffi and ffi or nil
local primitives = canffi and require'primitives.primitives-ffi' or require'primitives.primitives'
local primtivesPointer = require'primitives.primitives-pointer'

---@alias StructReader fun(buf: any, structoffset: number, datalength: number, ptrlength: number): any
---@alias StructWriter fun(val: any, buf: any): number, number returns datalength, ptrlength

---@class codegen
---@field package structreaders table<string, StructReader>
---@field package structwriters table<string, StructWriter>
local codegen = {}

---@param cg codegen
---@param id string struct id
---@param layout fun(): StructLayout struct layout generator
---@return fun(buf: any): any
local function structreaderlazy(cg, id, layout)
  if cg.structreaders[id] then
    return cg.structreaders[id]
  end
  return cg:structreader(layout())
end

---@param cg codegen
---@param id string struct id
---@param layout fun(): StructLayout struct layout generator
---@return fun(val: any, buf: any)
local function structwriterlazy(cg, id, layout)
  if cg.structwriters[id] then
    return cg.structwriters[id]
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
      bitwidthln = ty.bitwidthln,
    }
  end
  if ty.kind == "enum" then
    -- discriminator is initially read as u16 and converted to friendly name if one matches
    -- TODO: fix type id
    --local idstr = u64compat.toHex(ty.id)
    local idstr = ty.name
    return {
      readermethod = string.format("runtimedata.readenum[%q]", idstr),
      writermethod = string.format("runtimedata.writeenum[%q]", idstr),
      bitwidthln = 4,
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
  return field.offset * math.pow(2, field.lnbitwidth)
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
  return setfieldinfo(layout, {
    kind = "bools",
    boolfields = parser_boolfields,
  }, {
    offset = boolfields[1].offset / 8,
    default = combined_default,
    type = schema.u8,
  })
end

---@param layout StructLayout
function codegen:structtree(layout)
  local fields = {}
  local enums = {}
  local unionfields = {}
  local boolfields = {}
  table.sort(layout.data, function(a, b)
    return offset_in_bits(a) < offset_in_bits(b)
  end)
  for _, field in ipairs(layout.data) do
    local is_bool = field.lnbitwidth == 0
    if not is_bool or #boolfields == 8 then
      -- convert bools collected to a single u8 field
      if #boolfields > 0 then
        fields[#fields + 1] = combine_boolfields(layout, boolfields)
        boolfields = {}
      end
      if field.discriminator then
        local uf = unionfields[field.discriminator .. ':' .. field.discriminant]
        if not uf then
          uf = {}
          unionfields[field.discriminator .. ':' .. field.discriminant] = uf
        end
        uf[#uf + 1] = field
      elseif field.type.kind == "enum" then
        enums[#enums + 1] = field
      else
        fields[#fields + 1] = setfieldinfo(layout, {kind = "field"}, field)
      end
    else
      boolfields[#boolfields + 1] = field
    end
  end
  if #boolfields > 0 then
    fields[#fields + 1] = combine_boolfields(layout, boolfields)
    boolfields = {}
  end
  -- enum or union, if is used as discriminator will be unionfields entries matching
  local function buildenumfield(union)
    local variants = {}
    for _, tv in pairs(union.type.variants) do
      local uf = unionfields[union.offset .. ':' .. tv.variantindex]
      local fields = {}
      if uf then
        for _, field in ipairs(uf) do
          if field.type.kind == "enum" then
            fields[#fields + 1] = buildenumfield(field)
          else
            fields[#fields + 1] = setfieldinfo(layout, {kind = "field"}, field)
          end
        end
      end
      variants[#variants + 1] = {
        kind = "variant",
        discriminant = tv.variantindex,
        name = string.format("%q", tv.name),
        unionname = union.name,
        fields = fields,
      }
    end
    return setfieldinfo(
      layout,
      {
        kind = "union",
        variants = #variants > 0 and { kind = "variants", variants = variants } or "",
      }, union)
  end
  for i, union in ipairs(enums) do
    fields[#fields + 1] = buildenumfield(union)
  end

  local pointers = {}
  local pointervalues = {}
  local runtimedata = {
    layouts = {},
    readenum = {},
    writeenum = {},
  }

  for i, union in ipairs(enums) do
    -- TODO: fix type id
    --local idstr = u64compat.toHex(union.type.id)
    local idstr = union.type.name
    runtimedata.readenum[idstr] = function(buf, structOffset, structLength, fieldOffset, defaultXorBuf)
      return primitives.readu16(buf, structOffset, structLength, fieldOffset, defaultXorBuf)
    end
    runtimedata.writeenum[idstr] = function(fieldname, buf, reservation, defaultXorBuf)
      local fieldnum = union.vindex[fieldname]
      return primitives.writeu16(fieldnum, buf, reservation, defaultXorBuf)
    end
  end

  for i, pointer in ipairs(layout.pointers) do
    pointers[#pointers+1] = {
      kind = "pointer",
      idx = i,
    }
    local pointertype = {
      fieldname = pointer.name,
      fieldoffset = pointer.offset,
    }
    local pointerkind = pointer.type.kind
    if pointer.type.kind == "struct" then
      pointertype.kind = "struct"
      pointertype.codec = structcodec(pointer.type)
      runtimedata.layouts[u64compat.toHex(pointer.type.id)] = pointer.layout
    elseif pointer.type.kind == "list" then
      local elementtype = pointer.type.args[1]
      if elementtype.kind == "struct" then
        pointertype.kind = "liststruct"
        pointertype.codec = structcodec(elementtype)
        runtimedata.layouts[u64compat.toHex(elementtype.id)] = pointer.layout
      elseif elementtype.kind == "primitive" and elementtype.name == "bool" then
        pointertype.kind = "listbool"
        pointertype.elementsize = 1
      elseif elementtype.kind == "primitive" then
        pointertype.kind = "listgeneric"
        local c = codec(layout, pointer.name, elementtype)
        pointertype.readermethod = c.readermethod
        pointertype.writermethod = c.writermethod
        pointertype.elementsize = c.bitwidthln - 1
      else
        error("codegen:structtree: element type not supported: " .. elementtype.kind)
      end
    elseif pointer.type.kind == "text" then
      pointertype.kind = "listtext"
      pointerkind = "list"
    else
      error("codegen:structtree: pointer type not supported: " .. pointer.type.kind)
    end
    pointervalues[#pointervalues+1] = {
      kind = "pointervalue",
      pointerkind = pointerkind,
      idx = i,
      fieldname = pointer.name,
      fieldoffset = pointer.offset,
      default = nil,
      pointertype = pointertype,
    }
  end

  return {
    kind = "block",
    fields = fields,
    pointers = pointers,
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
  print("codegen:structreader_"..layout.name.."_"..tostring(layout.id))
  printCode(code)
  local result = assert(load(code, "codegen:structreader_"..layout.name.."_"..tostring(layout.id)))()(
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
  print("codegen:structreader_"..layout.name.."_"..tostring(layout.id))
  printCode(code)
  local result = assert(load(code, "codegen:structwriter_"..layout.name.."_"..tostring(layout.id)))()(
    primitives, primtivesPointer, u64compat, self, runtimedata
  )
  self.structwriters[layout.id] = result
  return result
end

return codegen

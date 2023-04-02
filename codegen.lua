local acg = require 'libs.abstract-codegen'

local parser_gen = acg.generator {
   block = [[
return function (prims)
  local function read_struct(buf, structoffset, datalength, ptrlength)
    local result = {}
    $(
    )fields
    return result
  end
  return read_struct
end
]],
  field = "result.$fieldname = $readermethod(buf, structoffset, datalength, $fieldoffset, $default)",
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
}

local canffi, ffi = pcall(require, 'ffi')
ffi = canffi and ffi or nil
local primitives = canffi and require'primitives.primitives-ffi' or require'primitives.primitives'

local codegen = {}

function codegen:new()
  return setmetatable({structreaders = {}}, {__index = codegen})
end

local function readermethod(ty)
  if ty.kind == "primitive" then
    return "prims.read" .. ty.name
  end
  if ty.kind == "enum" then
    -- discriminator is initially read as u16 and converted to friendly name if one matches
    return "prims.readu16"
  end
  error("not sure how to read " .. ty.kind)
end

local function setfieldinfo(packed, field)
  packed.readermethod = readermethod(field.type)
  packed.fieldoffset = field.offset
  packed.default = field.default
  packed.fieldname = field.name
  return packed
end

function codegen:structreader(layout)
  assert(layout.id ~= nil, "codegen:structreader: layout.id must be set")
  if self.structreaders[layout.id] then
    return self.structreaders[layout.id]
  end
  local fields = {}
  local enums = {}
  local unionfields = {}
  for _, field in ipairs(layout.data) do
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
      fields[#fields + 1] = setfieldinfo({kind = "field"}, field)
    end
  end
  p("unions", unionfields)
  local function buildfield(field)
      unionfields[field.discriminator] = uf
      currentfield = setfieldinfo({kind = "field"}, field)
      currentfield.discriminator, currentfield.discriminant = field.discriminator, field.discriminant
      currentfield.kind = "unionfield"
  end
  -- enum or union, if is used as discriminator will be unionfields entries matching
  local function buildenumfield(union)
    local variants = {}
    for _, tv in pairs(union.type.variants) do
      local uf = unionfields[union.offset .. ':' .. tv.variantindex]
      p(union.offset .. ':' .. tv.variantindex, uf)
      local fields = {}
      if uf then
        for _, field in ipairs(uf) do
          if field.type.kind == "enum" then
            fields[#fields + 1] = buildenumfield(field)
          else
            fields[#fields + 1] = setfieldinfo({kind = "field"}, field)
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
    p(variants)
    return setfieldinfo(
      {
        kind = "union",
        variants = #variants > 0 and { kind = "variants", variants = variants } or "",
      }, union)
  end
  for i, union in ipairs(enums) do
    fields[#fields + 1] = buildenumfield(union)
  end
  local code = parser_gen {
    kind = "block",
    fields = fields,
  }
  print(code)
  local result = assert(load(code, "codegen:structreader"..layout.id))()(primitives)
  self.structreaders[layout.id] = result
  return result
end

return codegen

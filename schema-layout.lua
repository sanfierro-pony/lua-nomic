local pow = math.pow or load("return function(a, b) return a ^ b end")

local holes = {}
local holes_mt
local null = {}
function holes:new()
  return setmetatable({null, null, null, null, null, null}, holes_mt )
end

function holes:findhole(size)
  local holes = self
  if size >= #holes then
    error ("size too high "..tostring(size))
  elseif holes[size + 1] ~= null then
    local result = holes[size + 1]
    holes[size + 1] = null
    return result
  elseif size + 1 < #holes then
    local maybeNextSize = self:findhole(size + 1)
    if maybeNextSize ~= nil then
      maybeNextSize = maybeNextSize * 2
      holes[size + 1] = maybeNextSize + 1
      return maybeNextSize
    end
  end
  return nil
end

function holes:addholes(sizeln, offset)
  local holes = self
  assert(sizeln <= #holes)

  while sizeln < 6 do
    assert(holes[sizeln + 1] == null)
    assert(offset % 2 == 1)
    holes[sizeln + 1] = offset
    sizeln = sizeln + 1
    offset = math.floor((offset + 1) / 2)
  end
end

function holes:__tostring()
  local result = ""
  for i = 1, #self do
    local h = self[i]
    result = result .. tostring(pow(2, i - 1)) .. "bits has hole at " .. (h == null and "none" or tostring(pow(2, i - 1) * h)) .. " bits\n"
  end
  return result
end
holes_mt = { __index = holes, __tostring = holes.__tostring }
local function layoutmessage()

end

local function getwidth(ty)
  if ty.kind == 'enum' then
    return 4
  end
  if ty.bitwidthln then
    return ty.bitwidthln
  end
  if ty.basetype then
    return getwidth(ty.basetype)
  end
  p(ty)
  error "TODO: getwidth for type"
end

local function ispointer(ty)
  if ty.kind == 'text' or ty.kind == 'struct' or ty.kind == 'list' then
    return true
  end

  if ty.basetype then
    return ispointer(ty.basetype)
  end

  return false
end

-- TODO more type detail
---@class StructLayout
---@field name string
---@field id string
---@field data table[]
---@field datalength number
---@field pointers table[]

-- Same idea as https://github.com/capnproto/capnproto/blob/9b1acb2f642fef318576c10a215bf6590c77538b/c%2B%2B/src/capnp/compiler/node-translator.c%2B%2B#L49
-- See docs there for why this works
-- this function assumes struct.fields is already sorted in evolution order
-- (schema does this)
---@return StructLayout
local function layoutstruct(struct)
  local h = holes:new()
  local words = 0
  local packed = {}
  local unionFields = {}
  local hole

  local packed = {
    name = struct.name,
    id = struct.id,
    data = {},
    pointers = {},
  }
  local packed_by_idx = {}

  for idx, field in ipairs(struct.fields) do
    if ispointer(field.type) then
      local pointer = {
        name = field.name,
        ["type"] = field.type,
        offset = #packed.pointers,
        discriminator = field.descriminator,
        discriminant = field.descriminant,
      }
      if field.type.kind == 'struct' then
        pointer.layout = function ()
          return layoutstruct(field.type)
        end
      elseif field.type.kind == 'list' and field.type.args[1].kind == 'struct' then
        pointer.layout = function ()
          return layoutstruct(field.type.args[1])
        end
      end
      packed.pointers[#packed.pointers + 1] = pointer
    else
      local lnbitwidth, wordwidth = getwidth(field.type)
      if lnbitwidth == 6 then
        wordwidth = 1
        lnbitwidth = nil
      end
      if lnbitwidth then
        hole = h:findhole(lnbitwidth)
        if hole == nil then
          hole = words * pow(2, 6 - lnbitwidth)
          words = words + 1
          h:addholes(lnbitwidth, hole + 1)
        end
      elseif wordwidth then
        hole = words
        words = words + wordwidth
      else
        error("field must have lnbitwidth or wordwidth")
      end
      local packedfield = {
        order = idx,
        name = field.name,
        ["type"] = field.type,
        offset = hole,
        lnbitwidth = lnbitwidth or 6,
        discriminator = field.descriminator,
        discriminant = field.descriminant,
      }
      if field.type.kind == 'enum' then
        local vindex = {}
        for _, v in ipairs(field.type.variants) do
          vindex[v.name] = v.variantindex
        end
        packedfield.vindex = vindex
      end
      packed.data[#packed.data + 1] = packedfield
      packed_by_idx[idx] = packedfield
    end
  end

  packed.datalength = words

  for _, field in ipairs(packed.data) do
    if field.discriminator then
      field.discriminator = packed_by_idx[field.discriminator].offset
    end
  end

  for _, field in ipairs(packed.pointers) do
    if field.discriminator then
      field.discriminator = packed_by_idx[field.discriminator].offset
    end
  end

  return packed
end

return {
  layoutstruct = layoutstruct,
  holes = holes,
}

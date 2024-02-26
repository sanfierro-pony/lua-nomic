local schema = require 'schema'

---@class Holes
---@field private holeArray table<number, number[]>
local Holes = {}
local Holes_mt

local maxLogSize = 6

---@return Holes
function Holes:new()
  local holeArray = {}
  for i = 1, maxLogSize + 1 do
    holeArray[i] = {}
  end
  return setmetatable({
    -- table of holes available, holeArray[n + 1] is the offsets in 2^n bits to a hole of size 2^n bits
    -- word sized holes may come in to play due to evolution of unions,
    -- e.g. a ([u32 | u32], u32) evolving into ([u32 | (u32, u64)], u32) would leave a word hole after the first two u32s
    -- that is disconnected
    holeArray = holeArray,
  }, Holes_mt )
end

-- Get all of the holes of a given size.
---@param logSize number the log2 of the size of the holes to get
---@return number[] the offsets of the holes in 2^logSize bits
function Holes:getall(logSize)
  return self.holeArray[logSize + 1]
end

-- Find a hole of the given size if one exists.
---@param logSize number the log2 of the size of the hole to find
---@return number|nil holeOffset the offset of the hole, or nil if no hole of the given size exists
function Holes:findhole(logSize)
  local holes = self.holeArray
  if logSize > maxLogSize then
    error ("size too high "..tostring(logSize))
  elseif #holes[logSize + 1] > 0 then
    return table.remove(holes[logSize + 1], 1)
  elseif logSize + 1 <= maxLogSize then
    local largerHoleOffset = self:findhole(logSize + 1)
    if largerHoleOffset ~= nil then
      largerHoleOffset = largerHoleOffset * 2 -- adjust the offset to be in logSize
      table.insert(holes[logSize + 1], largerHoleOffset + 1)
      return largerHoleOffset
    end
  end
  return nil
end

-- Add a word to this set of holes. This function assumes that a single hole of size 2^logSize bits
-- has been taken from a word, and adds the holes necessary to represent the remaining holes in the word.
---@param logSize number the log2 of the size of the hole taken
---@param holeOffset number the offset of the first hole in 2^logSize bits
function Holes:addholes(logSize, holeOffset)
  local holes = self.holeArray
  -- yes, <, not <=, because there can't be remaining holes in a word if the hole taken is the whole word
  assert(logSize < maxLogSize)

  while logSize < maxLogSize do
    for i = 1, #holes[logSize + 1] do
      assert(holes[logSize + 1][i] < holeOffset)
    end
    assert(holeOffset % 2 == 1)
    table.insert(holes[logSize + 1], holeOffset)
    self:fixholeinvariants(logSize)
    logSize = logSize + 1
    holeOffset = math.floor((holeOffset + 1) / 2)
  end
end

-- Push a hole that is known.
---@param logSize number the log2 of the size of the hole
---@param holeOffset number the offset of the hole in 2^logSize bits
function Holes:pushhole(logSize, holeOffset)
  table.insert(self.holeArray[logSize + 1], holeOffset)
  self:fixholeinvariants(logSize)
end

-- Ensure that any holes next to each other are pushed up to be a hole of the next size.
---@param logSize number the log2 of the size of the potentially imbalanced hole array
function Holes:fixholeinvariants(logSize)
  local holes = self.holeArray
  local sizeArray = holes[logSize + 1]
  if #sizeArray > 1 then
    local secondToLast = sizeArray[#sizeArray - 1]
    local last = sizeArray[#sizeArray]
    if secondToLast % 2 == 0 and secondToLast == last - 1 then
      sizeArray[#sizeArray - 1] = nil
      sizeArray[#sizeArray] = nil
      table.insert(holes[logSize + 2], secondToLast / 2)
      self:fixholeinvariants(logSize + 1)
    end
  end
end

Holes_mt = { __index = Holes }

local function getwidth(ty)
  if ty.kind == 'enum' then
    -- enums are serialized as a u16
    return 4
  end
  if ty.logbitwidth then
    return ty.logbitwidth
  end
  if ty.kind == 'generic' then
    error("generics do not have a width, they are always pointers")
  end
  if ty.basetype then
    return getwidth(ty.basetype)
  end
  print("error in struct")
  require 'printer'.prettyPrint(ty)
  error "TODO: getwidth for type"
end

local function ispointer(ty)
  if ty.kind == 'struct' or ty.kind == 'generic' then
    return true
  end

  if ty == schema.anyPointer then
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
---@field id table|integer
---@field data table[] may contain padding elements
---@field datalength number
---@field pointers table[]
local StructLayout = {}

---@alias UnionHoles { parent: UnionHoles?, discriminator: number?, holes: Holes, pointerHoles: number[]? }

local function build_union_holes(struct, rootHoles)
  local unionHoles = {}
  for i, field in ipairs(struct.fields) do
    if field.type.kind == "enum" then
      local discrimHoles = unionHoles[i]
      if discrimHoles == nil then
        discrimHoles = {}
        unionHoles[i] = discrimHoles
      end
      -- create variant holes for each variant
      for _, variant in ipairs(field.type.variants) do
        local variantHoles = discrimHoles[variant.variantindex]
        if variantHoles == nil then
          variantHoles = {
              holes = Holes:new(),
              discriminator = i,
              pointerHoles = {},
          }
          if field.kind == "union" then
            -- The parent is the holes for the union we're in, which should have already appeared
            local parentHoles = unionHoles[field.discriminator][field.discriminant]
            if parentHoles == nil then
              error("union parent hole not found for field " .. field.name)
            end
            variantHoles.parent = parentHoles
          else
            -- The parent is the holes for the struct we're in
            variantHoles.parent = rootHoles
          end
          discrimHoles[variant.variantindex] = variantHoles
        end
      end
    end
  end
  return unionHoles
end

-- Same idea as https://github.com/capnproto/capnproto/blob/9b1acb2f642fef318576c10a215bf6590c77538b/c%2B%2B/src/capnp/compiler/node-translator.c%2B%2B#L49
-- See docs there for why this works
-- this function assumes struct.fields is already sorted in evolution order
-- (schema does this)
---@return StructLayout
local function layoutstruct(struct)
  if struct.fields == nil then
    print("error in struct")
    require 'printer'.prettyPrint(struct, 1)
    error("struct " .. (struct.name or "nil") .. " has no fields")
  end
  local h = { holes = Holes:new() }
  local words = 0
  local pointers = 0
  local packed = {}
  ---@type table<number, table<number, UnionHoles>> discriminator field index -> variant holes by variant index
  local unionHoles = build_union_holes(struct, h)

  local packed = {
    name = struct.name,
    id = struct.id,
    data = {},
    pointers = {},
  }
  local packed_by_idx = {}

  ---@param uh UnionHoles
  ---@param logbitwidth number
  ---@return number holeOffset
  local function get_hole_for_size(uh, logbitwidth)
    local holeOffset = uh.holes:findhole(logbitwidth)
    if holeOffset == nil then
      if uh.parent then
        holeOffset = get_hole_for_size(uh.parent, logbitwidth)
        -- Push this hole into our siblings so they can use it if they need, we won't push it since we're using it now
        local siblings = unionHoles[uh.discriminator]
        for _, variantHoles in pairs(siblings) do
          if variantHoles ~= uh then
            variantHoles.holes:pushhole(logbitwidth, holeOffset)
          end
        end
      else
        holeOffset = words * (2 ^ (maxLogSize - logbitwidth))
        words = words + 1
        -- Don't add word-sized holes here, as we don't need to track them at the top level
        if logbitwidth < maxLogSize then
          uh.holes:addholes(logbitwidth, holeOffset + 1)
        end
      end
    end
    return holeOffset
  end

  ---@param field table the field to get a hole for
  ---@return number logbitwidth, number holeOffset the logbitwidth of the hole and the offset of the hole in 2^logbitwidth bits
  local function get_hole_for_field(field)
    local holes
    if field.kind == "union" then
      holes = unionHoles[field.discriminator][field.discriminant]
    else
      holes = h
    end
    local logbitwidth = getwidth(field.type)
    local holeOffset = get_hole_for_size(holes, logbitwidth)
    return logbitwidth, holeOffset
  end

  local function get_pointer_hole(holes)
    if holes.pointerHoles then
      local holeOffset = table.remove(holes.pointerHoles, 1)
      if holeOffset == nil then
        if holes.parent == nil then
          error("pointer holes should always have a parent")
        end
        holeOffset = get_pointer_hole(holes.parent)
        local siblings = unionHoles[holes.discriminator]
        for _, variantHoles in pairs(siblings) do
          if variantHoles ~= holes then
            variantHoles.pointerHoles[#variantHoles.pointerHoles + 1] = holeOffset
          end
        end
      end
      return holeOffset
    else
      pointers = pointers + 1
      return pointers - 1
    end
  end

  local function get_pointer_hole_for_field(field)
    local holes
    if field.kind == "union" then
      holes = unionHoles[field.discriminator][field.discriminant]
    else
      holes = h
    end
    return get_pointer_hole(holes)
  end

  for idx, field in ipairs(struct.fields) do
    if ispointer(field.type) then
      local pointer = {
        kind = "pointer",
        name = field.name,
        ["type"] = field.type,
        offset = get_pointer_hole_for_field(field),
        discriminator = field.discriminator,
        discriminant = field.discriminant,
      }
      if field.type.kind == 'struct' then
        pointer.layout = function ()
          return layoutstruct(field.type)
        end
      elseif field.type.kind == 'generic' and field.type.basetype.kind == 'list' and field.type.args[1].kind == 'struct' then
        pointer.layout = function ()
          return layoutstruct(field.type.args[1])
        end
      end
      packed.pointers[#packed.pointers + 1] = pointer
    else
      local logbitwidth, hole = get_hole_for_field(field)
      local packedfield = {
        kind = "field",
        order = #packed.data + 1,
        name = field.name,
        ["type"] = field.type,
        offset = hole,
        logbitwidth = logbitwidth,
        discriminator = field.discriminator,
        discriminant = field.discriminant,
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

  -- Insert padding into data for all remaining holes of at least 2^3 bits
  for i = 4, maxLogSize + 1 do
    local holes = h.holes:getall(i - 1)
    for _, holeOffset in ipairs(holes) do
      packed.data[#packed.data + 1] = {
        order = #packed.data + 1,
        kind = "padding",
        offset = holeOffset,
        logbitwidth = i - 1,
      }
    end
  end
  for discriminator, discrimHoles in pairs(unionHoles) do
    for variant, variantHoles in pairs(discrimHoles) do
      for i = 4, maxLogSize + 1 do
        local holes = variantHoles.holes:getall(i - 1)
        for _, holeOffset in ipairs(holes) do
          packed.data[#packed.data + 1] = {
            order = #packed.data + 1,
            kind = "padding",
            offset = holeOffset,
            logbitwidth = i - 1,
            discriminator = discriminator,
            discriminant = variant,
          }
        end
      end
      if variantHoles.pointerHoles then
        for _, holeOffset in ipairs(variantHoles.pointerHoles) do
          packed.pointers[#packed.pointers + 1] = {
            kind = "padding",
            offset = holeOffset,
            discriminator = discriminator,
            discriminant = variant,
          }
        end
      end
    end
  end

  for _, field in ipairs(packed.data) do
    if field.discriminator then
      field.discriminator = packed_by_idx[field.discriminator].order
    end
  end

  for _, ptr in ipairs(packed.pointers) do
    if ptr.discriminator then
      ptr.discriminator = packed_by_idx[ptr.discriminator].order
    end
  end

  return packed
end

return {
  layoutstruct = layoutstruct,
  Holes = Holes,
}

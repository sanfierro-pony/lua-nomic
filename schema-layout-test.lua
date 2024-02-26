local layout = require'schema-layout'
local lu = require'libs.luaunit'
local schema = require'schema'
local u8, u16, u32, u64 = schema.u8, schema.u16, schema.u32, schema.u64
local Holes = layout.Holes
local p = _G.p or print

local function name_to_start(packed)
  local packed_by_name = {}
  p(packed)
  for _, v in ipairs(packed.data) do
    packed_by_name[v.name] = v.offset * (2 ^ v.logbitwidth)
  end
  return packed_by_name
end

function test1_layout()
  local layout = name_to_start(layout.layoutstruct({ id=7, fields = {
      {name = "a", order = 1, type=u32},
      {name = "b", order = 1, type=u64},
      {name = "c", order = 1, type=u16},
      {name = "d", order = 1, type=u8},
  }}))
  lu.assertEquals(layout, {
    a = 0,
    b = 64,
    c = 32,
    d = 48,
  })
end

function test2_layout()
  local layout = name_to_start(layout.layoutstruct(
  {
    id = 2,
    fields = {
      {name = "a", order = 1, type=u64},
      {name = "b", order = 1, type=u64},
      {name = "c", order = 1, type=u64},
      {name = "d", order = 1, type=u64},
    },
  }))
  lu.assertEquals(layout, {
    a = 0,
    b = 64,
    c = 128,
    d = 192,
  })
end

testholes = {}

function testholes:testadd()
  local holes = layout.Holes:new()
  for i = 1, 5 do
    lu.assertEquals(holes:findhole(i), nil)
  end
  -- add a 32 bit hole at 32 bits in
  holes:addholes(5, 1)
  lu.assertEquals(holes:findhole(5), 1)
  holes[5] = holes[1]

  -- add a 16 bit hole at 16 bits in and a 32 bit hole at 32 bits in (allocated word, used first 16 bits)
  holes:addholes(4, 1)
  lu.assertEquals(holes:findhole(5), 1)
  lu.assertEquals(holes:findhole(4), 1)
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
checkGlobal = true
if not _G.checkGlobal then
  _G['tests'] = _ENV or getfenv()
end
-- _G['tests'] = { test1_layout = test1_layout }
os.exit(lu.LuaUnit.run())

-- parse from schema, save to buf, read from buf, compare
--
local schema = require 'schema'
local cg = require 'codegen'
local lu = require 'libs.luaunit'
local pow = math.pow or load("return function(a, b) return a ^ b end")

local text, union, enum, variant = schema.text, schema.union, schema.enum, schema.variant
local u16, u32, u64, list = schema.u16, schema.u32, schema.u64, schema.list
local bool = schema.bool

local S = schema.newschema("schema", "the schema for saving and transmitting schemas", 0xa3329f307fcd88f6)

local stype = S:addstruct("type", "the type that a field may have")
local struct = S:addstruct("struct", "a structure containing named fields")
local field = S:addstruct("field", "something in a structure where data can be stored")
local senum = S:addstruct("enum", "a set of meaningful names which get stored as a single number")

local typeid = S:newtype("typeid", u64)
local schemaid = S:newtype("schemaid", u64)
local fieldid = S:newtype("fieldid", u64)

local function printstruct(struct)
  for i, field in ipairs(struct.fields) do
    p(i - 1, field.name, field.type, field.descriminator and struct.fields[field.descriminator].name, field.descriminant)
  end
end

local layout = require 'schema-layout'

local function toComparableLayout(fieldlayout)
  local comparable = {
    data = {},
    pointers = {},
  }
  for idx, ptr in ipairs(fieldlayout.pointers) do
    comparable.pointers[ptr.name] = ptr.offset
  end
  for idx, dat in ipairs(fieldlayout.data) do
    comparable.data[dat.name] = dat.offset * pow(2, dat.lnbitwidth)
  end
 return comparable
end

function testSchemaBootstrapFieldStruct()
  field:define {
    text "name" (0) "the name of the field as it should be used to generate the keys of the table";
    stype "type" (1) "The type the field is stored as";
    text "docstring" (3) "expanded documentation describing the usage and meaning of the field";
    union "kind" (2) "what kind of field it is, whether it is always present, whether it is part of an enum"
    {
      variant "field" (4) "This field is just an ordinary field that is always accessible" {};
      variant "union" (5) "The field is part of a union, only accessible when the descriminator has a particular value"
      {
        -- support your local union
        u16 "descriminator" (6) "which component of the struct holds the discriminator for this union field";
        u16 "descriminant" (7) "the value the descriminator field must take for this field to be valid.";
      };
    };
    fieldid "id" (8) "The unique key for a field automatically derived from the initial name and the struct to verify forward compatibility. The collision domain for this key is within the parent struct.";
    -- not normally in the schema but i want to test bit packing
    bool "b1" (9) "demo bool 1";
    bool "b2" (10) "demo bool 1";
  }

  local expectedLayout = {
    -- bit offsets
    data = {
      kind = 0 * 16,
      descriminator = 1 * 16,
      descriminant = 2 * 16,
      id = 1 * 64,
      b1 = 3*16,
      b2 = 3*16 + 1,
    },
    -- word offsets
    pointers = {
      name = 0,
      ["type"] = 1,
      docstring = 2,
    },
  }

  printstruct(field)
  local fieldlayout = layout.layoutstruct(field)
  local cmpLayout = toComparableLayout(fieldlayout)
  lu.assertEquals(expectedLayout, cmpLayout)
end


function testNestedUnionStruct()
  local testunionstruct = S:struct "structname" ""
  {
    union "testunion" (0)
    {
      variant "none" (2) {};
      variant "some" (1) {
        union "innertestunion" (3)
        {
          -- TODO: better error if forget {}
          variant "none" (5) {};
          variant "number" (4) {
            u32 "innernumber" (6);
          };
        };
      };
    };
  }

  local fl = layout.layoutstruct(testunionstruct)

  local expectedLayout = {
    -- bit offsets
    data = {
      testunion = 0,
      innertestunion = 16,
      innernumber = 32,
    },
    -- word offsets
    pointers = {
    },
  }

  local toCompare = toComparableLayout(fl)
  lu.assertEquals(expectedLayout, toCompare)

  local reader = cg:new():structreader(fl)
  local parsed = reader("", 0, 0, 0)

  lu.assertEquals(parsed, {
    testunion = "some",
    innertestunion = "number",
    innernumber = 0,
  })

  parsed = reader(string.pack("I2I2I4", 0, 0, 17), 0, 2, 0)
  lu.assertEquals(parsed, {
    testunion = "some",
    innertestunion = "number",
    innernumber = 17,
  })
  parsed = reader(string.pack("I2I2I4", 1, 1, 17), 0, 2, 0)
  lu.assertEquals(parsed, {
    testunion = "none",
  })

  parsed = reader(string.pack("I2I2I4", 2, 0, 17), 0, 2, 0)
  lu.assertEquals(parsed, {
    testunion = 2,
  })




end



function testEmptyUnionStruct()
  local testunionstruct = S:struct "structname" ""
  {
    union "testunion" (0)
    {
    };
  }

  p("testunionstruct", testunionstruct)
  local fl = layout.layoutstruct(testunionstruct)

  local expectedLayout = {
    -- bit offsets
    data = {
      testunion = 0,
    },
    -- word offsets
    pointers = {
    },
  }

  local toCompare = toComparableLayout(fl)

  -- lu.assertEquals(expectedLayout, toCompare)

  local reader = cg:new():structreader(fl)
  local parsed = reader("", 0, 0, 0)

  p(parsed)
  lu.assertEquals(parsed, {
    testunion = 0,
  })

  local writer = cg:new():structwriter(fl)
  local written = writer(parse)
  p(written)
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
checkGlobal = true
if not _G.checkGlobal then
  _G['tests'] = _ENV or getfenv()
end
-- _G['tests'] = { test1_layout = test1_layout }
os.exit(lu.LuaUnit.run())

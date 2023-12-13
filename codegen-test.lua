local lu = require'libs.luaunit'
local codegen = require'codegen'
local schema = require'schema'
local encdec = require'encdec'
local u64 = require'primitives.primitives-u64'

local testschema = schema.newschema("teststruct", "a test struct", u64"68859291b0c3")
local teststruct = testschema:addstruct("teststruct", "a test struct")
teststruct:define {
  schema.bool "first" (0) "the first bool";
  schema.bool "second" (1) "the second bool";
}

function testcodegen()
  local struct = encdec.decode(teststruct, "")
  lu.assertEquals(struct, {
    first = false,
    second = false,
  })
end

function testcodegenwriter()
  local testData = {
    first = false,
    second = true,
  }
  local written = encdec.encode(teststruct, testData)
  local struct = encdec.decode(teststruct, written)
  lu.assertEquals(struct, testData)
end

local schemaSchema = require 'schema-bootstrap'
function testschemaschemacanschemaschema()
  local written = encdec.encode(schemaSchema.export.schema, schemaSchema)
  p(written)
  local struct = encdec.decode(schemaSchema, written)
  p(struct)
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
_G['tests'] = _ENV or getfenv()
os.exit(lu.LuaUnit.run())

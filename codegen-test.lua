local lu = require'luaunit'
local u64 = require'primitives/primitives-u64'
local codegen = require'codegen'
local schema = require'schema'
local encdec = require'encdec'
local printer = require'printer'

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

local function sortedPairs(value)
  local keys = {}
  for k, _ in pairs(value) do
    table.insert(keys, k)
  end
  table.sort(keys)
  local i = 0
  return function()
    i = i + 1
    return keys[i], value[keys[i]]
  end
end

local function assertEquals(a, b, ignorePathRegex, path)
  if path == nil then
    path = "<root>"
  end
  if ignorePathRegex then
    for _, regex in ipairs(ignorePathRegex) do
      if path:match(regex) ~= nil then
        return
      end
    end
  end
  if type(a) ~= type(b) then
    print("a:")
    printer.prettyPrint(a, 2)
    print("b:")
    printer.prettyPrint(b, 2)
    lu.fail("type mismatch at " .. path .. ": " .. type(a) .. " ~= " .. type(b))
  end
  if type(a) == 'table' then
    local checked = {}
    for k, v in sortedPairs(a) do
      checked[k] = true
      assertEquals(v, b[k], ignorePathRegex, path .. "." .. k)
    end
    for k, v in sortedPairs(b) do
      if not checked[k] then
        assertEquals(a[k], v, ignorePathRegex, path .. "." .. k)
      end
    end
  else
    lu.assertEquals(a, b)
  end
end

local schemaSchema = require 'schema-bootstrap'
function testschemaschemacanschemaschema()
  local written = encdec.encode(schemaSchema.export.schema, schemaSchema)
  local struct = encdec.decode(schemaSchema.export.schema, written)
  assertEquals(schemaSchema, struct, {
    -- not part of schema
    "%.type%.docstring$",
    "%.type%.id$",
    "%.type%.name$",
    "%.type%.variants$",
    "%.type%.components$",
    "%.type%.count$",
    "%.type%.field_by_name$",
    "%.type%.fields$",
    "%.basetype%.docstring$",
    "%.basetype%.id$",
    "%.basetype%.name$",
    "%.basetype%.variants$",
    "%.basetype%.components$",
    "%.basetype%.count$",
    "%.basetype%.field_by_name$",
    "%.basetype%.fields$",
    "%.basetype%.logbitwidth$",
    "%.export$",
    "%.exports%.%d+%.type%.kind$",
  })
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
_G['tests'] = _ENV or getfenv()
os.exit(lu.LuaUnit.run())

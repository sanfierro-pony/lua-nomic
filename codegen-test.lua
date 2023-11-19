local lu = require'libs.luaunit'
local codegen = require'codegen'
local schema = require'schema'

local teststruct = {
  id = 12345,
  data = {
    {
      name = "first",
      offset = 0,
      ["type"] = schema.bool,
      lnbitwidth = 1,
    },
    {
      name = "second",
      offset = 1,
      ["type"] = schema.bool,
      lnbitwidth = 1,
    }
  },
  pointers = {

  },
}

function testcodegen()
  local cg = codegen.new()
  local reader = cg:structreader(teststruct)
  local struct = reader("", 0, 0, 0)
  p(struct)
  lu.assertEquals(struct, {
    first = false,
    second = false,
  })
end

function testcodegenwriter()
  local cg = codegen.new()
  local writer = cg:structwriter(teststruct)
  local testData = {
    first = false,
    second = true,
  }
  local written = writer(testData , 0, 0, 0, 0)
  local read = reader(written, 0, 0, 0)
  lu.assertEquals(testData, read)
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
_G['tests'] = _ENV or getfenv()
os.exit(lu.LuaUnit.run())

local lu = require'libs.luaunit'
local codegen = require'codegen'
local schema = require'schema'

function testcodegen()
  local cg = codegen.new()
  local reader = cg:structreader({
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
  })
  local struct = reader("", 0, 0, 0)
  p(struct)
  lu.assertEquals(struct, {
    first = false,
    second = false,
  })
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
_G['tests'] = _ENV or getfenv()
os.exit(lu.LuaUnit.run())

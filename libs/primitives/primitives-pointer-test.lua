local pointers = require'primitives/primitives-pointer'
local lu = require'libs.luaunit'
local bit = _G['bit'] or _G['bit32'] or require 'primitives/polyfill.bit'


local function roundTripPointer(lsw, msw)
    local unpacked = pointers.unpackPointer(lsw, msw)
    local packedLsw, packedMsw = pointers.packPointer(unpacked)
    assert(packedLsw == lsw, "lsw != packedLsw " .. tostring(packedLsw) .. " " .. tostring(lsw))
    assert(packedMsw == msw, "msw != packedMsw " .. tostring(packedMsw) .. " " .. tostring(msw))
    return unpacked
end

function testList()
  lu.assertEquals(roundTripPointer(0, 0), {
    kind = "struct",
    offset = 0,
    datasize = 0,
    pointersize = 0,
  })
end

function test2()
  roundTripPointer(bit.bor(0, bit.lshift(4, 2)), 16 + bit.lshift(17, 16))
  roundTripPointer(1, 0)
end

function testCapPointer()
  lu.assertEquals(roundTripPointer(3, 0),
    {
      kind = "capability",
      capabilityindex = 0,
    }
  )
end

-- HACK: luaunit wants to find tests in globals and luvit doesn't run us with _ENV == _G
_G['tests'] = _ENV or getfenv()
os.exit(lu.LuaUnit.run())

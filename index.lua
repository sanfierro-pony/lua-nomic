local html = require './html'
local bundle = require 'luvi'.bundle
local fs = require 'coro-fs'
local json = require 'json'

local pagescript = fs.readFile('counter-ui-test.lua')

return function(req, res, go)
  table.insert(res.headers, {"Content-Type", "text/html"})
  res.body = html.render(
    html.html {
      html.head {
        html.title "fengari test",
        html.script {
          src = "fengari-web.js",
          type = "text/javascript"
        },
        html.script {
          type = "text/javascript",
          [[
            const { L, to_luastring } = fengari;
            const { LUA_ERRSYNTAX, lua_call, lua_pop, lua_setglobal, lua_tojsstring } = fengari.lua;
            const { luaL_loadbufferx } = fengari.lauxlib;
            const { tojs } = fengari.interop;

            const modulesText = ]] .. json.encode(fs.readFile('modules.lua')) .. [[

            // Load modules.lua
            const ok = luaL_loadbufferx(L, to_luastring(modulesText), undefined, to_luastring("modules.lua"), to_luastring("t"));
            let err = undefined;
            if (ok === LUA_ERRSYNTAX) {
              err = new SyntaxError(lua_tojsstring(L, -1));
            } else if (ok !== 0) {
              err = tojs(L, -1);
            }
            if (err) {
              lua_pop(L, 1); // remove error from stack
              throw err;
            }
            // Execute modules.lua, passing nothing and expecting a table
            lua_call(L, 0, 1);
            // Store the modules table in globals
            lua_setglobal(L, to_luastring("modules"));
          ]]
        },
        -- Load quill and slot using the modules.lua API
        html.script {
          type = "text/lua",
          [[
            local quillText = ]] .. string.format("%q", fs.readFile('quill.lua')) .. [[

            modules.define("quill", quillText, "quill.lua")
            local slotText = ]] .. string.format("%q", fs.readFile('slot.lua')) .. [[

            modules.define("slot", slotText, "slot.lua")
          ]]
        },
      },
      html.body {
        id = "body"
      }
    },
    {}
  )
  res.code = 200;
end

local html = require './html'
local bundle = require 'luvi'.bundle
local fs = require 'coro-fs'
local json = require 'json'

return function(req, res, go)
  local pagescript = fs.readFile('pagescript.lua')

  local sources = {}
  for _, v in ipairs{
    "client-dom", "client-html", "client-svg", "modules",
    "libs/rpc", "libs/rpc-schema", "libs/deque", "libs/encdec", "libs/promise",
    "libs/printer", "libs/printer-helper-generic",
    "libs/require-modules", "libs/tableutil", "libs/codegen", "libs/abstract-codegen", "libs/lulpeg",
    "libs/schema", "libs/schema-bootstrap", "libs/schema-hash", "libs/schema-layout", "libs/sha2",
    "libs/primitives/primitives", "libs/primitives/primitives-pointer", "libs/primitives/string-buffer",
    "libs/primitives/primitives-u64", "libs/primitives/u64-bint",
    "libs/primitives/polyfill/bit", "libs/bint", "libs/datagram/common",
    "clientmodules/testapp", "clientmodules/counter"
  } do
    local data, err = fs.readFile(v .. ".lua")
    if err ~= nil then
      error("failed to read file '" .. v .. "': " .. tostring(err))
    end
    sources[v] = data
  end

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
          [[
            document.addEventListener("DOMContentLoaded", () => {
              const {lua, lauxlib, interop} = fengari;
              console.log("setting up fengari hooks");
              let inError = 0;
              lua.lua_atnativeerror(fengari.L, (L) => {
                try {
                  if (inError > 0) {
                    throw new Error("recursive native error");
                  }
                  inError++;
                  try {
                    lauxlib.luaL_traceback(L, L);
                    const top = lua.lua_gettop(L);
                    const tb = lua.lua_tojsstring(L, top);
                    let e = lua.lua_touserdata(L, 1);
                    console.error('native error', e, tb);
                  } finally {
                    inError--;
                  }
                } catch (err) {
                  console.error('failed to handle native error', err);
                }
              });

              const jshooks = {
                stringToByteBuffer(L) {
                  const n = lua.lua_gettop(L);
                  if (n != 1) {
                    return lauxlib.luaL_error(L, "expected 1 argument");
                  }
                  if (!lua.lua_isstring(L, 1)) {
                    return lauxlib.luaL_error(L, "expected string");
                  }
                  const str = lua.lua_tostring(L, 1);
                  if (!(str instanceof Uint8Array)) {
                    return lauxlib.luaL_error(L, "expected string implementation to be Uint8Array");
                  }
                  interop.pushjs(L, str);
                  return 1;
                },
                arrayBufferToString(L) {
                  const n = lua.lua_gettop(L);
                  if (n != 1) {
                    return lauxlib.luaL_error(L, "expected 1 arguments");
                  }
                  const buf = interop.tojs(L, 1);
                  if (!(buf instanceof ArrayBuffer)) {
                    return lauxlib.luaL_error(L, "expected ArrayBuffer");
                  }
                  const str = new Uint8Array(buf);
                  lua.lua_pushstring(L, str);
                  return 1;
                },
                arshift(L) {
                  const n = lua.lua_gettop(L);
                  if (n != 2) {
                    return lauxlib.luaL_error(L, "expected 2 arguments");
                  }
                  const a = lua.lua_tonumber(L, 1);
                  const b = lua.lua_tonumber(L, 2);
                  lua.lua_pushnumber(L, a >> b);
                  return 1;
                }
              };
              lauxlib.luaL_requiref(fengari.L, fengari.to_luastring("jshooks"), (L) => {
                lauxlib.luaL_newlib(L, jshooks);
                return 1;
              }, 1);
              lua.lua_pop(fengari.L, 1); /* remove lib */

              const pagescript = document.getElementById("pagescript").value;
              console.log("loading pagescript");
              fengari.load(pagescript, "pagescript.lua")();
            });
          ]]
        },
        html.data {
          id = "sources",
          value = json.encode(sources) --[[@as string]]:gsub(".", function(c) return "&#"..string.byte(c)..";" end)
        },
        html.data {
          id = "pagescript",
          value = pagescript --[[@as string]]:gsub(".", function(c) return "&#"..string.byte(c)..";" end)
        }
      },
      html.body {
        id = "body",
        html.div {
          id = "mainapp",
        }
      }
    },
    {doctype = "html"}
  )
  res.code = 200;
end

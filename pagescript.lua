local function withTraceback(f)
  return function(...)
    return xpcall(f, function(err)
      print(debug.traceback(err, 2))
    end, ...)
  end
end
withTraceback(function()
  local js = require 'js'

  ---@module "typedef.jsdom"
  ---@type Document
  local document = js.global.document

  local sources = js.global.JSON:parse(document:getElementById("sources").value)

  ---@module "modules"
  local modules_base = assert(load(sources.modules, "modules.lua"))()

  local module_create = modules_base(false)

  local require_modules = assert(load(sources["libs/require-modules"], "require-modules.lua"))()(module_create, sources)

  local style_sheet = js.new(js.global.CSSStyleSheet)
  document.adoptedStyleSheets:push(style_sheet)

  print "client dom"
  ---@module "client-dom"
  local client_dom = module_create(sources["client-dom"], "client-dom.lua")(document, style_sheet, "mainapp")
  print "client html"
  ---@module "client-html"
  local client_html = module_create(sources["client-html"], "client-html.lua")(client_dom)
  print "client svg"
  ---@module "client-svg"
  local client_svg = module_create(sources["client-svg"], "client-svg.lua")(client_dom)
  print "rpc"
  ---@module "promise"
  local promise = require_modules.loadModule(
    "promise",
    function(canonicalName)
      -- promise can load whatever it wants
      return true
    end
  )
  ---@module "rpc"
  local rpc = require_modules.loadModule(
    "rpc",
    function(canonicalName)
      -- rpc can load whatever it wants
      return true
    end,
    {
      js = js,
      math = math,
      string = string,
      table = table,
      promise = promise,
    }
  )
  local printer = require_modules.loadModule(
    "libs/printer",
    function(canonicalName)
      -- printer can load whatever it wants
      return true
    end,
    {
    }
  )
  ---@module "datagram/common"
  local Datagrammer = require_modules.loadModule(
    "datagram/common",
    function(canonicalName)
      -- jsWebsocket can load whatever it wants
      return true
    end,
    {}
  )

  local function makeCallback()
    local thread = coroutine.running()
    return function(...)
      return coroutine.resume(thread, ...)
    end
  end

  local function getServerConn()
    local websocket = js.new(js.global.WebSocket, "ws://localhost:8080/v2/socket")
    websocket.binaryType = "arraybuffer"
    websocket:addEventListener('error', function(ws, event)
      js.global.console:log("websocket error", event)
    end)
    websocket:addEventListener('open', function(ws, event)
      js.global.console:log("websocket open", event)
    end)
    websocket:addEventListener('close', function(ws, event)
      js.global.console:log("websocket close", event)
    end)
    local link = Datagrammer:new(function(datagram)
      if websocket.readyState ~= 1 then
        websocket:addEventListener('open', makeCallback())
        coroutine.yield()
      end
      local buf = jshooks.stringToByteBuffer(datagram)
      js.global.console:log("sending datagram", buf)
      websocket:send(buf)
    end)
    websocket:addEventListener('message', function(ws, event)
      local data = jshooks.arrayBufferToString(event.data)
      link:receive(data)
    end)
    local conn = rpc.Conn:new(link)
    local writerThread = conn:createWriterCoroutine()
    coroutine.resume(writerThread)
    return conn
  end

  local initThread = coroutine.create(withTraceback(function()
    print "counter"
    ---@module "clientmodules.counter"
    local counter = module_create(sources["clientmodules/counter"], "clientmodules/counter.lua") { html = client_html }
    print "testapp"
    ---@module "clientmodules.testapp"
    local testapp = module_create(sources["clientmodules/testapp"], "clientmodules/testapp.lua") {
      html = client_html,
      svg = client_svg,
      getServerConn = getServerConn,
      promise = promise,
      printer = printer,
      rpc = rpc,
      schemaLayout = require_modules.loadModule(
        "schema-layout",
        function(canonicalName)
          -- schemaLayout can load whatever it wants
          return true
        end,
        {
        }
      ),
    }
    print "done loading scripts"

    client_dom.claim_root(document:getElementById("mainapp"), function() return testapp:render() end)
    print "root claimed"

    print(pcall(client_dom.notify))
  end))
  coroutine.resume(initThread)
end)()

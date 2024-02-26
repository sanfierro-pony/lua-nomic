local weblit = require "./deps/weblit"
local uv = require "uv"
local Conn = require "rpc".Conn
local Datagrammer = require "datagram/common"

local app = weblit.app

app.bind(
    {
        host = "127.0.0.1",
        port = 8080
    }
).use(weblit.logger).use(weblit.autoHeaders).use(weblit.etagCache)

app.websocket(
    {
        path = "/v2/socket", -- Prefix for matching
        heartbeat = 1000, -- Send a ping every 1000ms
        --protocol = "virgo/2.0", -- Restrict to a websocket sub-protocol
    },
    function(req, read, write)
        local link = Datagrammer:new(function (datagram)
            write({
                opcode = 0x02,
                payload = datagram
            })
        end)
        local conn = Conn:new(link)
        local writerThread = conn:createWriterCoroutine()
        coroutine.resume(writerThread)
        for datagram in read do
            link:receive(datagram.payload)
        end
        write()
    end
)

app.route({method = "GET", path = "/index.html"}, require './index')

app.use(weblit.static "bundle:static/").use(weblit.static "static/")

app.start()

require "uv".run()

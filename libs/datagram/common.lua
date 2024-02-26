---@class Datagrammer a datagram communicator implemented a writer and callbacks
---@field write fun(string?) the websocket writer
---@field callbacks fun(datagram:string)[] the callbacks to call when a datagram is received
local Datagrammer = {}
local Datagrammer_mt = {__index = Datagrammer}

-- TODO dedupe with pagescript.lua
local function withTraceback(f)
  return function(...)
    return xpcall(f, function(err)
      print(debug.traceback(err, 2))
    end, ...)
  end
end

function Datagrammer:new(write)
  local o = {
    write = write,
    callbacks = {}
  }
  return setmetatable(o, Datagrammer_mt)
end

-- send a datagram
---@param datagram string the datagram to send
function Datagrammer:send(datagram)
  self.write(datagram)
end

-- receive a datagram
---@param datagram string the datagram to receive
function Datagrammer:receive(datagram)
  for i = 1, #self.callbacks do
    self.callbacks[i](datagram)
  end
end

-- register a callback for datagrams
---@param callback fun(datagram:string) the callback to register
function Datagrammer:on_datagram(callback)
  self.callbacks[#self.callbacks + 1] = withTraceback(callback)
end

-- close the datagrammer
function Datagrammer:close()
  self.write()
end

return Datagrammer

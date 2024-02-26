local Deque = require"deque".Deque
local tableutil = require "tableutil"

---@class SlotReservation
---@field index integer index into buffer where this reservation was added
---@field offset integer offset into buffer (in bytes) where this reservation was added
---@field length integer length of the reservation

---@class DelayedStringBufferPointerWrite information about a pointed-to datum that needs to be written later
---@field key CacheKey the key for the pointer cache
---@field default any? the default value for the pointer
---@field reservation SlotReservation the reservation for the pointer to this datum
---@field writer fun(thing: any, buf: StringBuffer): PointerInfo the function to write the datum, returns the pointer

---@class StringBuffer
---@field private buffer (string|SlotReservation)[]
---@field private cursor integer current offset into buffer, in characters
---@field private reservations table<SlotReservation, boolean> reservations, must be empty to convert to string
---@field private pointerQueueStack Deque stack of queues of pointers to write (full type is Deque<Deque<DelayedStringBufferPointerWrite>>)
---@field private knownPointers table<string, table<any, PointerInfo>> map from cache key to pointer info, however the offset is absolute here
local StringBuffer = {}
local StringBuffer_mt = {
  __index = StringBuffer;
}

-- Creates a new StringBuffer
---@return StringBuffer
local function createStringBuffer()
  local self = {
    buffer = {},
    cursor = 0,
    reservations = {},
    pointerQueueStack = Deque:new(),
    knownPointers = {},
  }
  return setmetatable(self, StringBuffer_mt)
end

function StringBuffer:length()
  return self.cursor
end

-- Appends a string to the buffer
---@param text string
function StringBuffer:append(text)
  table.insert(self.buffer, text)
  self.cursor = self.cursor + #text
end

-- Reserve this slot in the buffer for filling in later
---@return SlotReservation
function StringBuffer:reserve(length)
  local reservation = {
    index = #self.buffer + 1,
    offset = self.cursor,
    length = length,
  }
  self.reservations[reservation] = true
  table.insert(self.buffer, reservation)
  self.cursor = self.cursor + length
  return reservation
end

-- Fill in a reservation with a string
---@param reservation SlotReservation
---@param text string
function StringBuffer:fill(reservation, text)
  if self.reservations[reservation] == nil then
    error("StringBuffer:fill: reservation must be unused")
  end
  self.reservations[reservation] = nil
  self.buffer[reservation.index] = text
end

-- Push a new queue of pointers to write
---@return Deque # real type is Deque<DelayedStringBufferPointerWrite>
function StringBuffer:pushPointerQueue()
  local queue = Deque:new()
  self.pointerQueueStack:pushBack(queue)
  return queue
end

-- Get a queue to add pointers to
---@return Deque # real type is Deque<DelayedStringBufferPointerWrite>
function StringBuffer:getPointerQueue()
  local queue = self.pointerQueueStack:peekBack()
  if queue == nil then
    error("ByteBuffer:getPointerQueue: no pointer queue has been pushed")
  end
  return queue
end

-- Pop a queue of pointers to write
---@return Deque? # real type is Deque<DelayedStringBufferPointerWrite>
function StringBuffer:popPointerQueue()
  return self.pointerQueueStack:popBack()
end

-- Get an existing pointer to a thing
---@param key CacheKey the key for the pointer cache
---@return PointerInfo?
function StringBuffer:getPointer(key)
  local areaPointers = self.knownPointers[key.area]
  if areaPointers == nil then
    return nil
  end
  return tableutil.copy(areaPointers[key.thing])
end

-- Add a pointer to a thing to the buffer
---@param key CacheKey the key for the pointer cache
---@param pointerInfo PointerInfo the pointer info for the thing
function StringBuffer:addPointer(key, pointerInfo)
  local areaPointers = self.knownPointers[key.area]
  if areaPointers == nil then
    areaPointers = {}
    self.knownPointers[key.area] = areaPointers
  end
  if areaPointers[key.thing] ~= nil then
    error("StringBuffer:addPointer: pointer for '" .. key.area .. "," .. tostring(key.thing) .. "' already exists")
  end
  areaPointers[key.thing] = pointerInfo
end

-- Converts the buffer to a string
---@return string
function StringBuffer:toString()
  assert(next(self.reservations) == nil, "StringBuffer:toString: reservations must be empty to convert to string")
  return table.concat(self.buffer)
end

return {
  createStringBuffer = createStringBuffer;
}

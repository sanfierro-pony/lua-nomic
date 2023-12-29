local ffi = require"ffi"
local Deque = require"deque".Deque
local tableutil = require "tableutil"

---@class SliceReservation
---@field offset number offset into buffer where this reservation was added
---@field length number length of the slice reserved

---@class DelayedPointerWrite information about a pointed-to datum that needs to be written later
---@field key CacheKey the key for the pointer cache
---@field default any? the default value for the pointer
---@field reservation SliceReservation the reservation for the pointer to this datum
---@field writer fun(thing: any, buf: ByteBuffer): PointerInfo the function to write the datum, returns the pointer

---@alias CacheKey { area: string, thing: any } pointer cache key, `area` is the struct id, optionally with a list marker; `thing` is the pointed-to datum

---@class ByteBuffer
---@field private buffer ffi.cdata*
---@field private cursor number current offset into buffer
---@field private reservations table<SliceReservation, boolean> reservations, must be empty to convert to string
---@field private pointerQueueStack Deque stack of queues of pointers to write (full type is Deque<Deque<DelayedPointerWrite>>)
---@field private knownPointers table<string, table<any, PointerInfo>> map from cache key to pointer info, however the offset is absolute here
local ByteBuffer = {}
local ByteBuffer_mt = {
  __index = ByteBuffer;
}

local maxiumumBufferSize = math.pow(2, 32) - 1
local initialBufferSize = 1024

-- Creates a new ByteBuffer
---@return ByteBuffer
local function createByteBuffer()
  local self = {
    buffer = ffi.new("uint8_t[?]", initialBufferSize),
    cursor = 0,
    reservations = {},
    pointerQueueStack = Deque:new(),
    knownPointers = {},
    size = initialBufferSize,
  }
  return setmetatable(self, ByteBuffer_mt)
end

function ByteBuffer:length()
  return self.cursor
end

-- Grow the buffer to at least `minimumSize`.
---@param minimumSize number minimum size to grow the buffer to
function ByteBuffer:grow(minimumSize)
  if self.size == maxiumumBufferSize then
    error("ByteBuffer:grow: buffer size cannot exceed " .. maxiumumBufferSize)
  end
  local newsize = math.max(minimumSize, math.min(self.size * 2, maxiumumBufferSize))
  if newsize > maxiumumBufferSize then
    error("ByteBuffer:grow: buffer size cannot exceed " .. maxiumumBufferSize)
  end
  local newbuffer = ffi.new("uint8_t[?]", newsize)
  ffi.copy(newbuffer, self.buffer, self.cursor)
  self.buffer = newbuffer
  self.size = newsize
end

-- Write some bytes into the buffer
---@param length number length of the bytes to write
---@return ffi.cdata* pointer to the slice
function ByteBuffer:write(length)
  local sizeNeeded = self.cursor + length
  if sizeNeeded > self.size then
    self:grow(sizeNeeded)
  end
  local slice = self.buffer + self.cursor
  self.cursor = sizeNeeded
  return slice
end

-- Reserve this slot in the buffer for filling in later
---@param length number length of the slot to reserve
---@return SliceReservation
function ByteBuffer:reserve(length)
  local sizeNeeded = self.cursor + length
  if sizeNeeded > self.size then
    self:grow(sizeNeeded)
  end
  local reservation = {
    offset = self.cursor,
    length = length,
  }
  self.reservations[reservation] = true
  self.cursor = sizeNeeded
  return reservation
end

-- Fill in a reservation with bytes
---@param reservation SliceReservation
---@return ffi.cdata* pointer to the reserved slice
function ByteBuffer:fill(reservation, writer)
  if self.reservations[reservation] == nil then
    error("ByteBuffer:fill: reservation must be unused")
  end
  self.reservations[reservation] = nil
  return self.buffer + reservation.offset
end

-- Push a new queue of pointers to write
---@return Deque # real type is Deque<DelayedPointerWrite>
function ByteBuffer:pushPointerQueue()
  local queue = Deque:new()
  self.pointerQueueStack:pushBack(queue)
  return queue
end

-- Get a queue to add pointers to
---@return Deque # real type is Deque<DelayedPointerWrite>
function ByteBuffer:getPointerQueue()
  local queue = self.pointerQueueStack:peekBack()
  if queue == nil then
    error("ByteBuffer:getPointerQueue: no pointer queue has been pushed")
  end
  return queue
end

-- Pop a queue of pointers to write
---@return Deque? # real type is Deque<DelayedPointerWrite>
function ByteBuffer:popPointerQueue()
  return self.pointerQueueStack:popBack()
end

-- Get an existing pointer to a thing
---@param key CacheKey the key for the pointer cache
---@return PointerInfo?
function ByteBuffer:getPointer(key)
  local areaPointers = self.knownPointers[key.area]
  if areaPointers == nil then
    return nil
  end
  return tableutil.copy(areaPointers[key.thing])
end

-- Add a pointer to a thing to the buffer
---@param key CacheKey the key for the pointer cache
---@param pointerInfo PointerInfo the pointer info for the thing
function ByteBuffer:addPointer(key, pointerInfo)
  local areaPointers = self.knownPointers[key.area]
  if areaPointers == nil then
    areaPointers = {}
    self.knownPointers[key.area] = areaPointers
  end
  if areaPointers[key.thing] ~= nil then
    error("ByteBuffer:addPointer: pointer for '" .. key.area .. "," .. tostring(key.thing) .. "' already exists")
  end
  areaPointers[key.thing] = pointerInfo
end

-- Retrieves the buffer as a string
---@return string
function ByteBuffer:toString()
  assert(next(self.reservations) == nil, "ByteBuffer:buffer: reservations must be empty to convert to string")
  return ffi.string(self.buffer, self.cursor)
end

return {
  createByteBuffer = createByteBuffer;
}

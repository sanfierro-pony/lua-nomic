---@class SlotReservation
---@field offset integer offset into buffer where this reservation was added
---@field length integer length of the reservation

---@class StringBuffer
---@field private buffer (string|SlotReservation)[]
---@field private cursor integer current offset into buffer, in characters
---@field private reservations integer counter for active reservations, must be 0 to convert to string
---@field knownPointers table<any,PointerInfo> map from object to pointer info
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
    reservations = 0,
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
  self.reservations = self.reservations + 1
  local reservation = {
    offset = #self.buffer,
    length = length,
  }
  table.insert(self.buffer, reservation)
  self.cursor = self.cursor + length
  return reservation
end

-- Fill in a reservation with a string
---@param reservation SlotReservation
---@param text string
function StringBuffer:fill(reservation, text)
  assert(self.reservations > 0, "StringBuffer:fill: reservations must be > 0 to fill")
  assert(self.buffer[reservation.offset] == reservation, "StringBuffer:fill: reservation must be in buffer")
  assert(#text == reservation.length, "StringBuffer:fill: text must be same length as reservation")
  self.buffer[reservation.offset] = text
  self.reservations = self.reservations - 1
end

-- Converts the buffer to a string
---@return string
function StringBuffer:toString()
  assert(self.reservations == 0, "StringBuffer:toString: reservations must be 0 to convert to string")
  return table.concat(self.buffer)
end

return {
  createStringBuffer = createStringBuffer;
}

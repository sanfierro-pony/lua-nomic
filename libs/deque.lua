---@class Deque a double-ended queue
---@field private first number index of the first element
---@field private last number index of the last element
---@field private buffer table<number,any> the buffer
local Deque = {}
local Deque_mt = {
  __index = Deque;
}

-- Creates a new Deque
---@return Deque
function Deque:new()
  local self = {
    first = 0,
    last = -1,
    buffer = {},
  }
  return setmetatable(self, Deque_mt)
end

-- Push an element onto the front of the queue
---@param element any
function Deque:pushFront(element)
  self.first = self.first - 1
  self.buffer[self.first] = element
end

-- Push an element onto the back of the queue
---@param element any
function Deque:pushBack(element)
  self.last = self.last + 1
  self.buffer[self.last] = element
end

-- Check if the queue is empty
---@return boolean
function Deque:isEmpty()
  return self.first > self.last
end

-- Pop an element off the front of the queue
---@return any?
function Deque:popFront()
  if self:isEmpty() then
    return nil
  end
  local element = self.buffer[self.first]
  self.buffer[self.first] = nil
  self.first = self.first + 1
  return element
end

-- Pop an element off the back of the queue
---@return any?
function Deque:popBack()
  if self:isEmpty() then
    return nil
  end
  local element = self.buffer[self.last]
  self.buffer[self.last] = nil
  self.last = self.last - 1
  return element
end

-- Peek at the front of the queue
---@return any?
function Deque:peekFront()
  if self:isEmpty() then
    return nil
  end
  return self.buffer[self.first]
end

-- Peek at the back of the queue
---@return any?
function Deque:peekBack()
  if self:isEmpty() then
    return nil
  end
  return self.buffer[self.last]
end

return {
  Deque = Deque;
}

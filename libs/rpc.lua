local encdec = require 'encdec'
local rpcSchema = require 'rpc-schema'
local schema = require 'schema'
local schemaLayout = require 'schema-layout'
local promise = require 'promise'
local u64compat = require 'primitives/primitives-u64'

---@class PriorityQueue
local PriorityQueue = {}
local PriorityQueue_mt = {__index = PriorityQueue}
local PriorityElement = {}
local PriorityElement_mt = {__index = PriorityElement}

function PriorityQueue:new()
  return setmetatable({
    n = 0,
  }, PriorityQueue_mt)
end

function PriorityQueue:pop()
  local elem = self[1]
  local idx = #self
  if idx == 1 then
    self[1] = nil
    return elem[1], elem[2]
  elseif idx == 0 then
    return
  end
  local last = idx - 1
  self[1], self[idx], self[idx][3] = self[idx], nil, 1
  idx = 1
  while true do
    if idx * 2 > last then
      return elem[1], elem[2]
    end
    local nextidx
    if self[idx][1] > self[idx * 2][1] then
      nextidx = idx * 2
    end
    if idx * 2 + 1 < last and self[idx * 2 + 1][1] < self[idx][1] and self[idx * 2 + 1][1] < self[idx * 2][1] then
      nextidx = idx * 2 + 1
    end
    if nextidx then
      self[nextidx], self[idx], self[nextidx][3], self[idx][3] = self[idx], self[nextidx], idx, nextidx
    else
      return elem[1], elem[2]
    end
  end
end

function PriorityQueue:peek()
  local elem = self[1]
  if not elem then return nil end
  return elem[1], elem[2]
end

function PriorityQueue:put(priority, value)
  local elem = PriorityElement:new(priority, value, self)
  local idx = #self + 1
  self[idx] = elem
  local newidx = math.floor(idx / 2)
  while newidx > 0 do
    if self[newidx][1] > self[idx][1] then
      self[newidx], self[idx], self[newidx][3], self[idx][3] = self[idx], self[newidx], idx, newidx
    else
      return elem
    end
  end
  return elem
end

function PriorityElement:new(priority, value, queue)
  return setmetatable({
    [1] = priority,
    [2] = value,
    queue = queue,
  }, PriorityElement_mt)
end

function PriorityElement:remove()
  local idx = self[3]
  local newidx = math.floor(idx / 2)
  while newidx > 0 do
    self.queue[newidx], self.queue[idx], self.queue[newidx][3], self.queue[idx][3] = self.queue[idx], self.queue[newidx],
        idx, newidx
  end
  self.queue:pop()
end

---@class Conn
---@field private messages PriorityQueue
---@field private waiting_writer_coroutine thread?
---@field private waiting_answer_coroutines table
---@field private link table
---@field private imports table
---@field private exports table
---@field private free_export number
---@field private questions table
---@field private free_question number
---@field private answers table
local Conn = {}
local Conn_mt = {__index = Conn}

function Conn:new(link)
  if not link then
    error('link is required')
  end
  local o = setmetatable({
    messages = PriorityQueue:new(),
    waiting_writer_coroutine = nil,
    waiting_answer_coroutines = {},
    link = link,
    imports = {},
    exports = {},
    free_export = 1,
    questions = {},
    free_question = 1,
    answers = {},
  }, Conn_mt)
  o:register_callbacks()
  return o
end

local rpcTest = schema.newschema("rpc-test", "definitions for testing rpc", u64compat"93f592f4bcd0cb61")
local simpleMessage = rpcTest:struct "simpleMessage" "A simple testing message"
{
  schema.text "message" (0) "the message"
}

local function handle_message(self, msg)
  if msg.kind == 'answer' then
    self.answers[msg.questionId] = msg.answer
    local waiters = self.waiting_answer_coroutines[msg.questionId]
    if waiters then
      for i = 1, #waiters do
        xpcall(function()
          coroutine.resume(waiters[i], msg)
        end, function(err)
          print('error in coroutine waiting for ' .. msg.questionId .. ': ',err)
        end)
      end
    end
  elseif msg.kind == 'question' then
    if msg.question.kind == 'bootstrap' then
      self:add_message(0, {
        kind = 'answer',
        questionId = msg.question.id,
        answer = schema.anyPointer:new(
          schemaLayout.layoutstruct(simpleMessage),
          { message = "this is my bootstrap answer :3" }
        ),
      })
    elseif msg.question.kind == 'invoke' then
      error('TODO')
    else
      error('unknown question kind: ' .. msg.question.kind)
    end
  end
end

function Conn:register_callbacks()
  self.link:on_datagram(function(datagram)
    local msg = encdec.decode(rpcSchema.export.message, datagram)
    handle_message(self, msg)
  end)
end

-- TODO dedupe with pagescript.lua
local function withTraceback(f)
  return function(...)
    return xpcall(f, function(err)
      print(debug.traceback(err, 2))
    end, ...)
  end
end

-- Return the thread writing to the link
---@return thread
function Conn:createWriterCoroutine()
  return coroutine.create(withTraceback(function()
    while true do
      local _, msg = self.messages:pop()
      if msg == nil then
        -- waiting for a message
        self.waiting_writer_coroutine = coroutine.running()
        coroutine.yield()
      elseif msg.kind == 'close' then
        self.link:close()
        return
      else
        local datagram = encdec.encode(rpcSchema.export.message, msg)
        self.link:send(datagram)
      end
    end
  end))
end

function Conn:await_answer(questionId)
  if self.answers[questionId] then
    return self.answers[questionId]
  end
  local c = coroutine.running()
  local waiters = self.waiting_answer_coroutines[questionId]
  if not waiters then
    waiters = {}
    self.waiting_answer_coroutines[questionId] = waiters
  end
  waiters[#waiters + 1] = c
  return coroutine.yield()
end

-- Add a message to the queue. May block the current coroutine to send the message.
---@param priority number
---@param msg table
function Conn:add_message(priority, msg)
  local elem = self.messages:put(priority, msg)
  local c = self.waiting_writer_coroutine
  if c then
    self.waiting_writer_coroutine = nil
    coroutine.resume(c)
  end
  return elem
end

function Conn:add_question(question)
  question.id = self.free_question
  question.needs_answer = true -- TODO determine this later and set it to false if it's not needed
  question.submitted = false

  question.entry = self:add_message(0, {
    kind = 'question',
    question = question,
  })
  if self.questions[self.free_question] then
    self.free_question = self.questions[self.free_question]
  else
    self.free_question = self.free_question + 1
  end
  self.questions[question.id] = question
  return question
end

function Conn:call(data)
  local question = self:add_question({
    kind = 'call',
    data = data,
  })
  return promise.Promise:new(self, question.id)
end

function Conn:bootstrap()
  local question = self:add_question({
    kind = 'bootstrap',
  })
  return promise.Promise:new(self, question.id)
end

return {
  Conn = Conn,
  rpcTest = rpcTest,
}

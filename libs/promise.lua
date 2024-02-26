-- Promises are a thing.
---@class Promise<T>
---@field private __state PromiseState internal state
local Promise = {}

---@class PromiseState
---@field conn Conn the connection
---@field value any|nil the value of the promise, or nil if it hasn't been resolved yet
---@field questionId number|nil the question ID that this promise is waiting for
---@field path any[] the path to the promise value from the root, using instructions from the schema
local PromiseState = {}

function PromiseState:new(conn, questionId, path)
  return setmetatable({
    conn = conn,
    value = nil,
    questionId = questionId,
    path = path,
  }, {__index = PromiseState})
end

function PromiseState:resolve()
  if self.value ~= nil then
    return self.value
  else
    local value = self.conn:await_answer(self.questionId)
    -- TODO path resolution
    self.value = value
    -- The question is no longer relevant, make sure we don't reuse it.
    self.questionId = nil
    return value
  end
end

function Promise:new(conn, questionId)
  return setmetatable({
    __state = PromiseState:new(conn, questionId, {}),
  }, {__index = Promise})
end

-- Await an object. If a promise, wait for it to resolve, then return the result, or call `error` with the error.
-- Otherwise, return the object.
---@generic T
---@param object Promise<T>|T the object to await
---@return T
local function await(object)
  if type(object) == "table" and getmetatable(object).__index == Promise then
    return object.__state:resolve()
  else
    return object
  end
end

return {
  Promise = Promise,
  await = await,
}

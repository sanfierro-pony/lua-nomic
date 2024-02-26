-- Copy the given table.
---@generic T :table|nil
---@param t `T` the table to copy
---@return T # the copy
local function copy(t)
  if t == nil then
    return nil
  end
  local new = {}
  for k, v in pairs(t) do
    new[k] = v
  end
  return new
end

-- Copy and sort the given table.
---@generic T :table|nil
---@param t `T` the table to copy and sort
---@param comp fun(a: any, b: any):boolean? comparison function
---@return T # the sorted copy
local function sortedCopy(t, comp)
  if t == nil then
    return nil
  end
  -- TODO make more efficient by doing the insert sorted?
  local new = copy(t)
  table.sort(new, comp)
  return new
end

-- Clear the given table.
---@param t table the table to clear
local function clear(t)
  for k in pairs(t) do
    t[k] = nil
  end
end

return {
  copy = copy,
  sortedCopy = sortedCopy,
  clear = clear,
}

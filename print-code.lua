-- Print a code string with line numbers for easy debugging.
---@param code string the code to print
---@param start number|integer|nil the line number to start at
local function printCode(code, start)
  if code[#code] ~= "\n" then
    code = code .. "\n"
  end
  if start == nil then
    start = 1
  end
  local lines = {}
  for line in code:gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  local max = #tostring(#lines) + start - 1
  for i, line in ipairs(lines) do
    local prefix = tostring(i + start - 1)
    while #prefix < max do
      prefix = " " .. prefix
    end
    print(prefix .. " " .. line)
  end
end

return {
  printCode = printCode,
}

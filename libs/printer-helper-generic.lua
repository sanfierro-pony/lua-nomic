local function escapeUnprintable(value)
  return value:gsub("[^%g ]", function(c)
    return string.format("\\%03d", c:byte())
  end)
end

local function appendToString(builder, value)
  builder[#builder + 1] = escapeUnprintable(tostring(value))
end

return {
  escapeUnprintable = escapeUnprintable,
  appendToString = appendToString,
}


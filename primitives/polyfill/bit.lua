local function bxor(a, b)
  return a ~ b
end
local function band(a, b)
  return a & b
end

return {
  bxor = bxor,
  band = band,
}

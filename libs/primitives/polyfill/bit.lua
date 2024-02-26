local function bor(a, b)
  return a | b
end
local function band(a, b)
  return a & b
end
local function bxor(a, b)
  return a ~ b
end
local function lshift(a, b)
  return a << b
end
local function rshift(a, b)
  return a >> b
end

return {
  bor = bor,
  bxor = bxor,
  band = band,
  lshift = lshift,
  rshift = rshift,
  arshift = jshooks.arshift
}

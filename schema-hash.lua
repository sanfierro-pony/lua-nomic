local sha2 = require"libs.sha2"

local uint32_max = math.pow(2, 32)
local hashFunc = sha2.sha256
local hashBytes = 8
-- we truncate the hash to this many chars
-- should be <= size of hashFunc's output
local hashHexChars = hashBytes * 2

-- generates a random hash
-- math.randomseed should be called before this is used for the first time
local function randomHash()
  return string.sub(hashFunc(tostring(math.random(uint32_max)) .. " " .. tostring(math.random(uint32_max))), 1, hashHexChars)
end

-- hash of every item in input sequence
local function hash(t)
  -- PERF: could change interface in sha2.lua to allow passing multiple buffers in in sequence
  -- so don't need to concat into one big string here? slight improvement
  local input = ""
  for i, v in ipairs(t) do
    if type(v) == 'table' then
      error(i, v, "unexpected table in inputs")
    end
    input = input .. string.char(i % 256) .. tostring(v)
  end
  return string.sub(hashFunc(input), 1, hashHexChars)
end

if not ... then
  math.randomseed(os.time())
  print(hashRandom())
  local testTable = {"test", 1234, "CAFEBABE"}
  print(hashSequence(testTable))
end

return {
  hash = hash,
  randomHash = randomHash,
}

---@meta typedef.jshooks
-- Hooks added by us in `index.lua` JS

jshooks = {}

-- Convert a Lua/Fengari string into a Uint8Array userdata at no cost
---@param string string the string
---@return userdata buffer the Uint8Array userdata
function jshooks.stringToByteBuffer(string) error("implementation not here") end

-- Convert a JS ArrayBuffer into a Lua/Fengari string at potentially no cost
---@param arrayBuffer userdata the ArrayBuffer
---@return string string the string
function jshooks.arrayBufferToString(arrayBuffer) error("implementation not here") end

-- Perform an arithmetic right shift on a number
---@param a number the number to shift
---@param b number the number of bits to shift
function jshooks.arshift(a, b) error("implementation not here") end

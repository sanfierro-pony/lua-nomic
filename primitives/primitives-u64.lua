-- u64 compatibility module, using bint on fengari and ULLs on LuaJIT

local canffi = pcall(require, 'ffi')

return canffi and require 'primitives.u64-ull' or require 'primitives.u64-bint'

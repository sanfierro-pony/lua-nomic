local hashing = require "schema-hash"
local u64compat = require "primitives.primitives-u64"

local newstruct, newenum, newunion, newvariant, newinterface

local defer_field_def, defer_union_def, defer_variant_def

local is_schematype

local primitive_schema_hash = "ea381865dd61e2d8"

local struct_mt = {
  __index = {
    addfield = function(self, name, stype, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if not is_schematype(stype) then
        if p then
          p(stype)
        end
        error("the type of field " .. name .. " must be a schema type, got " .. type(stype) .. " " .. tostring(stype))
      end
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end

      local field = {kind = "field", name = name, type = stype, docstring = docstring, id = id}
      self.fields[#self.fields + 1] = field
      self.field_by_name[name] = field
    end,
    addunion = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      -- this id reuse/collision is benign because one is a field and the other is an enum type, and both are in the same schema, and neither is a top level export
      local enum = newenum(name, docstring, id)
      self:addfield(name, enum, docstring, id)
      return newunion(self, #self.fields, enum)
    end,
    addunionfield = function(self, name, stype, descriminator, descriminant, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      assert(is_schematype(stype), "the type of the field must be a schema type")
      assert(type(descriminator) == "number", "union specifier must be present")
      assert(type(descriminant) == "number", "union descriminant must be present")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end

      local field = {kind = "union", name = name, type = stype, docstring = docstring, descriminator = descriminator, descriminant = descriminant, id = id}
      self.fields[#self.fields + 1] = field
      self.field_by_name[name] = field
    end,
    define = function(self, def)
      local list = {}
      local context = {val=self}
      for k, v in ipairs(def) do
        v:insertall(list, context)
      end
      table.sort(list, function(a, b) return a.order < b.order end)
      for k, v in ipairs(list) do
        v:execute()
      end
    end,
  },
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

function newstruct(name, docstring, id)
  if type(name) ~= "string" then
    error "the name of the struct must be a string"
  end
  if docstring ~= nil and type(docstring) ~= "string" then
    error "the docstring must be a string if present"
  end
  if not u64compat.isU64(id) then
    error "id must be a u64"
  end
  local self = {
    name = name,
    docstring = docstring,
    components = {},
    count = 0,
    id = id,
    kind = 'struct',
    fields = {},
    field_by_name = {},
  }
  return setmetatable(self, struct_mt)
end

local union_mt = {
  __index = {
    addvariant = function(self, name, docstring, id)
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      assert(type(name) == "string", "name must be a string")
      assert(self.descpos ~= nil, "descpos must be set")
      if not u64compat.isU64(id) then
        error "id must be a u64"
      end
      local descval = self.enum:addvariant(name, docstring, id)
      assert(descval ~= nil, "descval must be set")
      return newvariant(self, self.descpos, descval)
    end
  },
  __call = function(self, ...) return defer_union_def(self, ...) end
}

function newunion(parent, descpos, enum)
  assert(type(descpos) == "number", "descpos must be a number")
  local self = {
    parent = parent,
    descpos = descpos,
    enum = enum
  }
  return setmetatable(self, union_mt)
end

local variant_mt = {
  __index = {
    addfield = function(self, name, stype, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if not is_schematype(stype) then
        if p then
          p(stype)
        end
        error("the type of field " .. name .. " must be a schema type, got " .. type(stype) .. " " .. tostring(stype))
      end
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if self.descpos == nil or self.descval == nil then
        error "BUG: missing descpos or descval?"
      end
      return (self.parent.parent:addunionfield(name, stype, self.descpos, self.descval, docstring, id))
    end,
    addunion = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      local enum = newenum(name, docstring, id)
      self:addfield(name, enum, docstring, id)
      return newunion(self, #self.parent.parent.fields, enum)
    end,
    addunionfield = function(self, name, stype, descpos, descval, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      assert(is_schematype(stype), "the type of the field must be a schema type")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      return self.parent.parent:addunionfield(name, stype, descpos, descval, docstring, id)
    end,
  },
  __call = function(self, ...) return defer_variant_def(self, ...) end
}

function newvariant(parent, descpos, descval, id)
  assert(descpos ~= nil, "descpos must be set")
  assert(descval ~= nil, "descval must be set")
  if id ~= nil and not u64compat.isU64(id) then
    error "id must be a u64"
  end
  local self = {
    parent = parent,
    -- name = name,
    -- docstring = docstring,
    id = id,
    descpos = descpos,
    descval = descval,
  }
  return setmetatable(self, variant_mt)
end

local enum_mt = {
  __index = {
    addvariant = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      if not u64compat.isU64(id) then
        error "id must be a u64"
      end
      local variantindex = #self.variants -- zero indexed, first variant needs to have index 0 to match capnp
      self.variants[#self.variants + 1] = {name = name, docstring = docstring, id = id, variantindex = variantindex}
      return variantindex
    end
  },
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

function newenum(name, docstring, id)
  if id ~= nil and not u64compat.isU64(id) then
    error "id must be a u64"
  end
  local self = {
    name = name,
    docstring = docstring,
    id = id,
    kind = 'enum',
    variants = {},
  }
  return setmetatable(self, enum_mt)
end

local text_mt = {
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

local newtype_mt = {
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

function newnewtype(name, basetype, docstring, id)
  if not u64compat.isU64(id) then
    error "id must be a u64"
  end
  local self = {
    name = name,
    kind = "newtype",
    basetype = basetype,
    docstring = docstring,
    id = id,
  }
  return setmetatable(self, newtype_mt)
end

local interface_mt = {
  __index = {
    addmethod = function(self, name, docstring, args, results, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      if not u64compat.isU64(id) then
        error "id must be a u64"
      end
      -- TODO
    end
  },
  __call = function(self, ...) return defer_field_def(self, ...) end
}

function newinterface(name, docstring, id)
  assert(type(name) == "string", "the name of the field must be a string")
  if docstring ~= nil and type(docstring) ~= "string" then
    error "the docstring must be a string if present"
  end
  assert(id, "when creating a type outside the context of a schema it must have an id specified")
  if not u64compat.isU64(id) then
    error "id must be a u64"
  end
  local self = {
    name = name,
    kind = "interface",
    docstring = docstring,
    id = id
  }
  return setmetatable(self, interface_mt)
end

local add_struct_mt = {
  __call = function(self, val)
    if not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif type(val) == "table" then
      local struct = self.context:addstruct(self.name, self.docstring)
      struct:define(val)
      return struct
    end
    return self
  end
}

local add_enum_mt = {
  __call = function(self, val)
    if not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif type(val) == "table" then
      local enum = self.context:addenum(self.name, self.docstring)
      for i, v in ipairs(val) do
        enum:addvariant(v)
      end
      return enum
    end
    return self
  end
}

local add_interface_mt = {
  __call = function(self, val)
    if not self.name then
      assert(type(val) == "string", "the name of the interface must be a string")
      self.name = val
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif type(val) == "table" then
      local interface = self.context:addinterface(self.name, self.docstring)
      for i, v in ipairs(val) do
        v.order = i - 1
        interface:addmethod(v.name, v.docstring, v.args, v.results, v.id)
      end
      return interface
    end
    return self
  end
}

local schema_mt = {
  __index = {
    struct = function(self, name)
      assert(type(name) == "string", "the name of the struct must be a string")
      return setmetatable({context = self, name = name}, add_struct_mt)
    end,
    enum = function(self, name)
      assert(type(name) == "string", "the name of the enum must be a string")
      return setmetatable({context = self, name = name}, add_enum_mt)
    end,
    interface = function(self, name)
      return setmetatable({context = self}, add_interface_mt)(name)
    end,
    addstruct = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      local struct = newstruct(name, docstring, id)
      self.exports[#self.exports + 1] = struct
      self.export[name] = struct
      return struct
    end,
    addenum = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      local t = newenum(name, docstring, id)
      self.exports[#self.exports + 1] = t
      self.export[name] = t
      return t
    end,
    addinterface = function(self, name, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      local struct = newinterface(name, docstring, id)
      self.exports[#self.exports + 1] = struct
      self.export[name] = struct
      return struct
    end,
    newtype = function(self, name, basetype, docstring, id)
      assert(type(name) == "string", "the name of the field must be a string")
      if docstring ~= nil and type(docstring) ~= "string" then
        error "the docstring must be a string if present"
      end
      if not id then
        id = u64compat(hashing.hash{self.id, name})
      end
      local t = newnewtype(name, basetype, docstring, id)
      self.exports[#self.exports + 1] = t
      self.export[name] = t
      return t
    end,
  }
}

local defer_field_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      assert(self.order ~= nil, "fields must have an evolution order")
      list[#list + 1] = self
    end,
    execute = function(self)
      self.context.val:addfield(self.name, self.type, self.docstring, self.id)
    end
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a field declaration after the type must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order and type(val) == "number" then
      self.order = val
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    else
      error "unknown component of field declaration"
    end
    return self
  end
}

function defer_field_def(stype, name)
  return setmetatable({type = stype}, defer_field_mt)(name)
end

local defer_union_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      self.nextcontext = {}
      list[#list + 1] = self
      for i, v in ipairs(self.children) do
        v:insertall(list, self.nextcontext)
      end
    end,
    execute = function(self)
      self.nextcontext.val = self.context.val:addunion(self.name, self.docstring, self.id)
    end,
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a union declaration after `union` must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order then
      if type(val) ~= "number" then
        error "the second thing in a union declaration after `union` must be the evolution order which must be a number"
      else
        self.order = val
      end
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif not self.children and type(val) == "table" then
      self.children = val
    else
      error "unknown component of union declaration"
    end
    return self
  end
}

local function union(name)
  return setmetatable({kind="union"}, defer_union_mt)(name)
end

local defer_variant_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      self.nextcontext = {}
      list[#list + 1] = self
      for i, v in ipairs(self.children) do
        v:insertall(list, self.nextcontext)
      end
    end,
    execute = function(self)
      self.nextcontext.val = self.context.val:addvariant(self.name, self.docstring, self.id)
    end,
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a variant declaration after `variant` must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order then
      if type(val) ~= "number" then
        error "the second thing in a variant declaration after `variant` must be the evolution order which must be a number"
      else
        self.order = val
      end
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif not self.children and type(val) == "table" then
      self.children = val
    else
      error "unknown component of variant declaration"
    end
    return self
  end
}

local defer_method_mt = {
  __index = {
    insertall = function(self, list, context)
      self.context = context
      assert(self.order ~= nil, "fields must have an evolution order")
      list[#list + 1] = self
    end,
    execute = function(self)
      self.context.val:addfield(self.name, self.type, self.docstring, self.id)
    end,
    to = function(self, results)
      self.results = results
      return self
    end,
  },
  __call = function(self, val)
    if not self.name then
      if type(val) ~= "string" then
        error "the first thing in a method declaration after `variant` must be the name which must be a string"
      else
        self.name = val
      end
    elseif not self.order then
      if type(val) ~= "number" then
        error "the second thing in a method declaration after `variant` must be the evolution order which must be a number"
      else
        self.order = val
      end
    elseif not self.docstring and type(val) == "string" then
      self.docstring = val
    elseif not self.children and type(val) == "table" then
      self.parameters = val
    else
      error "unknown component of method declaration"
    end
    return self
  end
}

local function variant(name)
  return setmetatable({}, defer_variant_mt)(name)
end

local function struct(name)
  return setmetatable({}, struct_mt)(name)
end

local function text(name)
  -- FIXME: what should stype for text be
  return setmetatable({kind="text"}, text_mt)(name)
end

local function enum(name)
  return setmetatable({}, enum_mt)(name)
end

local function method(name)
  return setmetatable({}, defer_method_mt)(name)
end

function is_schematype(stype)
  return type(stype) == "table" and stype.kind
end

local function declare()
  return {}
end

local function newschema(name, docstring, id)
  assert(type(name) == "string", "name must be a string")
  if not u64compat.isU64(id) then
    error "id must be a u64"
  end
  local init = {
    name = name,
    docstring = docstring,
    id = id,
    exports = {},
    export = {},
  }
  return setmetatable(init, schema_mt)
end

local primitive_mt = {
  __index = {
    kind = "primitive",
  },
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

local function newprimitive(name, bitwidthln)
  return setmetatable(
    {
      id = u64compat(hashing.hash{primitive_schema_hash, name}),
      name = name,
      bitwidthln = bitwidthln,
    }, primitive_mt)
end

local bound_generic_mt = {
  __call = function(self, ...)
    return defer_field_def(self, ...)
  end
}

local generic_mt = {
  __call = function(self, ...)
    local args = { ... }
    assert(#args > 0, "must have at least one arg to generic type")
    for i, v in ipairs(args) do
      if not is_schematype(v) then
        error("generic type args must all be schematypes, got " .. type(v))
      end
    end
    return setmetatable({kind = self.kind, args = args}, bound_generic_mt)
  end
}

local function newgeneric(kind)
  return setmetatable({kind=kind}, generic_mt)
end

local primitives = {}

return {
  list = newgeneric("list"),
  maybe = newgeneric("maybe"),
  text = text,
  union = union,
  enum = enum,
  method = method,
  variant = variant,
  newschema = newschema,
  primitives = primitives,
  void = newprimitive("void", nil),
  bottom = newprimitive("bottom", nil),
  bool = newprimitive("bool", 0),
  u8 = newprimitive("u8", 3),
  i8 = newprimitive("i8", 3),
  u16 = newprimitive("u16", 4),
  i16 = newprimitive("i16", 4),
  u32 = newprimitive("u32", 5),
  i32 = newprimitive("i32", 5),
  u64 = newprimitive("u64", 6),
  i64 = newprimitive("i64", 6),
  float = newprimitive("float", 5),
  double = newprimitive("double", 6),
}

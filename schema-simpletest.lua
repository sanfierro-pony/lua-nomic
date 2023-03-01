-- parse from schema, save to buf, read from buf, compare
--
local schema = require 'schema'

local text, union, enum, variant = schema.text, schema.union, schema.enum, schema.variant
local u16, u64, list = schema.u16, schema.u64, schema.list

local S = schema.newschema("schema", "the schema for saving and transmitting schemas", "a3329f307fcd88f6")

local stype = S:addstruct("type", "the type that a field may have")
local struct = S:addstruct("struct", "a structure containing named fields")
local field = S:addstruct("field", "something in a structure where data can be stored")
local senum = S:addstruct("enum", "a set of meaningful names which get stored as a single number")

local typeid = S:newtype("typeid", u64)
local schemaid = S:newtype("schemaid", u64)
local fieldid = S:newtype("fieldid", u64)

field:define {
  text "name" (0) "the name of the field as it should be used to generate the keys of the table";
  stype "type" (1) "The type the field is stored as";
  text "docstring" (3) "expanded documentation describing the usage and meaning of the field";
  union "kind" (2) "what kind of field it is, whether it is always present, whether it is part of an enum"
  {
    variant "field" (4) "This field is just an ordinary field that is always accessible" {};
    variant "union" (5) "The field is part of a union, only accessible when the descriminator has a particular value"
    {
      -- support your local union
      u16 "descriminator" (6) "which component of the struct holds the discriminator for this union field";
      u16 "descriminant" (7) "the value the descriminator field must take for this field to be valid.";
    };
  };
  fieldid "id" (8) "The unique key for a field automatically derived from the initial name and the struct to verify forward compatibility. The collision domain for this key is within the parent struct.";
}

local json = require "json"
print(json.stringify(field))
p(field)

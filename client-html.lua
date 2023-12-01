
---@module "client-dom"
local dom = ...

---comment
---@param tag string
---@return fun(desc: UIDesc): UINode
local function b(tag)
    return function(desc)
        return dom.new_node(tag, desc)
    end
end

---@param name string
---@return fun(value: string|boolean|integer): UIAttribute
local function attr(name)
    return function(value)
        return dom.new_attribute(name, value)
    end
end

---@param name string
---@return fun(value: function): UIHandler
local function handler(name)
    return function(value)
        return dom.new_handler(name, value)
    end
end

---@param name string
---@return fun(value: string): UIStyle
local function style(name)
    return function(value)
        return dom.new_simple_style(name, value)
    end
end

local elems = {
    p = b"p",
    span = b"span",
    div = b"div",
    button = b"button",
}

local attrs = {
    contentEditable = attr"contenteditable",
}

local handlers = {
    ---@type fun(value: fun()): UIHandler
    onClick = handler"click",
}

local styles = {
    bgColor = style"background-color",
    verticalAlign = style"vertical-align",
}

return {
    elems = elems,
    attrs = attrs,
    handlers = handlers,
    styles = styles,
}

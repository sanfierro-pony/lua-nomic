return function (module_create, sources)
  local function getCanonicalName(moduleName, providedModules)
    for _, prefix in ipairs{"", "libs/"} do
      local name = prefix .. moduleName
      if sources[name] or providedModules[name] ~= nil then
        return name
      end
    end
    error("module not found: " .. moduleName)
  end

  local function loadModule(mainName, permittedNames, providedModules)
    if type(permittedNames) == "table" then
      local permittedNamesTable = permittedNames
      permittedNames = function (canonicalName)
        return permittedNamesTable[canonicalName]
      end
    elseif type(permittedNames) ~= "function" then
      error("permittedNames must be a table or function")
    end

    local canonicalMainName = getCanonicalName(mainName, {})

    local moduleLoaderCache = {}
    local function requireUnchecked(canonicalName)
      if moduleLoaderCache[canonicalName] then
        return moduleLoaderCache[canonicalName]
      end
      local module = module_create("return function(require) " .. sources[canonicalName] .. "\nend", canonicalName)()
      moduleLoaderCache[canonicalName] = module
      return module
    end

    local module = requireUnchecked(canonicalMainName)

    local moduleCache = {}
    providedModules = providedModules or {}
    local function require(moduleName)
      local canonicalName = getCanonicalName(moduleName, providedModules)
      if providedModules[canonicalName] then
        return providedModules[canonicalName]
      end
      if not permittedNames(canonicalName) then
        error("module not permitted: " .. canonicalName)
      end
      if moduleCache[canonicalName] == nil then
        moduleCache[canonicalName] = requireUnchecked(canonicalName)(require)
      end
      return moduleCache[canonicalName]
    end

    return module(require)
  end

  return {
    loadModule = loadModule
  }
end

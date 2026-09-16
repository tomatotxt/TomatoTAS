-- Configure getgenv().TomatoTASConfig before executing this file.
local env = getgenv()
local supplied = env.TomatoTASConfig or {}
local config = table.clone(supplied)
config.Owner = config.Owner or "tomatotxt"
config.Repo = config.Repo or "TomatoTAS"
config.Branch = config.Branch or "live"
assert(type(config.Repo) == "string" and config.Repo ~= "" and config.Repo ~= "TBD",
    "[TomatoTAS] Set getgenv().TomatoTASConfig.Repo to your GitHub repository name")
for _, key in ipairs({"Owner", "Repo", "Branch"}) do
    assert(type(config[key]) == "string" and config[key]:match("^[%w_.%-/]+$")
        and not config[key]:find("..", 1, true), "Invalid GitHub " .. key)
end
config.Directory = config.Directory or "TomatoTAS"
config.Timeout = config.Timeout or 45
config.BatchSize = config.BatchSize or 100
config.MaxNodes = config.MaxNodes or 1000000
config.MaxFileBytes = config.MaxFileBytes or 268435456
config.File = config.File or "run"
for _, key in ipairs({"Timeout", "BatchSize", "MaxNodes", "MaxFileBytes"}) do
    assert(type(config[key]) == "number" and config[key] > 0 and config[key] < math.huge,
        "Invalid numeric setting: " .. key)
end
assert(config.BatchSize%1==0 and config.MaxNodes%1==0 and config.MaxFileBytes%1==0 and config.MaxFileBytes>=4096,
    "BatchSize/MaxNodes/MaxFileBytes must be positive integers; MaxFileBytes must be >=4096")
local base = "https://raw.githubusercontent.com/" .. config.Owner .. "/" .. config.Repo .. "/" .. config.Branch .. "/"
local cache, loading = {}, {}
local function import(name)
    assert(name:match("^[%w_/]+$") and not name:find("..", 1, true), "Invalid module name")
    if cache[name] ~= nil then return cache[name] end
    assert(not loading[name], "Circular module dependency: " .. name)
    loading[name] = true
    local ok, result = xpcall(function()
        local source = game:HttpGet(base .. "src/" .. name .. ".luau", true)
        assert(type(source) == "string" and #source > 0 and not source:match("^404:"), "Missing module: " .. name)
        local chunk, reason = loadstring(source, "@TomatoTAS/" .. name)
        assert(chunk, reason)
        local factory = chunk()
        assert(type(factory) == "function", "Invalid module factory: " .. name)
        local value = factory(import, config)
        assert(value ~= nil, "Module returned nil: " .. name)
        return value
    end, debug.traceback)
    loading[name] = nil
    assert(ok, result)
    cache[name] = result
    return result
end
local App = import("App")
if env.TomatoTAS then env.TomatoTAS:Destroy() end
local app = App.new()
env.TomatoTAS = app
print("[TomatoTAS] Ready. F1 prepare live map; F2 record/pause; F3 play/pause; F8 clone. See README for all controls.")
return app

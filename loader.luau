-- Configure getgenv().TomatoTASConfig before executing this file.
local env = getgenv()
local supplied = env.TomatoTASConfig or {}
assert(type(supplied)=="table", "[TomatoTAS] TomatoTASConfig must be a table")
local config = table.clone(supplied)
config.Owner = config.Owner or "tomatotxt"
config.Repo = config.Repo or "TomatoTAS"
config.Branch = config.Branch or "live"
assert(type(config.Repo) == "string" and config.Repo ~= "" and config.Repo ~= "TBD",
    "[TomatoTAS] Set getgenv().TomatoTASConfig.Repo to your GitHub repository name")
assert(type(config.Owner)=="string" and config.Owner:match("^[%w%-]+$"),"Invalid GitHub Owner")
assert(config.Repo:match("^[%w_.%-]+$") and config.Repo~="." and config.Repo~="..", "Invalid GitHub Repo")
assert(type(config.Branch)=="string" and config.Branch:match("^[%w_.%-/]+$")
    and not config.Branch:find("..",1,true) and not config.Branch:find("//",1,true)
    and config.Branch:sub(1,1)~="/" and config.Branch:sub(-1)~="/", "Invalid GitHub Branch")
config.Directory = config.Directory or "TomatoTAS"
config.Timeout = config.Timeout or 45
config.BatchSize = config.BatchSize or 100
config.MaxNodes = config.MaxNodes or 1000000
config.MaxFileBytes = config.MaxFileBytes or 268435456
config.File = config.File or "run"
assert(config.AutoPrepare==nil or type(config.AutoPrepare)=="boolean", "AutoPrepare must be a boolean")
assert(type(config.Directory)=="string" and config.Directory:match("^[%w_%-]+$"),
    "Directory must be a simple relative folder name")
assert(type(config.File)=="string" and #config.File>0 and #config.File<=100 and config.File:match("^[%w_%-]+$"),
    "File must be a simple run name without an extension")
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
-- Finish constructing the replacement before unloading an already running
-- session. A failed initialization must leave its recording and controls alive.
App.Validate()
local app = App.new()
local previous = env.TomatoTAS
if previous then
    local ok, err = pcall(function() previous:Destroy() end)
    if not ok then
        pcall(function() app:Destroy() end)
        error("[TomatoTAS] Could not replace the previous session: " .. tostring(err), 0)
    end
end
env.TomatoTAS = app
app:StartAutoPrepare()
if config.GUI~=false then
    local ok,err=pcall(function()
        local panel=import("ui/Panel").new(app)
        if app.scope.dead then panel:Destroy()
        else app.scope:Add(panel); app.gui=panel end
    end)
    if not ok then warn("[TomatoTAS] GUI unavailable; hotkeys remain active: "..tostring(err)) end
end
print("[TomatoTAS] Ready. Map preparation is automatic; F1 retries it. F2 record/pause; F3 play/pause; F8 clone.")
return app

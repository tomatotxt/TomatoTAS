-- scripts/check.ps1 passes the actual loader source as a program argument.
local source=...
assert(type(source)=="string" and #source>0,"Run this suite through scripts/check.ps1 (it supplies loader source)")
local function run(config,fixtures,options)
    options=options or {}
    local requests,events={},{}
    local previous={Destroy=function()
        table.insert(events,"destroy")
        if options.destroyError then error("old cleanup failed") end
    end}
    local nextApp={name="new",scope={Add=function() end},Destroy=function() table.insert(events,"discard") end}
    local shared={TomatoTASConfig=config,TomatoTAS=previous}
    local environment
    environment=setmetatable({
        getgenv=function() return shared end,
        game={HttpGet=function(_,url,nocache)
            assert(nocache==true)
            table.insert(requests,url)
            local name=url:match("/src/(.+)%.luau$")
            local body=fixtures[name]
            if name=="ui/Panel" and body==nil then body="return function() return {new=function() return {Destroy=function() end} end} end" end
            assert(body,"HTTP 404: "..url)
            return body
        end},
        print=function() end,
        warn=function() end,
        onValidate=function()
            table.insert(events,"validate")
            if options.invalid then error("capability validation failed") end
        end,
        onNew=function()
            table.insert(events,"new")
            if options.newError then error("initialization failed") end
            return nextApp
        end,
        inspectConfig=options.inspectConfig or function() end,
    },{__index=getfenv()})
    environment.loadstring=function(body,name)
        local chunk,err=loadstring(body,name)
        if chunk then setfenv(chunk,environment) end
        return chunk,err
    end
    local chunk=assert(loadstring(source,"@actual-loader"))
    setfenv(chunk,environment)
    local ok,result=pcall(chunk)
    return {ok=ok,result=result,requests=requests,events=events,shared=shared,previous=previous,nextApp=nextApp}
end
local appSource="return function(import,config) inspectConfig(config); return {Validate=onValidate,new=onNew} end"
local count=0
local function test(name,fn) fn(); count+=1; print("PASS "..name) end
test("loader defaults target TomatoTAS live",function()
    local r=run(nil,{App=appSource})
    assert(r.ok and r.result==r.nextApp and r.shared.TomatoTAS==r.nextApp)
    assert(r.requests[1]=="https://raw.githubusercontent.com/tomatotxt/TomatoTAS/live/src/App.luau")
    assert(table.concat(r.events,",")=="validate,new,destroy")
end)
test("owner repo and branch are shared by every cached module",function()
    local config={Owner="other",Repo="other-repo",Branch="feature/example",Timeout=12}
    local fixture={App=[[return function(import,config)
        inspectConfig(config)
        assert(import("core/Example")==import("core/Example"))
        return {Validate=onValidate,new=onNew}
    end]], ["core/Example"]="return function() return {} end"}
    local r=run(config,fixture,{inspectConfig=function(snapshot) assert(snapshot~=config and snapshot.Timeout==12) end})
    assert(r.ok and #r.requests==3)
    local prefix="https://raw.githubusercontent.com/other/other-repo/feature/example/src/"
    for _,url in ipairs(r.requests) do assert(url:sub(1,#prefix)==prefix) end
end)
test("validation failure preserves the existing session",function()
    local r=run(nil,{App=appSource},{invalid=true})
    assert(not r.ok and r.shared.TomatoTAS==r.previous and table.concat(r.events,",")=="validate")
end)
test("constructor failure preserves the existing session",function()
    local r=run(nil,{App=appSource},{newError=true})
    assert(not r.ok and r.shared.TomatoTAS==r.previous)
    assert(table.concat(r.events,",")=="validate,new")
end)
test("handoff failure destroys the unused replacement",function()
    local r=run(nil,{App=appSource},{destroyError=true})
    assert(not r.ok and r.shared.TomatoTAS==r.previous)
    assert(table.concat(r.events,",")=="validate,new,destroy,discard")
    assert(tostring(r.result):find("Could not replace the previous session",1,true))
end)
test("missing and invalid module responses preserve the existing session",function()
    for _,fixtures in ipairs({{}, {App="404: Not Found"}, {App="<html>unavailable</html>"},
        {App="return {}"},{App="return function() return nil end"}}) do
        local r=run(nil,fixtures)
        assert(not r.ok and r.shared.TomatoTAS==r.previous and #r.events==0)
    end
end)
test("circular module imports fail clearly without unloading",function()
    local r=run(nil,{App='return function(import) return import("core/A") end',
        ["core/A"]='return function(import) return import("App") end'})
    assert(not r.ok and tostring(r.result):find("Circular module dependency",1,true))
    assert(#r.requests==2 and #r.events==0)
end)
test("invalid configuration fails before any HTTP request",function()
    for _,config in ipairs({"bad", {Owner="a/b"},{Repo=".."},{Repo="a/b"},{Branch="../main"},
        {Branch="/live"},{Branch="live//bad"},{Timeout=0},{BatchSize=0.5},{MaxFileBytes=100},
        {Directory="../elsewhere"},{Directory=12},{File="a/b"},{File="run.fe2tomatas"}}) do
        local r=run(config,{App=appSource})
        assert(not r.ok and #r.requests==0 and #r.events==0)
    end
end)
test("invalid module paths never issue an extra HTTP request",function()
    local r=run(nil,{App='return function(import) return import("../outside") end'})
    assert(not r.ok and #r.requests==1 and #r.events==0)
end)
test("GUI is optional and presentation failure preserves the engine",function()
    local headless=run({GUI=false},{App=appSource})
    assert(headless.ok and #headless.requests==1 and not headless.nextApp.gui)
    local broken=run(nil,{App=appSource,["ui/Panel"]="return function() error('GUI failed') end"})
    assert(broken.ok and broken.shared.TomatoTAS==broken.nextApp)
end)
print("Loader tests passed: "..count)

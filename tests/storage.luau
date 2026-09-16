local factory=require("../src/runtime/Storage")
local files,folders,warnings={},{},{}
local fault
local Codec={
    encode=function(tree) return "valid:"..tree.value end,
    decode=function(data) assert(data:sub(1,6)=="valid:","bad data"); return {value=data:sub(7)} end,
    validate=function(data) assert(data:sub(1,6)=="valid:","bad data"); return true end,
}
local environment=setmetatable({
    isfile=function(path) return files[path]~=nil end,
    readfile=function(path) assert(files[path],"missing file"); return files[path] end,
    writefile=function(path,bytes)
        if fault and fault(path,bytes) then return end
        files[path]=bytes
    end,
    delfile=function(path)
        if fault and fault(path,nil) then return end
        files[path]=nil
    end,
    isfolder=function(path) return folders[path]==true end,
    makefolder=function(path) folders[path]=true end,
    listfiles=function(path)
        local result={}
        for name in pairs(files) do if name:sub(1,#path+1)==path.."/" then table.insert(result,name) end end
        return result
    end,
    warn=function(message) table.insert(warnings,message) end,
},{__index=getfenv()})
setfenv(factory,environment)
local Storage=factory(function(name) assert(name=="core/Codec"); return Codec end,{Directory="TomatoTAS"})
local target="TomatoTAS/run.fe2tomatas"
local count=0
local function test(name,fn)
    files,folders,warnings={},{},{}
    fault=nil
    fn(); count+=1; print("PASS "..name)
end
local function save(value) return Storage.save("run",{value=value}) end
local function fails(fn) assert(not pcall(fn),"Expected rejection") end
test("new and replacement saves retain a verified backup",function()
    local path,size=save("first")
    assert(path==target and size==11 and folders.TomatoTAS)
    assert(not files[target..".pending"] and not files[target..".bak"])
    save("second")
    assert(Storage.load("run").value=="second" and Storage.load("run","backup").value=="first")
end)
test("staging failure leaves original and backup untouched",function()
    save("first"); files[target..".bak"]="valid:older"
    fault=function(path) if path==target..".pending" then files[path]="truncated"; return true end end
    fails(function() save("second") end)
    assert(files[target]=="valid:first" and files[target..".bak"]=="valid:older")
end)
test("backup failure prevents primary overwrite",function()
    save("first")
    fault=function(path) if path==target..".bak" then files[path]="truncated"; return true end end
    fails(function() save("second") end)
    assert(files[target]=="valid:first" and files[target..".pending"]=="valid:second")
end)
test("failed final write restores original and keeps recovery files",function()
    save("first")
    fault=function(path,bytes)
        if path==target and bytes=="valid:second" then files[path]="truncated"; return true end
    end
    fails(function() save("second") end)
    assert(files[target]=="valid:first" and files[target..".bak"]=="valid:first")
    assert(Storage.load("run","pending").value=="second")
end)
test("unrecoverable final write still preserves backup and pending",function()
    save("first")
    fault=function(path) if path==target then error("disk failure") end end
    fails(function() save("second") end)
    assert(Storage.load("run","backup").value=="first" and Storage.load("run","pending").value=="second")
end)
test("corrupt primary never replaces a valid older backup",function()
    files[target]="corrupt"; files[target..".bak"]="valid:older"
    save("new")
    assert(Storage.load("run").value=="new" and Storage.load("run","backup").value=="older")
    assert(#warnings==1)
end)
test("pending cleanup failure does not report a failed verified save",function()
    fault=function(_,bytes) if bytes==nil then error("delete failed") end end
    save("new")
    assert(Storage.load("run").value=="new" and #warnings==1)
end)
test("recovery reads never overwrite primary",function()
    files[target]="corrupt"; files[target..".bak"]="valid:backup"; files[target..".pending"]="valid:pending"
    fails(function() Storage.load("run") end)
    assert(Storage.load("run","backup").value=="backup" and files[target]=="corrupt")
    assert(Storage.load("run","pending").value=="pending" and files[target]=="corrupt")
    fails(function() Storage.load("run","../bad") end)
end)
test("path traversal and unwanted file extensions rejected",function()
    for _,name in ipairs({"", "../run", "a/b", "a\\b", "run.fe2tomatas",string.rep("x",101)}) do
        fails(function() Storage.save(name,{value="new"}) end)
        fails(function() Storage.load(name) end)
    end
    assert(next(files)==nil)
end)
test("file listing excludes recovery files",function()
    save("first"); save("second")
    files[target..".pending"]="valid:pending"
    local listing=Storage.list()
    assert(#listing==1 and listing[1]==target)
end)
print("Storage tests passed: "..count)

local factories={
    ["core/Tree"]=require("../src/core/Tree"),
    ["core/Quaternion"]=require("../src/core/Quaternion"),
    ["core/Codec"]=require("../src/core/Codec"),
    ["core/Sampling"]=require("../src/core/Sampling"),
}
local config={MaxNodes=100000,MaxFileBytes=16000000}
local modules={}
local function import(name)
    if not modules[name] then modules[name]=factories[name](import,config) end
    return modules[name]
end
local Tree,Codec,Q,Sampling=import("core/Tree"),import("core/Codec"),import("core/Quaternion"),import("core/Sampling")
local count=0
local function test(name,fn)
    fn(); count+=1; print("PASS "..name)
end
local function near(a,b) assert(math.abs(a-b)<1e-10,tostring(a).." != "..tostring(b)) end
local function fails(fn) assert(not pcall(fn),"Expected rejection") end
local function frame(time,x)
    return {time=time,root={x,0,0,0,0,0,1},camera={x,1,0,0,0,0,1},velocity={10,0,0},angular={0,0,0},
        geometry={2,2,1,2,2,1,0},humanoid={8,20,50,7.2,1,0,100},flags={0,0,0},
        tracks={{id="rbxassetid://123",time=time,speed=1,weight=0.75,priority=2,looped=1}}}
end
local function tree()
    local t=Tree.new({map="Test map",spawn="Spawn",author="Tester",created=12345})
    t:Append(frame(0,0)); t:Append(frame(0.1,1)); t:Append(frame(0.2,2))
    return t
end
test("branching preserves old futures",function()
    local t=tree()
    t:Seek(2); t:Append(frame(0.3,30))
    local tips=t:Branches()
    assert(#tips==2 and tips[1]==3 and tips[2]==4)
    assert(table.concat(t:Path(4),",")=="1,2,4")
    assert(t.nodes[3].frame.root[1]==2)
end)
test("timestamps and node ids validated",function()
    local t=tree()
    fails(function() t:Append(frame(0.2,1)) end)
    fails(function() t:Append(frame(0/0,1)) end)
    fails(function() t:Seek(-1) end)
    fails(function() t:Seek(1.5) end)
end)
test("binary roundtrip branches, marks, transforms and animation",function()
    local t=tree(); t:Seek(2); t:Mark("a"); t:Mark("b"); t:Mark("c"); t:Mark("d")
    t:Append(frame(0.25,9)); t:Mark("alternate")
    local bytes=Codec.encode(t)
    local decoded=Codec.decode(bytes)
    assert(Codec.encode(decoded)==bytes)
    assert(decoded.cursor==4 and decoded.marks.alternate==4 and #decoded:Branches()==2)
    near(decoded.nodes[4].frame.root[1],9)
    assert(decoded.metadata.map=="Test map")
end)
test("truncation and trailing data rejected",function()
    local bytes=Codec.encode(tree())
    for i=0,#bytes-1 do fails(function() Codec.decode(bytes:sub(1,i)) end) end
    fails(function() Codec.decode(bytes.."x") end)
end)
test("single-byte corruption rejected",function()
    local bytes=Codec.encode(tree())
    for i=1,#bytes do
        local corrupt=bytes:sub(1,i-1)..string.char((bytes:byte(i)+1)%256)..bytes:sub(i+1)
        fails(function() Codec.decode(corrupt) end)
    end
end)
test("invalid geometry and quaternions rejected",function()
    local t=tree(); t.nodes[1].frame.geometry[1]=0
    fails(function() Codec.encode(t) end)
    t=tree(); t.nodes[2].frame.root[7]=0
    fails(function() Codec.encode(t) end)
end)
test("quaternion matrix roundtrip across rotations",function()
    math.randomseed(17)
    for _=1,10000 do
        local a={Q.normalize(math.random()-0.5,math.random()-0.5,math.random()-0.5,math.random()-0.5)}
        local m={Q.matrix(table.unpack(a))}
        local b={Q.fromMatrix(table.unpack(m))}
        near(math.abs(a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4]),1)
    end
end)
test("quaternion opposite signs take shortest path",function()
    local q=Q.slerp({0,0,0,1},{0,0,0,-1},0.5)
    near(math.abs(q[4]),1)
    fails(function() Q.normalize(0,0,0,0) end)
end)
test("sampling boundaries, interpolation and discrete flags",function()
    local t=tree(); t.nodes[3].frame.flags[1]=1
    local path=t:Path()
    local f,index=Sampling.at(t,path,0.15)
    near(f.root[1],1.5); near(f.tracks[1].time,0.15)
    assert(index==2 and f.flags[1]==0)
    assert(Sampling.at(t,path,-1)==t.nodes[1].frame)
    assert(Sampling.at(t,path,10)==t.nodes[3].frame)
end)
test("large branching file roundtrip",function()
    local t=tree()
    for i=4,10000 do
        if i%100==0 then t:Seek(2) end
        t:Append(frame(t.nodes[t.cursor].frame.time+0.01,i))
    end
    local decoded=Codec.decode(Codec.encode(t))
    assert(#decoded.nodes==10000 and #decoded:Branches()==#t:Branches())
end)
print("Core tests passed: "..count)

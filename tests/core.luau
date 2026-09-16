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
-- Recompute the checksum with the simple reference algorithm so malformed
-- payload tests exercise parsing rather than stopping at checksum validation.
local function seal(b)
    local a,c=1,0
    for i=0,buffer.len(b)-5 do
        a=(a+buffer.readu8(b,i))%65521
        c=(c+a)%65521
    end
    buffer.writeu32(b,buffer.len(b)-4,c*65536+a)
    return buffer.tostring(b)
end
local function rewrite(bytes,fn)
    local b=buffer.fromstring(bytes)
    fn(b)
    return seal(b)
end
local function locations(bytes)
    local b,p=buffer.fromstring(bytes),0
    local function skipString()
        local start=p
        p+=4+buffer.readu32(b,p)
        return start
    end
    skipString()
    p+=4
    skipString(); skipString(); skipString()
    p+=8
    local result={count=p,cursor=p+4,nodes={}}
    local n=buffer.readu32(b,p)
    p+=8
    for i=1,n do
        local node={parent=p,time=p+4,root=p+12,geometry=p+172,humanoid=p+228,flags=p+284,tracks={}}
        p+=308
        node.trackCount=p
        local tracks=buffer.readu32(b,p)
        p+=4
        for j=1,tracks do
            local id=skipString()
            node.tracks[j]={id=id,time=p,speed=p+8,weight=p+16,priority=p+24,looped=p+32}
            p+=40
        end
        result.nodes[i]=node
    end
    result.markCount=p
    local marks=buffer.readu32(b,p)
    p+=4
    result.marks={}
    for i=1,marks do
        local name=skipString()
        result.marks[i]={name=name,id=p}
        p+=4
    end
    assert(p==#bytes-4,"Incorrect fixture offsets")
    return result
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

test("invalid tree paths and parent cycles reject immediately",function()
    local t=tree()
    for _,id in ipairs({-1,0,1.5,4,math.huge,0/0}) do fails(function() t:Path(id) end) end
    fails(function() t:Path(false) end)
    assert(#Tree.new({}):Path()==0)
    t.nodes[3].parent=3
    fails(function() t:Path(3) end)
    t.nodes[3].parent=0
    fails(function() t:Path(3) end)
    t.nodes[3].parent=1.5
    fails(function() t:Path(3) end)
    t.cursor=0
    fails(function() t:Append(frame(1,0)) end)
    t.cursor=1.5
    fails(function() t:Mark("bad") end)
end)

test("node limits and mark names reject without changing the tree",function()
    local LimitedTree=factories["core/Tree"](nil,{MaxNodes=1})
    local t=LimitedTree.new({})
    t:Append(frame(0,0))
    fails(function() t:Append(frame(1,1)) end)
    assert(#t.nodes==1 and t.cursor==1 and t.tips[1])
    fails(function() t:Mark("") end)
    fails(function() t:Mark(string.rep("x",129)) end)
    t:Mark("valid"); t:Mark("valid")
    assert(t.marks.valid==1)
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

test("encoder rejects malformed topology and selection",function()
    fails(function() Codec.encode(Tree.new({map="",author="",spawn="",created=0})) end)
    for _,id in ipairs({0,4,1.5,0/0}) do
        local t=tree(); t.cursor=id
        fails(function() Codec.encode(t) end)
    end
    for _,parent in ipairs({0,2,3,0.5}) do
        local t=tree(); t.nodes[2].parent=parent
        fails(function() Codec.encode(t) end)
    end
    local t=tree(); t.nodes[2]=nil
    fails(function() Codec.encode(t) end)
    t=tree(); t.nodes[1].frame.time=0.05
    fails(function() Codec.encode(t) end)
    t=tree(); t.nodes[3].frame.time=t.nodes[2].frame.time
    fails(function() Codec.encode(t) end)
end)

test("encoder validates marks and dense frame arrays",function()
    for _,id in ipairs({0,4,1.5,0/0}) do
        local t=tree(); t.marks.bad=id
        fails(function() Codec.encode(t) end)
    end
    local t=tree(); t.marks[string.rep("x",129)]=1
    fails(function() Codec.encode(t) end)
    t=tree(); t.marks[12]=1
    fails(function() Codec.encode(t) end)
    t=tree(); t.nodes[1].frame.root[8]=0
    fails(function() Codec.encode(t) end)
    t=tree(); t.nodes[1].frame.tracks[3]=t.nodes[1].frame.tracks[1]
    fails(function() Codec.encode(t) end)
    t=tree(); t.nodes[1].frame.tracks=nil
    fails(function() Codec.encode(t) end)
    assert(t.nodes[1].frame.tracks==nil,"Encoding mutated the rejected frame")
end)

test("encoding leaves frozen run snapshots untouched",function()
    local t=tree(); t:Mark("frozen")
    for _,node in ipairs(t.nodes) do
        local f=node.frame
        for _,track in ipairs(f.tracks) do table.freeze(track) end
        for _,value in pairs(f) do if type(value)=="table" then table.freeze(value) end end
        table.freeze(f); table.freeze(node)
    end
    table.freeze(t.metadata); table.freeze(t.nodes); table.freeze(t.marks); table.freeze(t)
    assert(Codec.decode(Codec.encode(t)).marks.frozen==3)
end)

test("checksum-valid malformed parents, counts and timestamps reject",function()
    local bytes=Codec.encode(tree())
    local pos=locations(bytes)
    local corruptions={
        function(b) buffer.writeu32(b,pos.count,100001) end,
        function(b) buffer.writeu32(b,pos.count,99999) end,
        function(b) buffer.writeu32(b,pos.cursor,0) end,
        function(b) buffer.writeu32(b,pos.cursor,4) end,
        function(b) buffer.writeu32(b,pos.nodes[1].parent,1) end,
        function(b) buffer.writeu32(b,pos.nodes[2].parent,2) end,
        function(b) buffer.writeu32(b,pos.nodes[2].parent,0) end,
        function(b) buffer.writef64(b,pos.nodes[1].time,1) end,
        function(b) buffer.writef64(b,pos.nodes[2].time,0) end,
        function(b) buffer.writef64(b,pos.nodes[2].time,0/0) end,
        function(b) buffer.writeu32(b,pos.nodes[1].trackCount,257) end,
        function(b) buffer.writeu32(b,pos.nodes[1].tracks[1].id,1048577) end,
        function(b) buffer.writeu32(b,pos.markCount,100001) end,
    }
    for _,change in ipairs(corruptions) do fails(function() Codec.decode(rewrite(bytes,change)) end) end
end)

test("checksum-valid malformed frame fields reject",function()
    local bytes=Codec.encode(tree())
    local node=locations(bytes).nodes[1]
    local invalidFields={
        {node.root,math.huge},{node.root+48,0},{node.geometry,0},{node.geometry+8,-1},
        {node.humanoid,1.5},{node.humanoid+8,-1},{node.humanoid+16,-1},{node.humanoid+24,-1},
        {node.humanoid+32,2},{node.humanoid+40,0.5},{node.humanoid+48,-1},{node.flags,2},
        {node.tracks[1].time,-1},{node.tracks[1].weight,-0.1},{node.tracks[1].priority,0.5},
        {node.tracks[1].looped,2},
    }
    for _,field in ipairs(invalidFields) do
        fails(function() Codec.decode(rewrite(bytes,function(b) buffer.writef64(b,field[1],field[2]) end)) end)
    end
end)

test("animation weights above one survive save, load and sampling",function()
    local t=tree()
    t.nodes[1].frame.tracks[1].weight=3
    t.nodes[2].frame.tracks[1].weight=5
    local bytes=Codec.encode(t)
    assert(Codec.validate(bytes))
    local decoded=Codec.decode(bytes)
    assert(decoded.nodes[1].frame.tracks[1].weight==3)
    assert(decoded.nodes[2].frame.tracks[1].weight==5)
    near(Sampling.at(decoded,decoded:Path(),0.05).tracks[1].weight,4)
end)

test("checksum-valid invalid marks and trailing payload reject",function()
    local t=tree(); t:Mark("a"); t:Mark("b")
    local bytes=Codec.encode(t)
    local pos=locations(bytes)
    fails(function() Codec.decode(rewrite(bytes,function(b) buffer.writeu32(b,pos.marks[1].id,4) end)) end)
    fails(function() Codec.decode(rewrite(bytes,function(b) buffer.writeu32(b,pos.marks[1].name,0) end)) end)
    fails(function() Codec.decode(rewrite(bytes,function(b) buffer.writeu8(b,pos.marks[2].name+4,string.byte("a")) end)) end)
    local extra=buffer.create(#bytes+1)
    buffer.copy(extra,0,buffer.fromstring(bytes),0,#bytes-4)
    fails(function() Codec.decode(seal(extra)) end)
end)

test("file and node caps apply symmetrically on encode and decode",function()
    local t=tree()
    local bytes=Codec.encode(t)
    local exact=factories["core/Codec"](import,{MaxNodes=3,MaxFileBytes=#bytes})
    assert(exact.encode(t)==bytes and #exact.decode(bytes).nodes==3)
    local small=factories["core/Codec"](import,{MaxNodes=3,MaxFileBytes=#bytes-1})
    fails(function() small.encode(t) end)
    fails(function() small.decode(bytes) end)
    local fewer=factories["core/Codec"](import,{MaxNodes=2,MaxFileBytes=#bytes})
    fails(function() fewer.encode(t) end)
    fails(function() fewer.decode(bytes) end)
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

test("quaternion normalization resists overflow and underflow",function()
    for _,scale in ipairs({1e-300,1e300}) do
        local q={Q.normalize(scale,0,0,scale)}
        near(q[1],math.sqrt(0.5)); near(q[4],math.sqrt(0.5))
    end
    fails(function() Q.normalize(0/0,0,0,1) end)
    fails(function() Q.normalize(0,math.huge,0,1) end)
    fails(function() Q.slerp({0,0,0,1},{0,0,0,1},0/0) end)
    fails(function() Q.slerp({0,0,0,1},{0,0,0,1},2) end)
    local q=Q.slerp({0,0,0,2},{0,2,0,0},0.5)
    near(q[2],math.sqrt(0.5)); near(q[4],math.sqrt(0.5))
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

test("sampling resolves exact frames and rejects nonfinite clocks",function()
    local t=tree()
    local path=t:Path()
    for i,id in ipairs(path) do
        local f,index=Sampling.at(t,path,t.nodes[id].frame.time)
        assert(f==t.nodes[id].frame and index==i)
    end
    fails(function() Sampling.at(t,path,0/0) end)
    fails(function() Sampling.at(t,path,math.huge) end)
    fails(function() Sampling.at(t,{},0) end)
end)

test("animation interpolation survives track reordering and duplicate ids",function()
    local t=tree()
    local a,b=t.nodes[1].frame,t.nodes[2].frame
    local function track(id,time,weight)
        return {id=id,time=time,speed=1,weight=weight,priority=2,looped=0}
    end
    a.tracks={track("same",1,0),track("other",4,1),track("same",8,0.5)}
    b.tracks={track("other",4.1,0),track("same",1.1,1),track("same",8.1,0.75)}
    local f=Sampling.at(t,t:Path(),0.05)
    near(f.tracks[1].time,1.05); near(f.tracks[1].weight,0.5)
    near(f.tracks[2].time,4.05); near(f.tracks[2].weight,0.5)
    near(f.tracks[3].time,8.05); near(f.tracks[3].weight,0.625)
    assert(a.tracks[1].time==1 and a.tracks[1].weight==0)
end)

test("reverse animation interpolates while loops and missing tracks hold",function()
    local t=tree()
    local a,b=t.nodes[1].frame.tracks[1],t.nodes[2].frame.tracks[1]
    a.time=2; b.time=1.9; a.speed=-1; b.speed=-1
    near(Sampling.at(t,t:Path(),0.05).tracks[1].time,1.95)
    a.speed=1; b.speed=1
    near(Sampling.at(t,t:Path(),0.05).tracks[1].time,2)
    t.nodes[2].frame.tracks={}
    near(Sampling.at(t,t:Path(),0.05).tracks[1].time,2)
end)
test("large branching file roundtrip",function()
    local t=tree()
    for i=4,10000 do
        if i%100==0 then t:Seek(2) end
        t:Append(frame(t.nodes[t.cursor].frame.time+0.01,i))
    end
    local bytes=Codec.encode(t)
    assert(rewrite(bytes,function() end)==bytes,"Batched checksum differs from the reference")
    local decoded=Codec.decode(bytes)
    assert(#decoded.nodes==10000 and #decoded:Branches()==#t:Branches())
end)
test("validation checks semantic corruption as strictly as decoding",function()
    local t=tree(); t:Mark("valid")
    local bytes=Codec.encode(t)
    local pos=locations(bytes)
    assert(Codec.validate(bytes))
    for _,change in ipairs({
        function(b) buffer.writeu32(b,pos.nodes[2].parent,2) end,
        function(b) buffer.writef64(b,pos.nodes[2].time,0) end,
        function(b) buffer.writef64(b,pos.nodes[1].geometry,-1) end,
        function(b) buffer.writeu32(b,pos.marks[1].id,999) end,
    }) do
        local bad=rewrite(bytes,change)
        fails(function() Codec.validate(bad) end)
        fails(function() Codec.decode(bad) end)
    end
end)
test("validation does not allocate a second recording tree",function()
    local bytes=Codec.encode(tree())
    local original=Tree.new
    Tree.new=function() error("validation must not allocate a Tree") end
    local ok,result=pcall(Codec.validate,bytes)
    Tree.new=original
    assert(ok and result==true)
end)
print("Core tests passed: "..count)

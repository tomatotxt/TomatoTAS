-- Version 1: little endian, f64 transforms/quaternions, explicit frame schema.
return function(import, config)
    local Tree = import("core/Tree")
    local Codec = {}
    local function checksum(b,n)
        local a,c=1,0
        for first=0,n-1,4096 do
            for i=first,math.min(first+4095,n-1) do
                a+=buffer.readu8(b,i)
                c+=a
            end
            a%=65521
            c%=65521
        end
        return c*65536+a
    end
    local arrays = {{"root",7},{"velocity",3},{"angular",3},{"camera",7},{"geometry",7},{"humanoid",7},{"flags",3}}
    local trackFields={"time","speed","weight","priority","looped"}
    local function denseLength(values,maximum,label)
        assert(type(values)=="table","Invalid "..label)
        local n=#values
        assert(n<=maximum,"Too many "..label)
        local count=0
        for key in pairs(values) do
            assert(type(key)=="number" and key%1==0 and key>=1 and key<=n,"Sparse or invalid "..label)
            count+=1
        end
        assert(count==n,"Sparse "..label)
        return n
    end
    local function validParent(id,parent)
        return type(parent)=="number" and parent%1==0
            and ((id==1 and parent==0) or (id>1 and parent>=1 and parent<id))
    end
    local function stream(data)
        local s={b=if data then buffer.fromstring(data) else buffer.create(math.min(4096,config.MaxFileBytes)),
            p=0,read=data~=nil,limit=if data then #data-4 else config.MaxFileBytes}
        function s:room(n)
            assert(n>=0 and self.p+n<=config.MaxFileBytes,"File size limit")
            if self.read then assert(self.p+n<=self.limit,"Truncated TAS file")
            elseif self.p+n>buffer.len(self.b) then
                local nextBuffer=buffer.create(math.min(config.MaxFileBytes,math.max(self.p+n,buffer.len(self.b)*2)))
                buffer.copy(nextBuffer,0,self.b,0,self.p)
                self.b=nextBuffer
            end
        end
        function s:num(kind,value)
            local size=if kind=="u8" then 1 elseif kind=="u32" then 4 else 8
            self:room(size)
            if self.read then value=buffer["read"..kind](self.b,self.p)
            else
                assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Nonfinite number")
                if kind~="f64" then assert(value%1==0 and value>=0 and value<2^(size*8),"Integer out of range") end
                buffer["write"..kind](self.b,self.p,value)
            end
            self.p+=size
            assert(value==value and math.abs(value)<math.huge,"Nonfinite number")
            return value
        end
        function s:str(value)
            if not self.read then assert(type(value)=="string","Invalid string") end
            local n=self:num("u32",if value then #value else nil)
            assert(n<=1048576,"String too large")
            self:room(n)
            if self.read then value=buffer.readstring(self.b,self.p,n) else buffer.writestring(self.b,self.p,value) end
            self.p+=n
            return value
        end
        return s
    end
    local function frame(s,f)
        if not s.read then assert(type(f)=="table","Invalid frame") end
        local time=s:num("f64",f and f.time)
        if s.read then f={time=time} end
        assert(time>=0,"Invalid frame time")
        for _,spec in ipairs(arrays) do
            local a=if s.read then {} else f[spec[1]]
            if not s.read then assert(denseLength(a,spec[2],spec[1])==spec[2],"Incomplete "..spec[1]) end
            for i=1,spec[2] do
                local value=s:num("f64",a[i])
                if s.read then a[i]=value end
            end
            if s.read then f[spec[1]]=a end
        end
        if s.read then f.tracks={} end
        local n=s:num("u32",if s.read then nil else denseLength(f.tracks,256,"animation tracks"))
        assert(n<=256,"Too many animation tracks")
        for i=1,n do
            local t=if s.read then {} else f.tracks[i]
            assert(type(t)=="table","Invalid animation sample")
            local id=s:str(t.id)
            if s.read then t.id=id end
            for _,key in ipairs(trackFields) do
                local value=s:num("f64",t[key])
                if s.read then t[key]=value end
            end
            if s.read then f.tracks[i]=t end
        end
        for _,name in ipairs({"root","camera"}) do
            local a=f[name]
            local norm=a[4]^2+a[5]^2+a[6]^2+a[7]^2
            assert(math.abs(norm-1)<0.001,"Invalid rotation quaternion")
        end
        for i=1,6 do assert(f.geometry[i]>0 and f.geometry[i]<1000,"Invalid character geometry") end
        for i=1,3 do assert(f.flags[i]==0 or f.flags[i]==1,"Invalid mechanic flag") end
        assert(f.humanoid[1]>=0 and f.humanoid[1]<=16 and f.humanoid[1]%1==0,"Invalid humanoid state")
        for i=2,4 do assert(f.humanoid[i]>=0,"Invalid humanoid movement value") end
        for i=5,6 do assert(f.humanoid[i]==0 or f.humanoid[i]==1,"Invalid humanoid flag") end
        assert(f.humanoid[7]>=0,"Invalid humanoid health")
        for _,t in ipairs(f.tracks) do
            assert(t.time>=0 and t.weight>=0 and t.weight<=1 and t.priority%1==0
                and t.priority>=0 and t.priority<=1000 and (t.looped==0 or t.looped==1),"Invalid animation sample")
        end
        return f
    end
    function Codec.encode(tree)
        assert(type(tree)=="table" and type(tree.metadata)=="table" and type(tree.marks)=="table","Invalid run")
        local n=denseLength(tree.nodes,config.MaxNodes,"tree nodes")
        assert(n>0 and type(tree.cursor)=="number" and tree.cursor%1==0 and tree.cursor>=1 and tree.cursor<=n,"Invalid node count/cursor")
        local s=stream()
        s:str("FE2TOMATAS"); s:num("u32",1)
        s:str(tree.metadata.map); s:str(tree.metadata.author); s:str(tree.metadata.spawn)
        s:num("f64",tree.metadata.created)
        s:num("u32",n); s:num("u32",tree.cursor)
        for id,node in ipairs(tree.nodes) do
            assert(type(node)=="table" and validParent(id,node.parent),"Invalid tree parent")
            s:num("u32",node.parent)
            frame(s,node.frame)
            assert((id==1 and node.frame.time==0) or (id>1 and node.frame.time>tree.nodes[node.parent].frame.time),"Nonmonotonic frame")
        end
        local names={}
        for name,id in pairs(tree.marks) do
            assert(type(name)=="string" and #name>0 and #name<=128
                and type(id)=="number" and id%1==0 and id>=1 and id<=n,"Invalid mark")
            assert(#names<100000,"Invalid mark count")
            table.insert(names,name)
        end
        table.sort(names)
        s:num("u32",#names)
        for _,name in ipairs(names) do s:str(name); s:num("u32",tree.marks[name]) end
        s:num("u32",checksum(s.b,s.p))
        return buffer.readstring(s.b,0,s.p)
    end
    local function decode(data,validateOnly)
        assert(type(data)=="string" and #data<=config.MaxFileBytes,"Invalid file size")
        local s=stream(data)
        assert(#data>=4 and buffer.readu32(s.b,#data-4)==checksum(s.b,#data-4),"TAS checksum mismatch")
        assert(s:str()=="FE2TOMATAS" and s:num("u32")==1,"Unsupported TAS format/version")
        local metadata={map=s:str(),author=s:str(),spawn=s:str(),created=s:num("f64")}
        local tree=if validateOnly then nil else Tree.new(metadata)
        local times=if validateOnly then {} else nil
        local n,cursor=s:num("u32"),s:num("u32")
        assert(n>0 and n<=config.MaxNodes and cursor>=1 and cursor<=n,"Invalid node count/cursor")
        -- Even a frame without animation occupies 312 bytes including its
        -- parent. Reject impossible counts before allocating the node tree.
        assert(n<=math.floor((s.limit-s.p-4)/312),"Truncated TAS nodes")
        for id=1,n do
            local parent=s:num("u32")
            assert(validParent(id,parent),"Invalid tree parent")
            local sample=frame(s)
            if tree then
                tree.cursor=parent
                tree:Append(sample)
            else
                assert((id==1 and sample.time==0) or (id>1 and sample.time>times[parent]),"Nonmonotonic frame")
                times[id]=sample.time
            end
        end
        if tree then tree.cursor=cursor end
        local marks=s:num("u32")
        assert(marks<=100000 and marks<=math.floor((s.limit-s.p)/9),"Invalid mark count")
        local seen=if tree then tree.marks else {}
        for _=1,marks do
            local name,id=s:str(),s:num("u32")
            assert(#name>0 and #name<=128 and id>=1 and id<=n and not seen[name],"Invalid mark")
            seen[name]=id
        end
        assert(s.p==s.limit,"Unexpected trailing bytes")
        return tree
    end
    function Codec.decode(data)
        return decode(data,false)
    end
    function Codec.validate(data)
        -- Keep only parent timestamps while checking an existing backup. Building
        -- another full frame tree during every save doubles peak run memory.
        decode(data,true)
        return true
    end
    return Codec
end

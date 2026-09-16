-- Version 1: little endian, f64 transforms/quaternions, explicit frame schema.
return function(import, config)
    local Tree = import("core/Tree")
    local Codec = {}
    local function checksum(b,n)
        local a,c=1,0
        for i=0,n-1 do
            a=(a+buffer.readu8(b,i))%65521
            c=(c+a)%65521
        end
        return c*65536+a
    end
    local arrays = {{"root",7},{"velocity",3},{"angular",3},{"camera",7},{"geometry",7},{"humanoid",7},{"flags",3}}
    local function stream(data)
        local s={b=if data then buffer.fromstring(data) else buffer.create(4096),p=0,read=data~=nil}
        function s:room(n)
            assert(n>=0 and self.p+n<=config.MaxFileBytes,"File size limit")
            if self.read then assert(self.p+n<=buffer.len(self.b),"Truncated TAS file")
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
        f=f or {}
        f.time=s:num("f64",f.time)
        for _,spec in ipairs(arrays) do
            local a=f[spec[1]] or {}
            for i=1,spec[2] do a[i]=s:num("f64",a[i]) end
            f[spec[1]]=a
        end
        f.tracks=f.tracks or {}
        local n=s:num("u32",#f.tracks)
        assert(n<=256,"Too many animation tracks")
        for i=1,n do
            local t=f.tracks[i] or {}
            t.id=s:str(t.id)
            for _,key in ipairs({"time","speed","weight","priority","looped"}) do t[key]=s:num("f64",t[key]) end
            f.tracks[i]=t
        end
        for _,name in ipairs({"root","camera"}) do
            local a=f[name]
            local norm=a[4]^2+a[5]^2+a[6]^2+a[7]^2
            assert(math.abs(norm-1)<0.001,"Invalid rotation quaternion")
        end
        for i=1,6 do assert(f.geometry[i]>0 and f.geometry[i]<1000,"Invalid character geometry") end
        for i=1,3 do assert(f.flags[i]==0 or f.flags[i]==1,"Invalid mechanic flag") end
        assert(f.humanoid[1]>=0 and f.humanoid[1]<=16 and f.humanoid[1]%1==0,"Invalid humanoid state")
        for _,t in ipairs(f.tracks) do
            assert(t.time>=0 and t.weight>=0 and t.weight<=1 and t.priority%1==0
                and t.priority>=0 and t.priority<=1000 and (t.looped==0 or t.looped==1),"Invalid animation sample")
        end
        return f
    end
    function Codec.encode(tree)
        local s=stream()
        s:str("FE2TOMATAS"); s:num("u32",1)
        s:str(tree.metadata.map); s:str(tree.metadata.author); s:str(tree.metadata.spawn)
        s:num("f64",tree.metadata.created)
        s:num("u32",#tree.nodes); s:num("u32",tree.cursor)
        for _,node in ipairs(tree.nodes) do s:num("u32",node.parent); frame(s,node.frame) end
        local names={}
        for name in pairs(tree.marks) do table.insert(names,name) end
        table.sort(names)
        s:num("u32",#names)
        for _,name in ipairs(names) do s:str(name); s:num("u32",tree.marks[name]) end
        s:num("u32",checksum(s.b,s.p))
        return buffer.readstring(s.b,0,s.p)
    end
    function Codec.decode(data)
        assert(type(data)=="string" and #data<=config.MaxFileBytes,"Invalid file size")
        local s=stream(data)
        assert(#data>=4 and buffer.readu32(s.b,#data-4)==checksum(s.b,#data-4),"TAS checksum mismatch")
        assert(s:str()=="FE2TOMATAS" and s:num("u32")==1,"Unsupported TAS format/version")
        local tree=Tree.new({map=s:str(),author=s:str(),spawn=s:str(),created=s:num("f64")})
        local n,cursor=s:num("u32"),s:num("u32")
        assert(n>0 and n<=config.MaxNodes and cursor>=1 and cursor<=n,"Invalid node count/cursor")
        for id=1,n do
            local parent=s:num("u32")
            assert((id==1 and parent==0) or (id>1 and parent>=1 and parent<id),"Invalid tree parent")
            tree.cursor=parent
            tree:Append(frame(s))
        end
        tree.cursor=cursor
        local marks=s:num("u32")
        assert(marks<=100000,"Invalid mark count")
        for _=1,marks do
            local name,id=s:str(),s:num("u32")
            assert(#name>0 and #name<=128 and tree.nodes[id] and not tree.marks[name],"Invalid mark")
            tree.marks[name]=id
        end
        s:num("u32") -- checksum already verified before parsing
        assert(s.p==#data,"Unexpected trailing bytes")
        return tree
    end
    return Codec
end

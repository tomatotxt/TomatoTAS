return function(_, config)
    local Tree = {}
    Tree.__index = Tree
    function Tree.new(metadata)
        return setmetatable({metadata=metadata, nodes={}, cursor=0, marks={}, tips={}},Tree)
    end
    function Tree:Append(frame)
        assert(#self.nodes < config.MaxNodes, "Recording node limit reached; save this run")
        assert(type(frame)=="table" and type(frame.time)=="number" and frame.time >= 0 and frame.time < math.huge, "Invalid time")
        assert(type(self.cursor)=="number" and self.cursor%1==0 and self.cursor>=0
            and self.cursor<=#self.nodes, "Invalid tree cursor")
        local parent = self.nodes[self.cursor]
        assert((parent and frame.time > parent.frame.time) or (not parent and #self.nodes==0 and frame.time==0), "Nonmonotonic frame")
        local id = #self.nodes+1
        self.nodes[id] = {parent=self.cursor,frame=frame}
        self.tips[self.cursor] = nil
        self.tips[id] = true
        self.cursor = id
        return id
    end
    function Tree:Seek(id)
        assert(type(id)=="number" and id%1==0 and self.nodes[id], "Unknown frame node")
        self.cursor=id
        return self.nodes[id].frame
    end
    function Tree:Mark(name)
        assert(type(name)=="string" and #name>0 and #name<=128, "Invalid mark name")
        assert(type(self.cursor)=="number" and self.cursor%1==0 and self.nodes[self.cursor], "No frame to mark")
        if not self.marks[name] then
            local count=0
            for _ in pairs(self.marks) do count+=1 end
            assert(count<100000,"Mark limit reached")
        end
        self.marks[name]=self.cursor
    end
    function Tree:Path(id)
        if id==nil then id=self.cursor end
        assert(type(id)=="number" and id%1==0 and id>=0 and (self.nodes[id] or (id==0 and #self.nodes==0)), "Unknown frame node")
        local reverse, result = {},{}
        while id>0 do
            local node = assert(self.nodes[id], "Invalid tree path")
            assert(type(node.parent)=="number" and node.parent%1==0
                and ((id==1 and node.parent==0) or (id>1 and node.parent>=1 and node.parent<id)), "Invalid tree parent")
            table.insert(reverse,id)
            id=node.parent
        end
        for i=#reverse,1,-1 do table.insert(result,reverse[i]) end
        return result
    end
    function Tree:Branches()
        local result={}
        for id in pairs(self.tips) do table.insert(result,id) end
        table.sort(result)
        return result
    end
    return Tree
end

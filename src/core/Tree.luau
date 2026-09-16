return function(_, config)
    local Tree = {}
    Tree.__index = Tree
    function Tree.new(metadata)
        return setmetatable({metadata=metadata, nodes={}, cursor=0, marks={}, tips={}},Tree)
    end
    function Tree:Append(frame)
        assert(#self.nodes < config.MaxNodes, "Recording node limit reached; save this run")
        assert(type(frame.time)=="number" and frame.time >= 0 and frame.time < math.huge, "Invalid time")
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
        assert(self.cursor>0, "No frame to mark")
        self.marks[name]=self.cursor
    end
    function Tree:Path(id)
        id=id or self.cursor
        local reverse, result = {},{}
        while id>0 do
            local node = assert(self.nodes[id], "Invalid tree path")
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

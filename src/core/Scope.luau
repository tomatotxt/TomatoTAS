return function()
    local Scope={}
    Scope.__index=Scope
    function Scope.new() return setmetatable({items={},dead=false},Scope) end
    function Scope:Add(item)
        assert(not self.dead,"Scope already closed")
        table.insert(self.items,item)
        return item
    end
    function Scope:Destroy()
        if self.dead then return end
        self.dead=true
        for i=#self.items,1,-1 do
            local item=self.items[i]
            local ok,err=pcall(function()
                if type(item)=="function" then item()
                elseif typeof(item)=="RBXScriptConnection" then item:Disconnect()
                else item:Destroy() end
            end)
            if not ok then warn("[TomatoTAS cleanup]",err) end
        end
        table.clear(self.items)
    end
    return Scope
end

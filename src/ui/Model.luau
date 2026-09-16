-- Pure presentation helpers; no Roblox objects or playback side effects.
return function()
    local Model={}
    function Model.clock(seconds)
        if type(seconds)~="number" or seconds~=seconds or math.abs(seconds)==math.huge then seconds=0 end
        local ms=math.floor(math.max(0,seconds)*1000+0.5)
        return string.format("%02d:%02d.%03d",math.floor(ms/60000),math.floor(ms/1000)%60,ms%1000)
    end
    function Model.fileName(path)
        if type(path)~="string" then return nil end
        local name=path:gsub("\\","/"):match("([^/]+)$")
        local stem=name and name:match("^(.-)%.fe2tomatas$")
        return if stem and #stem>0 and #stem<=100 and stem:match("^[%w_%-]+$") then stem else nil
    end
    function Model.frameAt(tree,path,ratio)
        if not tree or not path or #path==0 then return nil end
        if type(ratio)~="number" or ratio~=ratio then return nil end
        local first,last=tree.nodes[path[1]],tree.nodes[path[#path]]
        if not first or not last then return nil end
        local target=first.frame.time+(last.frame.time-first.frame.time)*math.clamp(ratio,0,1)
        local low,high=1,#path
        while low<high do
            local middle=math.ceil((low+high)/2)
            if tree.nodes[path[middle]].frame.time<=target then low=middle else high=middle-1 end
        end
        return path[low]
    end
    function Model.summary(app)
        local tree=app.tree
        local id=tree and tree.cursor or 0
        local tip=app.path and app.path[#app.path] or id
        local finish=tree and tree.nodes[tip]
        local duration=finish and finish.frame.time or 0
        return {mode=if app.busy then "preparing" else app.mode,map=app.map.name or "Waiting for map…",
            node=id,nodes=tree and #tree.nodes or 0,time=app.time or 0,duration=duration,
            progress=if duration>0 then math.clamp((app.time or 0)/duration,0,1) else 0}
    end
    return Model
end

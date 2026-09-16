return function(import)
    local Q=import("core/Quaternion")
    local Sampling={}
    local function lerp(a,b,t) return a+(b-a)*t end
    local function transform(a,b,t)
        local q=Q.slerp({a[4],a[5],a[6],a[7]},{b[4],b[5],b[6],b[7]},t)
        return {lerp(a[1],b[1],t),lerp(a[2],b[2],t),lerp(a[3],b[3],t),q[1],q[2],q[3],q[4]}
    end
    function Sampling.at(tree,path,time)
        assert(#path>0,"Empty branch")
        local low,high=1,#path
        while low<high do
            local middle=math.ceil((low+high)/2)
            if tree.nodes[path[middle]].frame.time<=time then low=middle else high=middle-1 end
        end
        local a=tree.nodes[path[low]].frame
        local nextID=path[low+1]
        if not nextID or time<=a.time then return a,low end
        local b=tree.nodes[nextID].frame
        local t=math.clamp((time-a.time)/(b.time-a.time),0,1)
        local f=table.clone(a)
        f.root=transform(a.root,b.root,t); f.camera=transform(a.camera,b.camera,t)
        f.time=time
        for _,name in ipairs({"velocity","angular"}) do
            f[name]={lerp(a[name][1],b[name][1],t),lerp(a[name][2],b[name][2],t),lerp(a[name][3],b[name][3],t)}
        end
        f.tracks={}
        for i,track in ipairs(a.tracks) do
            local sample=table.clone(track)
            local other=b.tracks[i]
            if other and other.id==track.id and other.time>=track.time then
                sample.time=lerp(track.time,other.time,t)
            end
            table.insert(f.tracks,sample)
        end
        return f,low
    end
    return Sampling
end

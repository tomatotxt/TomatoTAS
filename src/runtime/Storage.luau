return function(import,config)
    local Codec=import("core/Codec")
    local Storage={}
    local function path(name)
        assert(type(name)=="string" and #name>0 and #name<=100 and name:match("^[%w_%-]+$"),
            "Run filename must contain only letters, numbers, underscores or hyphens")
        assert(config.Directory:match("^[%w_%-]+$"),"Directory must be a simple relative folder name")
        return config.Directory.."/"..name..".fe2tomatas"
    end
    function Storage.save(name,tree)
        local target=path(name)
        local bytes=Codec.encode(tree)
        Codec.decode(bytes) -- validate before touching the existing file
        if not isfolder(config.Directory) then makefolder(config.Directory) end
        if isfile(target) then writefile(target..".bak",readfile(target)) end
        local staging=target..".pending"
        writefile(staging,bytes)
        assert(readfile(staging)==bytes,"Staging write verification failed")
        writefile(target,bytes)
        assert(readfile(target)==bytes,"Final write verification failed; previous file retained as .bak")
        delfile(staging)
        return target,#bytes
    end
    function Storage.load(name)
        local target=path(name)
        assert(isfile(target),"Run file not found: "..target)
        return Codec.decode(readfile(target))
    end
    function Storage.list()
        if not isfolder(config.Directory) then return {} end
        local result={}
        for _,file in ipairs(listfiles(config.Directory)) do
            if file:sub(-11)==".fe2tomatas" then table.insert(result,file) end
        end
        table.sort(result)
        return result
    end
    return Storage
end

return function(import,config)
    local Codec=import("core/Codec")
    local Storage={}
    local suffixes={primary="",backup=".bak",pending=".pending"}
    local function path(name)
        assert(type(name)=="string" and #name>0 and #name<=100 and name:match("^[%w_%-]+$"),
            "Run filename must contain only letters, numbers, underscores or hyphens")
        assert(type(config.Directory)=="string" and config.Directory:match("^[%w_%-]+$"),"Directory must be a simple relative folder name")
        return config.Directory.."/"..name..".fe2tomatas"
    end
    function Storage.save(name,tree)
        local target=path(name)
        local bytes=Codec.encode(tree)
        -- encode validates the complete frame/tree schema before returning bytes.
        if not isfolder(config.Directory) then makefolder(config.Directory) end
        local staging=target..".pending"
        writefile(staging,bytes)
        assert(readfile(staging)==bytes,"Staging write verification failed")
        local previous
        if isfile(target) then
            local old=readfile(target)
            if pcall(Codec.validate,old) then
                writefile(target..".bak",old)
                assert(readfile(target..".bak")==old,"Backup write verification failed; original run is untouched")
                previous=old
            else
                warn("[TomatoTAS] Existing run is corrupt; preserving any older .bak file.")
            end
        end
        local ok,err=pcall(function()
            writefile(target,bytes)
            assert(readfile(target)==bytes,"Final write verification failed")
        end)
        if not ok then
            local restored=false
            if previous then
                restored=pcall(function()
                    writefile(target,previous)
                    assert(readfile(target)==previous,"Rollback write failed")
                end)
            end
            error(tostring(err)..(if restored then "; original run restored; new data retained in .pending"
                else "; inspect .pending and .bak recovery files"),0)
        end
        local removed=pcall(delfile,staging)
        if not removed then warn("[TomatoTAS] Run saved and verified; temporary .pending file could not be removed.") end
        return target,#bytes
    end
    function Storage.load(name,source)
        source=source or "primary"
        assert(suffixes[source]~=nil,"Recovery source must be primary, backup or pending")
        local target=path(name)..suffixes[source]
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

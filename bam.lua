Import("configure.lua")

--- Setup Config -------
config = NewConfig()
config:Add(OptCCompiler("compiler"))
config:Add(OptLibrary("zlib", "zlib.h", false))
config:Finalize("config.lua")

-- data compiler
function Script(name) return "python " .. name end

function CHash(output, ...) -- used in generated files only
    local inputs = TableFlatten({ ... })

    output = Path(output)

    -- compile all the files
    local cmd = Script("scripts/cmd5.py") .. " "
    for index, inname in ipairs(inputs) do
        cmd = cmd .. Path(inname) .. " "
    end

    cmd = cmd .. " > " .. output

    AddJob(output, "cmd5 " .. output, cmd)
    for index, inname in ipairs(inputs) do
        AddDependency(output, inname)
    end
    AddDependency(output, "scripts/cmd5.py")
    return output
end

function ResCompile(scriptfile)
    scriptfile = Path(scriptfile)
    if config.compiler.driver == "cl" then
        output = PathBase(scriptfile) .. ".res"
        AddJob(output, "rc " .. scriptfile, "rc /fo " .. output .. " " .. scriptfile)
    elseif config.compiler.driver == "gcc" then
        output = PathBase(scriptfile) .. ".coff"
        AddJob(output, "windres " .. scriptfile, "windres -i " .. scriptfile .. " -o " .. output)
    end
    AddDependency(output, scriptfile)
    return output
end

--[[function Dat2c(datafile, sourcefile, arrayname)
    datafile = Path(datafile)
    sourcefile = Path(sourcefile)

    AddJob(
        sourcefile,
        "dat2c " .. PathFilename(sourcefile) .. " = " .. PathFilename(datafile),
        Script("scripts/dat2c.py") .. "\" " .. sourcefile .. " " .. datafile .. " " .. arrayname)
    AddDependency(sourcefile, datafile)
    return sourcefile
    end]]

function ContentCompile(action, output)
    output = Path(output)
    AddJob(
        output,
        action .. " > " .. output,
        Script("datasrc/compile.py") .. " " .. action .. " > " .. Path(output)
    )
    AddDependency(output, Path("datasrc/content.py")) -- do this more proper
    AddDependency(output, Path("datasrc/network.py"))
    AddDependency(output, Path("datasrc/compile.py"))
    AddDependency(output, Path("datasrc/datatypes.py"))
    return output
end

-- Content Compile
network_source = ContentCompile("network_source", "src/game/generated/protocol.cpp")
network_header = ContentCompile("network_header", "src/game/generated/protocol.h")
server_content_source = ContentCompile("server_content_source", "src/game/generated/server_data.cpp")
server_content_header = ContentCompile("server_content_header", "src/game/generated/server_data.h")

AddDependency(network_source, network_header)
AddDependency(server_content_source, server_content_header)

nethash = CHash("src/game/generated/nethash.cpp", "src/engine/shared/protocol.h", "src/game/generated/protocol.h",
    "src/game/tuning.h", "src/game/gamecore.cpp", network_header)

function Intermediate_Output(settings, input)
    return "objs/" .. string.sub(PathBase(input), string.len("src/") + 1) .. settings.config_ext
end

function build(settings)
    -- apply compiler settings
    config.compiler:Apply(settings)

    --settings.objdir = Path("objs")
    settings.cc.Output = Intermediate_Output

    if config.compiler.driver == "cl" then
        settings.cc.flags:Add("/wd4244", "/wd4577")
    else
        settings.cc.flags:Add("-Wall", "-fno-exceptions")
        settings.link.flags:Add("-fstack-protector", "-fstack-protector-all")
    end
    settings.cc.includes:Add("src")

    if family == "unix" then
        settings.link.libs:Add("pthread")
        -- add ICU for linux
        if ExecuteSilent("pkg-config icu-uc icu-i18n") == 0 then
        end

        settings.cc.flags:Add("`pkg-config --cflags icu-uc icu-i18n`")
        settings.link.flags:Add("`pkg-config --libs icu-uc icu-i18n`")
    end

    -- compile zlib if needed
    --[[if config.zlib.value == 1 then
        settings.link.libs:Add("z")
        if config.zlib.include_path then
            settings.cc.includes:Add(config.zlib.include_path)
        end
        zlib = {}]]
    --else
    zlib = Compile(settings, Collect("src/engine/external/zlib/*.c"))
    settings.cc.includes:Add("src/engine/external/zlib")
    --end

    -- build the small libraries
    json = Compile(settings, "src/engine/external/json-parser/json.c")
    md5 = Compile(settings, Collect("src/engine/external/md5/*.c"))

    -- build game components
    engine_settings = settings:Copy()
    server_settings = engine_settings:Copy()
    launcher_settings = engine_settings:Copy()
    --
    engine = Compile(engine_settings, Collect("src/engine/shared/*.cpp", "src/base/*.c"))
    server = Compile(server_settings, Collect("src/engine/server/*.cpp"))
    teeuniverses = Compile(server_settings,
        Collect("src/teeuniverses/*.cpp", "src/teeuniverses/components/*.cpp", "src/teeuniverses/system/*.cpp"))

    game_shared = Compile(settings, Collect("src/game/*.cpp"), nethash, network_source)
    game_server = Compile(settings, CollectRecursive("src/game/server/*.cpp"), server_content_source)
    -- build server
    server_exe = Link(server_settings, "teeworlds_srv", engine, server,
        game_shared, game_server, zlib, md5, server_link_other, json, teeuniverses)

    -- make targets
    s = PseudoTarget("server" .. "_" .. settings.config_name, server_exe, serverlaunch, icu_depends)

    all = PseudoTarget(settings.config_name, c, s, v, m, t)
    return all
end

debug_settings = NewSettings()
debug_settings.config_name = "debug"
debug_settings.config_ext = "_d"
debug_settings.debug = 1
debug_settings.optimize = 0
debug_settings.cc.defines:Add("CONF_DEBUG")

release_settings = NewSettings()
release_settings.config_name = "release"
release_settings.config_ext = ""
release_settings.debug = 0
release_settings.optimize = 1
release_settings.cc.defines:Add("CONF_RELEASE")

build(debug_settings)
build(release_settings)
DefaultTarget("server_debug")

using Maple, YAML, ZipFile, ArgParse

const mapBinLocationCache = Dict{String,Any}()

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--directory", "-d"
            help = "The directory to download all the mods that depend on the helper into"
            arg_type = String
        "--helper-prefix", "-p"
            help = "The prefix the helper's entities have in their Lönn/Ahorn plugins if different from the helper name"
            arg_type = String
        "--dependency-graph-yaml", "-g"
            help = "The location of mod_dependency_graph.yaml if you want to use a local copy instead of downloading an up to date verison every time"
            arg_type = String
        "--everest-update-yaml", "-u"
            help = "The location of everest_update.yaml if you want to use a local copy instead of downloading an up to date verison every time"
            arg_type = String
        "--skip-updates", "-x"
            help = "Whether to skip updating already downloaded mods, and if possible also the dependency graph"
            action = :store_true
        "--keep-zips", "-z"
            help = "Whether to keep the full zip files of downloaded mods, rather than deleting them right after they get extracted **(NOT RECOMMENDED, causes multiple gigabytes of unnecessary bloat)** "
            action = :store_true
        "helper-name"
            help = "The name of the helper to search for, as specifed in its everest.yaml"
            arg_type = String
            required = true
    end

    return parse_args(s)
end

logIO = IOBuffer()
resultIO = IOBuffer()

# printstyled copy which also writes everything to a log file
# very janky but it works so Whatever
function printcolored(xs...; bold::Bool=false, italic::Bool=false, underline::Bool=false, blink::Bool=false, reverse::Bool=false, hidden::Bool=false, color::Union{Symbol,Int}=:normal, result::Bool=false)
    printstyled(xs...; bold, italic, underline, blink, reverse, hidden, color)
    print(logIO, xs...;)
    if (result != false)
        print(resultIO, xs...;)
    end
end

# stolen and slightly modified version of this
# https://discourse.julialang.org/t/how-to-extract-a-file-in-a-zip-archive-without-using-os-specific-tools/34585
function unzip(file, modName, exdir="", overwrite=false)
    fileFullPath = isabspath(file) ? file : joinpath(pwd(), file)
    basePath = dirname(fileFullPath)
    outPath = (exdir == "" ? basePath : (isabspath(exdir) ? exdir : joinpath(pwd(), exdir)))
    isdir(outPath) ? "" : mkdir(outPath)
    zarchive = ZipFile.Reader(fileFullPath)
    for f in zarchive.files
        fileFullPath = joinpath(outPath, f.name)
        # only extracts map bins and everest.yaml to save space
        if ((startswith(f.name, "Maps") && endswith(f.name, ".bin")) || f.name == "everest.yaml" || f.name == "everest.yml")
            if (!isfile(fileFullPath) || overwrite == true)
                printcolored("extracting ")
                printcolored(joinpath(modName, f.name), bold=true, color=:light_cyan)
                printcolored("...\n")

                mkpath(dirname(fileFullPath))
                write(fileFullPath, read(f))
            else
                printcolored(joinpath(modName, f.name), bold=true, color=:light_cyan)
                printcolored(" already exists, skipping...\n", color=:yellow)
            end
        end
    end
    close(zarchive)
end

function main()
    parsed_args = parse_commandline()

    helperName = parsed_args["helper-name"]
    helperPrefix = !isnothing(parsed_args["helper-prefix"]) ? parsed_args["helper-prefix"] : helperName
    dir = !isnothing(parsed_args["directory"]) ? parsed_args["directory"] : joinpath(pwd(), "FindHelperUsesDownloads")
    dependencyGraphPath = !isnothing(parsed_args["dependency-graph-yaml"]) ? parsed_args["dependency-graph-yaml"] : joinpath(dir, "mod_dependency_graph.yaml")
    everestUpdatePath = !isnothing(parsed_args["everest-update-yaml"]) ? parsed_args["everest-update-yaml"] : joinpath(dir, "everest_update.yaml")
    keepZips = parsed_args["keep-zips"]
    skipUpdates = parsed_args["skip-updates"]
    
    # used to show stats at the end of the script
    totalEntityCounts = Dict{String,Integer}()
    totalEntityCount = 0
    totalMapCount = 0
    totalModCount = 0
    
    mkpath(dir)
    
    if (isnothing(parsed_args["dependency-graph-yaml"]) && (!skipUpdates || !isfile(dependencyGraphPath)))
        printcolored("downloading latest mod_dependency_graph.yaml...\n")
        download("https://maddie480.ovh/celeste/mod_dependency_graph.yaml", dependencyGraphPath)
    end
    
    if (isnothing(parsed_args["everest-update-yaml"]) && (!skipUpdates || !isfile(everestUpdatePath)))
        printcolored("downloading latest everest_update.yaml...\n")
        download("https://maddie480.ovh/celeste/everest_update.yaml", everestUpdatePath)
    end
    
    everestUpdate = YAML.load_file(everestUpdatePath)
    dependencyGraph = YAML.load_file(dependencyGraphPath)
    
    cd(dir)

    # main code here

    # mod downloader
    for (modName, modData) in dependencyGraph
        # this mod has like i think every helper in its dependencies + a broken version number which is Fun
        if modName == "UDAllHelper"
            continue
        end

        helperFound = false
        for dependency in modData["Dependencies"]
            if dependency["Name"] == helperName
                helperFound = true
                printcolored("found ")
                printcolored("$helperName", bold=true, color=:light_green)
                printcolored(" in dependencies for ")
                printcolored("$modName", bold=true, color=:light_blue)
                printcolored("!\n")
            end
        end
        if helperFound == true
            totalModCount += 1

            # check if mod needs to be updated
            modOutOfDate = false
            everestYamlPath = joinpath(modName, "everest.yaml")
            if (isfile(joinpath(modName, "everest.yml")))
                everestYamlPath = joinpath(modName, "everest.yml")
            end
            if (isfile(everestYamlPath) && !skipUpdates)
                everestYaml = YAML.load_file(everestYamlPath)
                
                # shouldnt need to have a try catch here but some everest.yamls have bad version numbers so
                modVersion = v"0.0.0"
                latestVersion = v"1.0.0"

                try
                    modVersion = VersionNumber(first(everestYaml)["Version"])
                    latestVersion = VersionNumber(everestUpdate[modName]["Version"])
                catch
                    printcolored("ERROR: ", bold=true, color=:red)
                    printcolored("$modName", bold=true, color=:light_blue)
                    printcolored(" has bad version! skipping update check and redownloading anyway.\n", bold=true, color=:red)
                end

                if (modVersion < latestVersion)
                    printcolored("version ", color=:yellow)
                    printcolored("$modVersion", bold=true, color=:red)
                    printcolored(" of ", color=:yellow)
                    printcolored("$modName", bold=true, color=:light_blue)
                    printcolored(" is outdated! updating...\n", color=:yellow)
                    modOutOfDate = true
                end
            end

            if (!isfile(everestYamlPath) || modOutOfDate)
                printcolored("downloading ")
                printcolored("$modName.zip", bold=true, color=:light_blue)
                printcolored("...\n")

                # try mirror if gb fails
                try
                    download(everestUpdate[modName]["URL"], modName * ".zip")
                catch
                    printcolored("failed to download from gamebanana, trying mirror...\n", color=:yellow)

                    try
                        download(everestUpdate[modName]["MirrorURL"], modName * ".zip")
                    catch
                        printcolored("ERROR: download failed! this is very bad! skipping mod.\n", bold=true, color=:red)
                        continue
                    end
                end

                # printcolored("downloaded ")
                # printcolored("$modName.zip", bold=true, color=:light_blue)
                # printcolored(".\n")

                printcolored("unzipping ")
                printcolored("$modName.zip", bold=true, color=:light_blue)
                printcolored("...\n")
                # also shouldnt need a try catch here but apparently sometimes ppl upload bad zips as well
                try
                    unzip(modName * ".zip", modName, modName, modOutOfDate)
                catch
                    printcolored("ERROR: ", bold=true, color=:red)
                    printcolored("$modName.zip", bold=true, color=:light_blue)
                    printcolored(" is broken! this is very bad! skipping mod.\n", bold=true, color=:red)
                    delete!(mapBinLocationCache, modName)
                    rm(modName * ".zip")
                    continue
                end
                
                printcolored("finished extracting ")
                printcolored("$modName.zip", bold=true, color=:light_blue)
                printcolored("!\n")

                if (!keepZips)
                    rm(modName * ".zip")
                end
            else
                printcolored("$modName ", bold=true, color=:light_blue)
                printcolored("already exists and is up to date, skipping download...\n", color=:yellow)
            end

            # cache map bin locations for later
            mapBinLocationCache[modName] = String[]

            for (folder, dirs, files) in walkdir(modName), file in files
                file = joinpath(folder, file)
                if (contains(file, "Maps") && endswith(file, ".bin"))
                    push!(mapBinLocationCache[modName], file)
                    # printcolored("cached location of ")
                    # printcolored(file, bold=true, color=:light_cyan)
                    # printcolored("...\n")
                end
            end
        end
    end

    if (totalModCount <= 0)
        printcolored("ERROR: couldn't find any mods with ", bold=true, color=:red)
        printcolored(helperName, bold=true, color=:green)
        printcolored(" as a dependency, exiting.\n", bold=true, color=:red)

        exit(0)
    end

    printcolored("finished downloading files!\n", bold=true, color=:light_green)

    # map searcher
    printcolored("searching bin files for matches...\n", bold=true, color=:light_yellow)
    for (modName, modFiles) in mapBinLocationCache, file in modFiles
        side = loadSide(file)
        totalMapCount += 1
        for room in side.map.rooms, entity in room.entities
            if occursin(helperPrefix, entity.name)
                totalEntityCount += 1
                printcolored("[", bold=true, result=true)
                printcolored("$modName ", bold=true, color=:blue, result=true)
                printcolored("$file", bold=true, color=:light_cyan, result=true)
                printcolored("] ", bold=true, result=true)
                printcolored(entity.name, bold=true, color=:light_green, result=true)
                printcolored(" found at position ", result=true)
                printcolored(entity.x, bold=true, color=:light_yellow, result=true)
                printcolored(",", result=true)
                printcolored(entity.y, bold=true, color=:light_yellow, result=true)
                printcolored(" in room ", result=true)
                printcolored(room.name, bold=true, color=:light_red, result=true)
                printcolored("!\n", result=true)

                if !haskey(totalEntityCounts, entity.name)
                    totalEntityCounts[entity.name] = 0
                end
                totalEntityCounts[entity.name] += 1
            end
        end
    end

    printcolored("\n", result=true)

    for (entityName, entityCount) in sort(collect(totalEntityCounts), by=last)
        entityPercent = (entityCount / totalEntityCount) * 100
        printcolored("found ", bold=true, result=true)
        printcolored("$entityCount", bold=true, color=:light_yellow, result=true)
        printcolored(" placements of ", bold=true, result=true)
        printcolored("$entityName", bold=true, color=:blue, result=true)
        printcolored(", accounting for ", bold=true, result=true)
        printcolored(round(entityPercent, digits=4), bold=true, color=:light_cyan, result=true)
        printcolored("% of ", bold=true, result=true)
        printcolored(helperName, bold=true, color=:light_green, result=true)
        printcolored(" entities in maps.\n", bold=true, result=true)
    end

    printcolored("\n", result=true)

    printcolored("total ", bold=true, result=true)
    printcolored("$totalEntityCount", bold=true, color=:light_green, result=true)
    printcolored(" entities found in ", bold=true, result=true)
    printcolored("$totalMapCount", bold=true, color=:light_cyan, result=true)
    printcolored(" maps across ", bold=true, result=true)
    printcolored("$totalModCount", bold=true, color=:blue, result=true)
    printcolored(" mods.\n", bold=true, result=true)

    write("log.txt", String(take!(logIO)))
    write("result-$helperName.txt", String(take!(resultIO)))
end

main()

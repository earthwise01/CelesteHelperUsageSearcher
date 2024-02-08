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
    totalTriggerCounts = Dict{String,Integer}()
    totalTriggerCount = 0
    totalEffectCounts = Dict{String,Integer}()
    totalEffectCount = 0
    totalMaps = Dict{String,Any}()
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
                    printcolored("ERROR: unzipping ", bold=true, color=:red)
                    printcolored("$modName.zip", bold=true, color=:light_blue)
                    printcolored(" failed! this is very bad! skipping mod.\n", bold=true, color=:red)
                    delete!(mapBinLocationCache, modName)
                    # rm(modName * ".zip")
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
        mapName = replace(file, "$modName/Maps/" => "")

        for room in side.map.rooms
            for entity in room.entities
                if occursin(helperPrefix, entity.name)
                    totalEntityCount += 1
                    if !haskey(totalMaps, mapName)
                        totalMaps[mapName] = Dict{String,Integer}()
                    end
                    if !haskey(totalMaps[mapName], entity.name)
                        totalMaps[mapName][entity.name] = 0
                    end
                    totalMaps[mapName][entity.name] += 1

                    # printcolored("[", bold=true, result=true)
                    # printcolored("$modName ", bold=true, color=:blue, result=true)
                    # printcolored("$mapName", bold=true, color=:light_cyan, result=true)
                    # printcolored("] ", bold=true, result=true)
                    # printcolored("found ", result=true)
                    # printcolored(entity.name, bold=true, color=:light_green, result=true)
                    # printcolored(" at position ", result=true)
                    # printcolored(entity.x, bold=true, color=:light_yellow, result=true)
                    # printcolored(",", result=true)
                    # printcolored(entity.y, bold=true, color=:light_yellow, result=true)
                    # printcolored(" in room ", result=true)
                    # printcolored(room.name, bold=true, color=:light_red, result=true)
                    # printcolored("!\n", result=true)

                    if !haskey(totalEntityCounts, entity.name)
                        totalEntityCounts[entity.name] = 0
                    end
                    totalEntityCounts[entity.name] += 1
                end
            end
            for trigger in room.triggers
                if occursin(helperPrefix, trigger.name)
                    totalTriggerCount += 1
                    if !haskey(totalMaps, mapName)
                        totalMaps[mapName] = Dict{String,Integer}()
                    end
                    if !haskey(totalMaps[mapName], trigger.name)
                        totalMaps[mapName][trigger.name] = 0
                    end
                    totalMaps[mapName][trigger.name] += 1

                    # printcolored("[", bold=true, result=true)
                    # printcolored("$modName ", bold=true, color=:blue, result=true)
                    # printcolored("$mapName", bold=true, color=:light_cyan, result=true)
                    # printcolored("] ", bold=true, result=true)
                    # printcolored("found ", result=true)
                    # printcolored(trigger.name, bold=true, color=:light_green, result=true)
                    # printcolored(" at position ", result=true)
                    # printcolored(trigger.x, bold=true, color=:light_yellow, result=true)
                    # printcolored(",", result=true)
                    # printcolored(trigger.y, bold=true, color=:light_yellow, result=true)
                    # printcolored(" in room ", result=true)
                    # printcolored(room.name, bold=true, color=:light_red, result=true)
                    # printcolored("!\n", result=true)

                    if !haskey(totalTriggerCounts, trigger.name)
                        totalTriggerCounts[trigger.name] = 0
                    end
                    totalTriggerCounts[trigger.name] += 1
                end
            end
        end
        for fg in side.map.style.foregrounds
            if fg isa Effect && occursin(helperPrefix, fg.name)
                totalEffectCount += 1
                if !haskey(totalMaps, mapName)
                    totalMaps[mapName] = Dict{String,Integer}()
                end
                if !haskey(totalMaps[mapName], fg.name)
                    totalMaps[mapName][fg.name] = 0
                end
                totalMaps[mapName][fg.name] += 1

                # printcolored("[", bold=true, result=true)
                # printcolored("$modName ", bold=true, color=:blue, result=true)
                # printcolored("$mapName", bold=true, color=:light_cyan, result=true)
                # printcolored("] ", bold=true, result=true)
                # printcolored("found ", result=true)
                # printcolored(fg.name, bold=true, color=:light_green, result=true)
                # printcolored("!\n", result=true)

                if !haskey(totalEffectCounts, fg.name)
                    totalEffectCounts[fg.name] = 0
                end
                totalEffectCounts[fg.name] += 1
            end
        end
        for bg in side.map.style.backgrounds
            if bg isa Effect && occursin(helperPrefix, bg.name)
                totalEffectCount += 1
                if !haskey(totalMaps, mapName)
                    totalMaps[mapName] = Dict{String,Integer}()
                end
                if !haskey(totalMaps[mapName], bg.name)
                    totalMaps[mapName][bg.name] = 0
                end
                totalMaps[mapName][bg.name] += 1

                # printcolored("[", bold=true, result=true)
                # printcolored("$modName ", bold=true, color=:blue, result=true)
                # printcolored("$mapName", bold=true, color=:light_cyan, result=true)
                # printcolored("] ", bold=true, result=true)
                # printcolored("found ", result=true)
                # printcolored(bg.name, bold=true, color=:light_green, result=true)
                # printcolored("!\n", result=true)

                if !haskey(totalEffectCounts, bg.name)
                    totalEffectCounts[bg.name] = 0
                end
                totalEffectCounts[bg.name] += 1
            end
        end

        if haskey(totalMaps, mapName)
            printcolored("[", bold=true, result=true)
            printcolored("$modName ", bold=true, color=:blue, result=true)
            printcolored("$mapName", bold=true, color=:light_cyan, result=true)
            printcolored("] ", bold=true, result=true)
            printcolored("found ", bold=true, result=true)

            index = 0
            for (object, count) in totalMaps[mapName]
                index += 1
                printcolored("$count ", bold=true, color=:light_yellow, result=true)
                printcolored("$object", bold=true, color=:light_green, result=true)
                if index == length(totalMaps[mapName])
                    printcolored("!\n", bold=true, result=true)
                elseif index == length(totalMaps[mapName]) - 1
                    printcolored(" and ", bold=true, result=true)
                else
                    printcolored(", ", bold=true, result=true)
                end
            end
            # printcolored("in ", bold=true, result = true)
            # printcolored("$mapName", bold=true, color=:light_cyan, result=true)
            # printcolored("!\n", bold=true, result=true)
        end
    end

    printcolored("\n", result=true)

    # for (mapName, entities) in totalMaps
    #     printcolored("[", bold=true, result = true)
    #     printcolored("$mapName", bold=true, color=:light_cyan, result=true)
    #     printcolored("] ", bold=true, result=true)
    #     printcolored("found ", bold=true, result=true)
    #     for (index, entity) in pairs(entities)
    #         printcolored("$entity", bold=true, color=:light_green, result=true)
    #         if index == length(entities)
    #             printcolored("!\n", bold=true, result=true)
    #         elseif index == length(entities) - 1
    #             printcolored(" and ", bold=true, result=true)
    #         else
    #             printcolored(", ", bold=true, result=true)
    #         end
    #     end
    #     # printcolored("in ", bold=true, result = true)
    #     # printcolored("$mapName", bold=true, color=:light_cyan, result=true)
    #     # printcolored("!\n", bold=true, result=true)
    # end

    # printcolored("\n", result=true)

    # for (entityName, entityCount) in sort(collect(totalEntityCounts), by=last)
    #     entityPercent = (entityCount / totalEntityCount) * 100
    #     printcolored("found ", bold=true, result=true)
    #     printcolored("$entityCount", bold=true, color=:light_yellow, result=true)
    #     printcolored(" placements of ", bold=true, result=true)
    #     printcolored("$entityName", bold=true, color=:blue, result=true)
    #     printcolored(", accounting for ", bold=true, result=true)
    #     printcolored(round(entityPercent, digits=4), bold=true, color=:light_cyan, result=true)
    #     printcolored("% of ", bold=true, result=true)
    #     printcolored(helperName, bold=true, color=:light_green, result=true)
    #     printcolored(" entities in maps.\n", bold=true, result=true)
    # end

    # for (triggerName, triggerCount) in sort(collect(totalTriggerCounts), by=last)
    #     triggerPercent = (triggerCount / totalTriggerCount) * 100
    #     printcolored("found ", bold=true, result=true)
    #     printcolored("$triggerCount", bold=true, color=:light_yellow, result=true)
    #     printcolored(" placements of ", bold=true, result=true)
    #     printcolored("$triggerName", bold=true, color=:blue, result=true)
    #     printcolored(", accounting for ", bold=true, result=true)
    #     printcolored(round(triggerPercent, digits=4), bold=true, color=:light_cyan, result=true)
    #     printcolored("% of ", bold=true, result=true)
    #     printcolored(helperName, bold=true, color=:light_green, result=true)
    #     printcolored(" triggers in maps.\n", bold=true, result=true)
    # end

    # for (effectName, effectCount) in sort(collect(totalEffectCounts), by=last)
    #     effectPercent = (effectCount / totalEffectCount) * 100
    #     printcolored("found ", bold=true, result=true)
    #     printcolored("$effectCount", bold=true, color=:light_yellow, result=true)
    #     printcolored(" uses of ", bold=true, result=true)
    #     printcolored("$effectName", bold=true, color=:blue, result=true)
    #     printcolored(", accounting for ", bold=true, result=true)
    #     printcolored(round(effectPercent, digits=4), bold=true, color=:light_cyan, result=true)
    #     printcolored("% of ", bold=true, result=true)
    #     printcolored(helperName, bold=true, color=:light_green, result=true)
    #     printcolored(" styleground effects in maps.\n", bold=true, result=true)
    # end
    totalCounts = Dict{String, Integer}()
    for (entity, count) in totalEntityCounts
        totalCounts[entity] = count
    end
    for (trigger, count) in totalTriggerCounts
        totalCounts[trigger] = count
    end
    for (effect, count) in totalEffectCounts
        totalCounts[effect] = count
    end
    totalCount = totalEntityCount + totalTriggerCount + totalEffectCount

    for (objectName, objectCount) in sort(collect(totalCounts), by=last)
        usagePercent = (objectCount / totalCount) * 100
        printcolored("found ", bold=true, result=true)
        printcolored("$objectCount", bold=true, color=:light_yellow, result=true)
        printcolored(" uses of ", bold=true, result=true)
        printcolored("$objectName", bold=true, color=:blue, result=true)
        printcolored(", accounting for ", bold=true, result=true)
        printcolored(round(usagePercent, digits=4), bold=true, color=:light_cyan, result=true)
        printcolored("% of ", bold=true, result=true)
        printcolored(helperName, bold=true, color=:light_green, result=true)
        printcolored(" things in maps.\n", bold=true, result=true)
    end

    printcolored("\n", result=true)

    printcolored("total ", bold=true, result=true)
    printcolored("$totalCount", bold=true, color=:light_green, result=true)
    printcolored(" things found in ", bold=true, result=true)
    printcolored("$totalMapCount", bold=true, color=:light_cyan, result=true)
    printcolored(" maps across ", bold=true, result=true)
    printcolored("$totalModCount", bold=true, color=:blue, result=true)
    printcolored(" mods.\n", bold=true, result=true)

    write("log.txt", String(take!(logIO)))
    write("result-$helperName.txt", String(take!(resultIO)))
end

main()

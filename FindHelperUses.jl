using Maple, YAML, ZipFile, ArgParse

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--helper-prefix", "-p"
            help = "The prefix the helper's entities/triggers/effects have in their SIDs, if different from the helper name"
            arg_type = String
        # todo: probably use something other than just occursin for these
        "--find-only", "-f"
            help = "A string that must be present in the helper's entity/trigger/effect SIDs"
            arg_type = String
        "--find-except", "-e"
            help = "A string that must not be present in the helper's entity/trigger/effect SIDs"
            arg_type = String
        "--find-alongside", "-a"
            help = "A string in the SID of an entity/trigger that must be in the same room as any of the helper's own entities/triggers"
            arg_type = String
        "--directory", "-d"
            help = "The directory to download all the mods that depend on the helper into"
            arg_type = String
        "--dependency-graph-yaml", "-g"
            help = "The location of mod_dependency_graph.yaml, if you want to use a local copy instead of downloading an up to date verison every time"
            arg_type = String
        "--everest-update-yaml", "-u"
            help = "The location of everest_update.yaml, if you want to use a local copy instead of downloading an up to date verison every time"
            arg_type = String
        "--skip-downloads", "-x"
            help = "Whether to skip downloading mods"
            action = :store_true
        "--keep-zips", "-z"
            help = "Whether to keep the full zip files of all downloaded mods **(NOT RECOMMENDED, uses a significant amount of storage)** "
            action = :store_true
        "helper-name"
            help = "The name of the helper to search for, as specified in its everest.yaml"
            arg_type = String
            required = true
    end

    return parse_args(s)
end

logIO = IOBuffer()
resultIO = IOBuffer()

# printstyled copy which also writes everything to a log file
# todo: make this suck less somehow
function printcolored(xs...; bold::Bool=false, italic::Bool=false, underline::Bool=false, blink::Bool=false, reverse::Bool=false, hidden::Bool=false, color::Union{Symbol,Int}=:normal, result::Bool=false)
    printstyled(xs...; bold, italic, underline, blink, reverse, hidden, color)
    print(logIO, xs...;)
    if (result)
        print(resultIO, xs...;)
    end
end

# todo: also make this suck less somehow
function printfancylist(list, newline::Bool=true, itemColor::Union{Symbol,Int}=:normal, result::Bool=false)
    local listLength = length(list)
    local i = 0
    for item in list
        printcolored(item, bold=true, color=itemColor, result=result)

        i += 1
        if (i == listLength)
            if (newline)
                printcolored(".\n", result=result)
            end
        elseif (i == listLength - 1)
            printcolored(" and ", result=result)
        else
            printcolored(", ", result=result)
        end
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
        # only extract map bins and everest.yaml to save space
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
    # arguments
    local parsed_args = parse_commandline()
    local helperName = parsed_args["helper-name"]
    local helperPrefix = something(parsed_args["helper-prefix"], helperName)
    local findOnly = parsed_args["find-only"]
    local findExcept = parsed_args["find-except"]
    local findAlongside = parsed_args["find-alongside"]
    local workingDir = something(parsed_args["directory"], joinpath(pwd(), "FindHelperUsesDownloads"))
    local dependencyGraphPath = something(parsed_args["dependency-graph-yaml"], joinpath(workingDir, "mod_dependency_graph.yaml"))
    local everestUpdatePath = something(parsed_args["everest-update-yaml"], joinpath(workingDir, "everest_update.yaml"))
    local skipDownloads = parsed_args["skip-downloads"]
    local keepZips = parsed_args["keep-zips"]

    local totalEntityCounts = Dict{String,Integer}()
    local totalEntityCount = 0
    local totalTriggerCounts = Dict{String,Integer}()
    local totalTriggerCount = 0
    local totalEffectCounts = Dict{String,Integer}()
    local totalEffectCount = 0
    local totalMapCount = 0
    local totalModCount = 0
    local skippedMods = String[]
    local skippedMaps = String[]

    local mapBinLocationCache = Dict{String,Any}()

    mkpath(workingDir)

    # download yamls
    if (isnothing(parsed_args["dependency-graph-yaml"]) && (!skipDownloads || !isfile(dependencyGraphPath)))
        printcolored("downloading latest mod_dependency_graph.yaml...\n")
        download("https://maddie480.ovh/celeste/mod_dependency_graph.yaml", dependencyGraphPath)
    end
    if (isnothing(parsed_args["everest-update-yaml"]) && (!skipDownloads || !isfile(everestUpdatePath)))
        printcolored("downloading latest everest_update.yaml...\n")
        download("https://maddie480.ovh/celeste/everest_update.yaml", everestUpdatePath)
    end
    local everestUpdate = YAML.load_file(everestUpdatePath)
    local dependencyGraph = YAML.load_file(dependencyGraphPath)

    cd(workingDir)

    # download mods if necessary + find bin files
    for (modName, modData) in dependencyGraph
        # this mod has like i think every helper in its dependencies + an unparsable version number which is Fun
        if (modName == "UDAllHelper")
            continue
        end

        local helperFound = false
        for dependency in modData["Dependencies"]
            if dependency["Name"] == helperName
                printcolored("found ")
                printcolored("$helperName", bold=true, color=:light_green)
                printcolored(" in dependencies for ")
                printcolored("$modName", bold=true, color=:light_blue)
                printcolored("!\n")

                helperFound = true
                break
            end
        end

        if helperFound
            totalModCount += 1

            # check if mod needs to be updated
            local modOutOfDate = false
            local everestYamlPath = joinpath(modName, "everest.yaml")
            if (isfile(joinpath(modName, "everest.yml")))
                everestYamlPath = joinpath(modName, "everest.yml")
            end
            if (!skipDownloads && isfile(everestYamlPath))
                everestYaml = YAML.load_file(everestYamlPath)

                local modVersionString = string(first(everestYaml)["Version"])
                local latestVersionString = string(everestUpdate[modName]["Version"])
#               local modVersion = v"0.0.0"
#               local latestVersion = v"1.0.0"
#               try
#                   modVersion = VersionNumber(modVersionString)
#                   latestVersion = VersionNumber(latestVersionString)
#               catch
#                   printcolored("WARNING: failed to parse version for ", bold=true, color=:red)
#                   printcolored("$modName ", bold=true, color=:light_blue)
#                   printcolored("(installed: ", bold=true, color=:red)
#                   printcolored("$modVersionString", bold=true, color=:yellow)
#                   printcolored(", latest: ", bold=true, color=:red)
#                   printcolored("$latestVersionString", bold=true, color=:yellow)
#                   printcolored(")! skipping update check and redownloading anyway.\n", bold=true, color=:red)
#               end
#
#               if (modVersion < latestVersion)

                # version numbers are mean and don't parse some version strings used by mods (e.g. 1.0.0.0) so just check if the strings are different
                # technicallyyy to be accurate to everest/olympus the zip hash shd be used for update checks but i don't feel like implementing that atm
                if (modVersionString != latestVersionString)
                    printcolored("version ", color=:yellow)
                    printcolored("$modVersionString", bold=true, color=:yellow)
                    printcolored(" of ", color=:yellow)
                    printcolored("$modName", bold=true, color=:light_blue)
                    printcolored(" is outdated (latest: ", color=:yellow)
                    printcolored("$latestVersionString", bold=true, color=:yellow)
                    printcolored(")! updating...\n", color=:yellow)
                    modOutOfDate = true
                end
            end

            # download mod
            if (!skipDownloads && (!isfile(everestYamlPath) || modOutOfDate))
                printcolored("downloading ")
                printcolored("$modName.zip", bold=true, color=:light_blue)
                printcolored("...\n")

                local downloadSuccessful = false
                local maxRetries = 5
                for i in 1:maxRetries
                    try
                        download(everestUpdate[modName]["URL"], modName * ".zip")
                        downloadSuccessful = true
                    catch
                        printcolored("failed to download from gamebanana, trying again ($i/$downloadAttempts)...\n", color=:yellow)
                    end

                    if (downloadSuccessful)
                        break
                    end
                end
                if (!downloadSuccessful)
                    printcolored("WARNING: downloading ", bold=true, color=:red)
                    printcolored("$modName.zip", bold=true, color=:light_blue)
                    printcolored(" failed! skipping mod!\n", bold=true, color=:red)
                    continue
                end

                printcolored("extracting ")
                printcolored("$modName.zip", bold=true, color=:light_blue)
                printcolored("...\n")
                try
                    unzip(modName * ".zip", modName, modName, modOutOfDate)
                catch
                    printcolored("WARNING: extracting ", bold=true, color=:red)
                    printcolored("$modName.zip", bold=true, color=:light_blue)
                    printcolored(" failed! skipping mod!\n", bold=true, color=:red)
                    push!(skippedMods, modName)
                    # keep the zip so it can possibly be extracted manually
                    # rm("$modName.zip")
                    continue
                end
                printcolored("finished extracting ")
                printcolored("$modName.zip", bold=true, color=:light_blue)
                printcolored("!\n")

                if (!keepZips)
                    rm("$modName.zip")
                end
            elseif (isfile(everestYamlPath))
                printcolored("$modName ", bold=true, color=:light_blue)
                printcolored("already exists and is up to date, skipping download...\n", color=:yellow)
            end

            # cache map bin locations for later
            if (isdir(modName))
                mapBinLocationCache[modName] = String[]
                for (path, dirs, files) in walkdir(modName), file in files
                    file = joinpath(path, file)
                    if (contains(file, "Maps") && endswith(file, ".bin"))
                        push!(mapBinLocationCache[modName], file)
                    end
                end
            end
        end
    end

    if (totalModCount <= 0)
        printcolored("couldn't find any mods with ", bold=true, color=:red)
        printcolored(helperName, bold=true, color=:green)
        printcolored(" as a dependency! exiting...\n", bold=true, color=:red)

        exit(0)
    end

    printcolored("finished downloading mods!\n", bold=true, color=:light_green)

    # search bin files for entity/triggers/effects
    printcolored("searching bin files for matches...\n", bold=true, color=:light_yellow)
    for (modName, modFiles) in sort(collect(mapBinLocationCache), by=bins->uppercase(bins[1])), file in modFiles
        local mapName = replace(file, "$modName/Maps/" => "")
        local side
        try
            side = loadSide(file)
        catch
            printcolored("WARNING: loading ", bold=true, color=:red)
            printcolored("$mapName", bold=true, color=:light_blue)
            printcolored(" failed! skipping map!\n", bold=true, color=:red)
            push!(skippedMaps, mapName)
            continue
        end
        totalMapCount += 1

        # if different or more specific checks (e.g. for specific entitydata attributes) are wanted feel free to manually edit any of thiss
        # i would be lying if i said i always just used the default logic with findOnly/findExcept/findAlongside as is   there is usually somee level of manually editing the checks
        # this is probably the most relevant part of the code if you're trying to actually use it for anything

        local function checkname(objectName)
            return occursin(helperPrefix, objectName) && (isnothing(findOnly) || occursin(findOnly, objectName)) && (isnothing(findExcept) || !occursin(findExcept, objectName))
        end

        local mapObjectCounts = Dict{String,Integer}()
        local function updatecounts(objectName, totalCount, countsDict)
            if (!haskey(mapObjectCounts, objectName))
                mapObjectCounts[objectName] = 0
            end
            mapObjectCounts[objectName] += 1

            if (!haskey(countsDict, objectName))
                countsDict[objectName] = 0
            end
            countsDict[objectName] += 1

            return totalCount + 1
        end

        # check effects
        for fg in side.map.style.foregrounds
            if (isa(fg, Effect) && checkname(fg.name))
                totalEffectCount = updatecounts(fg.name, totalEffectCount, totalEffectCounts)
            end
        end
        for bg in side.map.style.backgrounds
            if (isa(bg, Effect) && checkname(bg.name))
                totalEffectCount = updatecounts(bg.name, totalEffectCount, totalEffectCounts)
            end
        end

        # check entities/triggers
        for room in side.map.rooms
            # handle findAlongside
            if (!isnothing(findAlongside))
                local roomObjectTypes = Set{String}()
                local findAlongsideTypes = Set{String}()

                for entity in room.entities
                    if (checkname(entity.name))
                        push!(roomObjectTypes, entity.name)
                    end
                    if (occursin(findAlongside, entity.name))
                        push!(findAlongsideTypes, entity.name)
                    end
                end
                for trigger in room.triggers
                    if (checkname(trigger.name))
                        push!(roomObjectTypes, trigger.name)
                    end
                    if (occursin(findAlongside, trigger.name))
                        push!(findAlongsideTypes, trigger.name)
                    end
                end

                # print findAlongside results
                if (length(findAlongsideTypes) > 0 && length(roomObjectTypes) > 0)
                    printcolored("[", bold=true, result=true)
                    printcolored("$modName ", bold=true, color=:blue, result=true)
                    printcolored("$mapName", bold=true, color=:light_cyan, result=true)
                    printcolored("] ", bold=true, result=true)
                    printcolored("found ", result=true)
                    printfancylist(findAlongsideTypes, false, :light_green, true)
                    printcolored(" alongside ", result=true)
                    printfancylist(roomObjectTypes, false, :light_green, true)
                    printcolored(" in room ", result=true)
                    printcolored(room.name, bold=true, color=:light_red, result=true)
                    printcolored("!\n", result=true)
                end

                continue
            end

            # normal checks
            for entity in room.entities
                if (checkname(entity.name))
                    totalEntityCount = updatecounts(entity.name, totalEntityCount, totalEntityCounts)
                end
            end
            for trigger in room.triggers
                if (checkname(trigger.name))
                    totalTriggerCount = updatecounts(trigger.name, totalTriggerCount, totalTriggerCounts)
                end
            end
        end

        # print map results
        # will be inaccurate with the current findAlongside implementation so skip if necessary
        if (isnothing(findAlongside) && length(mapObjectCounts) > 0)
            printcolored("[", bold=true, result=true)
            printcolored("$modName ", bold=true, color=:blue, result=true)
            printcolored("$mapName", bold=true, color=:light_cyan, result=true)
            printcolored("] ", bold=true, result=true)
            printcolored("found ", result=true)
            printfancylist(collect(Iterators.map(objs->"$(objs[2]) $(objs[1])", mapObjectCounts)), true, :light_green, true)
        end
    end

    printcolored("\n", result=true)

    # print final stats
    # will also be inaccurate with the current findAlongside implementation so skip if necessary
    if (isnothing(findAlongside))
        local totalCounts = Dict{String, Integer}()
        for (entity, count) in totalEntityCounts
            totalCounts[entity] = count
        end
        for (trigger, count) in totalTriggerCounts
            totalCounts[trigger] = count
        end
        for (effect, count) in totalEffectCounts
            totalCounts[effect] = count
        end
        local totalCount = totalEntityCount + totalTriggerCount + totalEffectCount
        for (objectName, objectCount) in sort(collect(totalCounts), by=last)
            usagePercent = (objectCount / totalCount) * 100
            printcolored("found ", result=true)
            printcolored("$objectCount", bold=true, color=:light_yellow, result=true)
            if (objectCount > 1)
                printcolored(" uses of ", result=true)
            else
                printcolored(" use of ", result=true)
            end
            printcolored("$objectName", bold=true, color=:blue, result=true)
            printcolored(", accounting for ", result=true)
            printcolored(round(usagePercent, digits=4), bold=true, color=:light_cyan, result=true)
            printcolored("% of ", result=true)
            printcolored(helperName, bold=true, color=:light_green, result=true)
            printcolored(" things in maps.\n", result=true)
        end
        printcolored("total ", bold=true, result=true)
        printcolored("$totalCount", bold=true, color=:light_green, result=true)
        printcolored(" things found in ", bold=true, result=true)
        printcolored("$totalMapCount", bold=true, color=:light_cyan, result=true)
        printcolored(" maps across ", bold=true, result=true)
        printcolored("$totalModCount", bold=true, color=:blue, result=true)
        printcolored(" mods.\n", bold=true, result=true)
    end

    # print skips
    local modSkipCount = length(skippedMods)
    if (modSkipCount > 0)
        printcolored("Skipped ", bold=true, color=:red, result=true)
        printcolored("$modSkipCount ", bold=true, color=:yellow, result=true)
        printcolored("mods due to errors while loading: ", bold=true, color=:red, result=true)
        printfancylist(skippedMods, true, :light_blue, true)
    end
    local mapSkipCount = length(skippedMaps)
    if (mapSkipCount > 0)
        printcolored("Skipped ", bold=true, color=:red, result=true)
        printcolored("$mapSkipCount ", bold=true, color=:yellow, result=true)
        printcolored("maps due to errors while loading: ", bold=true, color=:red, result=true)
        printfancylist(skippedMaps, true, :light_blue, true)
    end

    write("log.txt", String(take!(logIO)))
    write("result-$helperName.txt", String(take!(resultIO)))
end

main()

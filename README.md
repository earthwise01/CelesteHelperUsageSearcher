# Celeste Helper Usage Searcher

small kinda janky julia script i made a while back which downloads and searches through every mod that depends on a specific helper to see which entities are used and where

originally made it either to check through every mod depending on sorbet helper before updating it ages ago or just bc i was curious which entities were being used the most, most likely the second option i think :p

fair warning, even though this makes sure to only download mods when needed and unneeded files are cleaned up after downloading so it only ends up using a couple hundred megabytes of storage at most,<br> *the very first time* you run this for a helper expect to have this running for 10-70 minutes to download up to like ~7GB worth of mods depending on how widely used the helper is so uhh good luck if you have slow internet 

(as a reference took me abt 70 mins and 7GB to download every mod needed to search for communal helper and i have pretty decent internet)

## Usage

make sure you have [Julia](https://julialang.org/), [Maple](https://github.com/CelestialCartographers/Maple), [YAML.jl](https://github.com/JuliaData/YAML.jl), [ZipFile.jl](https://github.com/fhs/ZipFile.jl), and [ArgParse.jl](https://github.com/carlobaldassi/ArgParse.jl) all installed before running the script.<br>
(don't know enough abt julia pkgs to write instructions, if you're the kind of person who'd want to waste ages downloading a bunch of mods just to figure out which helper's entities are most used you can probably figure it out yourself i hope)

`julia ./FindHelperUses.jl [--directory -d DIRECTORY] [--helper-prefix -p HELPER-PREFIX] [--dependency-graph-yaml -g DEPENDENCY-GRAPH-YAML] [--everest-update-yaml -u EVEREST-UPDATE-YAML] [--skip-updates -x] [--keep-zips -z] helper-name`

`helper-name` the name of the helper to search for, as specifed in its everest.yaml.<br>
`--helper-prefix` the prefix the helper's entities have in their Lönn/Ahorn plugins if different from the helper name. defaults to `[helper-name]`.<br>
`--directory` the directory to download all the mods that depend on the helper into. defaults to `./FindHelperUsesDownloads`.<br>
`--dependency-graph-yaml` the location of [mod_dependency_graph.yaml](https://maddie480.ovh/celeste/mod_dependency_graph.yaml) if you want to use a local copy instead of downloading an up to date verison every time.<br>
`--everest-update-yaml` the location of [everest_update.yaml](https://maddie480.ovh/celeste/everest_update.yaml) if you want to use a local copy instead of downloading an up to date verison every time.<br>
`--skip-updates` whether to skip updating already downloaded mods, and if possible also the dependency graph.<br>
`--keep-zips` whether to keep the full zip files of downloaded mods, rather than deleting them right after they get extracted. ***(NOT RECOMMENDED, causes like multiple gigabytes of unnecessary bloat)***<br>

e.g. this downloads all mods depending on `SorbetHelper` into a folder named `SorbetHelperSearch` and prints which entities each map uses<br>
`julia ./FindHelperUses.jl -d ./SorbetHelperSearch SorbetHelper`<br>

the full output of the script is put into `[directory]/log.txt` and the result of the search is put into `[directory]/result-[helper-name].txt`

### warning: probably don't run this on your mods folder bc unless you've unzipped everything for some weird reason, it'll end up deleting basically everything and leave you only with directories that just contain map bins and an everest.yaml 


## Libraries/Thingys Used
**[Maple](https://github.com/CelestialCartographers/Maple)**: used for searching through the downloaded map files<br>
**[YAML.jl](https://github.com/JuliaData/YAML.jl)**: used for reading all the needed yaml files<br>
**[ZipFile.jl](https://github.com/fhs/ZipFile.jl)**: used for extracting the downloaded mod zips<br>
**[ArgParse.jl](https://github.com/carlobaldassi/ArgParse.jl)**: used for the command line arguments<br>
**[Everest Update Checker/Dependency Graph](https://github.com/maddie480/EverestUpdateCheckerServer/blob/master/README.md)**: used for getting dependency data + download links
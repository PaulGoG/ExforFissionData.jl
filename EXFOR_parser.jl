using CSV, DataFrames, Downloads, Dates, Plots
start_time = now()
println("*begin program execution at $(Dates.format(now(), "HH:MM:SS"))")
cd(@__DIR__)
if isdir("tempData/")
    rm("tempData/", recursive=true)
end
mkdir("tempData/")
if !isdir("outputData/")
    mkdir("outputData/")
end
#######################################################################################################
#################  Initialize parameters for searching the available datasets  ########################
#######################################################################################################
truncatingDigits = 7
E_min, E_max = NaN, 1e-1
targetNucleus, reaction, quantity, xdataID, ydataID = "U-233", "n,f", "FY", "A", "yield"
#######################################################################################################
#################  Initialize tags used for filtering the available datasets  #########################
#######################################################################################################
noTags = ["RECOM"#=, "CHN"=#, "TER", "RAT"#=, "REL"=#, ",G", "-G-",
    ")/(", ")//(", "DEL", "CUM", "RAW"]
#######################################################################################################
#######################################################################################################
if quantity != "NU" && quantity != "FY" && quantity != "E" && quantity != "MFQ"
    error("Searching for quantity = $(quantity) is outside the scope of this program!")
elseif reaction != "n,f" && reaction!= "0,f"
    error("Searching for reaction = $(reaction) is outside the scope of this program!")
end
#######################################################################################################
#######################################################################################################
if xdataID == "A"
    yesTagsAND = ["MASS"]
    yesTagsOR = []
    noTags = vcat("TKE", "ELEM", "SEC", "DE", "IND", noTags)
elseif xdataID == "Ap"
    yesTagsAND = ["MASS"]
    yesTagsOR = ["SEC", "IND"]
    noTags = vcat("TKE", "ELEM", "PRE", "DE", noTags)
elseif xdataID == "Z"
    yesTagsAND = [","]
    yesTagsOR = ["ELEM", "CHG"]
    noTags = vcat("TKE", "MASS", "DE", noTags)
elseif xdataID == "E"
    yesTagsAND = [","]
    yesTagsOR = ["KE", "DE"]
    noTags = vcat("MASS", "ELEM", "TKE", "LF+HF", noTags)
elseif xdataID == "TKE"
    yesTagsAND = [","]
    yesTagsOR = ["TKE", "DE,LF+HF"]
    noTags = vcat("MASS", "ELEM", noTags)
elseif xdataID == "ZAp"
    yesTagsAND = ["MASS", "ELEM"]
    yesTagsOR = ["SEC", "IND"]
    noTags = vcat("KE", "DE", "PRE", noTags)
elseif xdataID == "ATKE"
    yesTagsAND = ["MASS"]
    yesTagsOR = ["TKE", "DE,LF+HF"]
    noTags = vcat("ELEM", noTags)
else
    error("Invalid xdataID = $(xdataID)")
end
#######################################################################################################
#######################################################################################################
if ydataID == "nu"
    yesTagsAND = vcat(yesTagsAND, "PR", "FRG") 
    noTags = vcat("MSC", noTags)
elseif ydataID == "nuPair"
    yesTagsAND = vcat(yesTagsAND, "PR") 
    noTags = vcat("MSC", noTags, "FRG")
elseif ydataID == "yield"
    if xdataID == "ATKE" || xdataID == "A"
        #yesTagsAND = vcat(yesTagsAND, "PRE") 
    end
elseif ydataID == "KE"
    yesTagsAND = vcat(yesTagsAND, "KE", "PRE")
    noTags = vcat(noTags, "LF+HF", ",N")
elseif ydataID == "KEp"
    yesTagsAND = vcat(yesTagsAND, "KE")
    noTags = vcat(noTags, "LF+HF", ",N", "PRE")
elseif ydataID == "TKE"
    yesTagsAND = vcat(yesTagsAND, "KE", "LF+HF", "PRE")
    noTags = vcat(noTags, ",N")
elseif ydataID == "TKEp"
    yesTagsAND = vcat(yesTagsAND, "KE", "LF+HF")
    noTags = vcat(noTags, ",N", "PRE")
elseif ydataID == "epsE"
    yesTagsAND = vcat(yesTagsAND, "KE", "PR", ",N")
    noTags = vcat(noTags, "PRE")
elseif ydataID == "spectrum"
    yesTagsAND = vcat(yesTagsAND, "PR", "DE")
    noTags = vcat(noTags, "/DA", "PR/", "FRG", "MXD", "MSC")
elseif ydataID == "spectrumRatioMXW"
    yesTagsAND = vcat(yesTagsAND, "PR", "DE", "MXD")
    noTags = vcat(noTags, "/DA", "PR/", "FRG")
else
    error("Invalid ydataID = $(ydataID)")
end
#######################################################################################################
#######################################################################################################
listURL = "x4list?Target=$(targetNucleus)&Reaction=$(reaction)&Quantity=$(quantity)&txt"
println("*fetching Dataset xdataID list from https://nds.iaea.org/exfor/", listURL)
targetNucleus = replace(targetNucleus, "-" => ""); reaction = replace(reaction, "," => "")
outputPATH = string(targetNucleus, '_', reaction, '_', ydataID, xdataID)
if !isdir("outputData/$(targetNucleus)/")
    mkdir("outputData/$(targetNucleus)/")
end
if isdir("outputData/$(targetNucleus)/$(outputPATH)/")
    rm("outputData/$(targetNucleus)/$(outputPATH)/", recursive=true)
end
mkdir("outputData/$(targetNucleus)/$(outputPATH)/")
mkdir("outputData/$(targetNucleus)/$(outputPATH)/X4/")
mkdir("outputData/$(targetNucleus)/$(outputPATH)/DAT/")
Downloads.download(string("https://nds.iaea.org/exfor/", listURL), 
    "tempData/DatasetList_$(outputPATH).dat"
)
DatasetList = CSV.read("tempData/DatasetList_$(outputPATH).dat", DataFrame; header=[:Item])
gr(size = (1000, 1000), dpi = 600)
dataPlot = scatter(
    title=outputPATH, xlabel=xdataID, ylabel=ydataID,
    minorgrid=true, framestyle=:box
)
if ydataID == "nu" || ydataID == "nuPair" || ydataID == "yield" || ydataID == "spectrum" || ydataID == "spectrumRatioMXW"
    scatter!(dataPlot, ylims=(0, :auto))
end
println("*begin parsing $(length(DatasetList.Item)) datasets from EXFOR...")
print('\n')
mutex = Threads.SpinLock()
#######################################################################################################
#######################################################################################################
Threads.@threads for index in eachindex(DatasetList.Item)
    csvURL = "x4get?DatasetID=$(DatasetList.Item[index])&op=csv&plus=2"
    Downloads.download(string("https://nds.iaea.org/exfor/", csvURL), 
        "tempData/$(DatasetList.Item[index]).csv"
    )
    csvData = CSV.read("tempData/$(DatasetList.Item[index]).csv", DataFrame; normalizenames=true)

    #Filtering Data sets by required TAGS
    isempty(csvData) && continue
    isempty(skipmissing(csvData[!, 39])) && continue
    !isempty(findall(x -> x == "ARB", first(skipmissing(csvData[!, 4])))) && continue
    !isempty(findall(x -> x == '?', first(skipmissing(csvData[!, 4])))) && continue
    REACTION = first(skipmissing(csvData[!, 39]))
    skipIteration = false
    if !isempty(yesTagsOR)
        skipIteration = true
        for tagIndex in eachindex(yesTagsOR)
            if !isempty(findall(yesTagsOR[tagIndex], REACTION))
                skipIteration = false
                break
            end
        end
        skipIteration && continue
    end
    for tagIndex in eachindex(yesTagsAND)
        if isempty(findall(yesTagsAND[tagIndex], REACTION))
            skipIteration = true
            break
        end
    end
    skipIteration && continue
    for tagIndex in eachindex(noTags)
        if !isempty(findall(noTags[tagIndex], REACTION))
            skipIteration = true
            break
        end
    end
    skipIteration && continue
    (reaction[begin] != '0') && ((first(skipmissing(csvData[!, 11])) > E_max) || (first(skipmissing(csvData[!, 11])) < E_min)) && continue
    xdataID != "E" && xdataID != "TKE" && isempty(skipmissing(csvData[!, 26])) && continue
    (xdataID == "A" || xdataID == "Ap" || xdataID == "ATKE") && (first(skipmissing(csvData[!, 26])) > 1e4 || minimum(skipmissing(csvData[!, 26])) <= 10) && continue
    (xdataID == "Z" || xdataID == "ZAp") && minimum(skipmissing(csvData[!, 26])) < 1e4 && continue
    (xdataID == "E" || xdataID == "TKE") && !isempty(skipmissing(csvData[!, 26])) && continue

    
@lock mutex begin

    #Saving data set to file
    year = first(csvData[!, 2]); author = replace(first(csvData[!, 3]), "+" => "")
    fileID = string(DatasetList.Item[index], '_', author, '_', year)    
    legendLabel = replace(fileID, '_' => ' ')
    x4URL = "x4get?sub=$(DatasetList.Item[index])"
    Downloads.download(string("https://nds.iaea.org/exfor/", x4URL), 
        "outputData/$(targetNucleus)/$(outputPATH)/X4/$(fileID).txt"
    )

    println(lpad("", 75, "#"))
    println(lpad(rpad("  wrote $(legendLabel) to file!  ", 70, "#"), 75, "#"))
    println(lpad(rpad("  REACTION: $(REACTION)  ", 70, "#"), 75, "#"))
    println(lpad("", 75, "#"))

    if xdataID == "A" || xdataID == "Ap"
        xData = csvData[!, 26]
    elseif xdataID == "Z"
        xData = div.(csvData[!, 26], 1e3)
    elseif xdataID == "TKE" || xdataID == "E"
        xData = round.(csvData[!, 14] .*1e-6, digits=truncatingDigits)
    elseif xdataID == "ATKE"
        xData = csvData[!, 26]
    elseif xdataID == "ZAp"
        xData = mod.(csvData[!, 26], 1e3)
    end
    data = DataFrame(x=xData, y=csvData[!, 5], erroy=csvData[!, 6])
    if !isempty(skipmissing(data.erroy))
        data.erroy[ismissing.(data.erroy)] .= 0.0
    else
        data.erroy .= 0.0
    end
    if ydataID == "yield" 
        while(maximum(data.y) <= 2.5)
            data.y .*= 10; data.erroy .*= 10
        end
        while(maximum(data.y) > 25)
            data.y ./= 10; data.erroy ./= 10
        end
    elseif ydataID == "KE" || ydataID == "KEp" || ydataID == "TKE" || ydataID == "TKEp"|| ydataID == "epsE"
        data.y .*= 1e-6; data.erroy .*= 1e-6
    end
    if xdataID == "A" || xdataID == "Z" || xdataID == "Ap"
        if !isempty(data.y[ismissing.(data.y)])
            deleteIndices = findall(x -> ismissing(x), data.y)
            deleteat!(data, deleteIndices)
        end
        xAUX = unique(round.(data.x))
        for value in xAUX
            data.y[round.(data.x) .== value] .= sum(data.y[round.(data.x) .== value])/length(data.y[round.(data.x) .== value])
            data.erroy[round.(data.x) .== value] .= sqrt(sum(data.erroy[round.(data.x) .== value].^2))/length(data.erroy[round.(data.x) .== value])
        end
        data.x .= round.(data.x)
        unique!(data, 1)
        data.y = round.(data.y, digits=truncatingDigits)
        data.erroy = round.(data.erroy, digits=truncatingDigits)
    end
    if xdataID != "ATKE" && xdataID != "ZAp"
        if !isempty(data.y[ismissing.(data.y)])
            deleteIndices = findall(x -> ismissing(x), data.y)
            deleteat!(data, deleteIndices)
        end
        if !isempty(data.erroy[.!iszero.(data.erroy)])
            CSV.write(
                "outputData/$(targetNucleus)/$(outputPATH)/DAT/$(fileID).dat", 
                DataFrame(x = data.x, y = data.y, yerror = data.erroy),
                writeheader=true, newline="\r\n", delim=' ', header=["$(xdataID)", "$(ydataID)", "err$(ydataID)"]
            )
            scatter!(dataPlot, data.x, data.y, yerror=data.erroy, label=legendLabel, markershape=:xcross)
        else
            CSV.write(
                "outputData/$(targetNucleus)/$(outputPATH)/DAT/$(fileID).dat",
                DataFrame(x = data.x, y = data.y),
                writeheader=true, newline="\r\n", delim=' ', header=["$(xdataID)", "$(ydataID)"]
            )
            scatter!(dataPlot, data.x, data.y, label=legendLabel, markershape=:xcross)
        end
    elseif xdataID == "ATKE"
        data.TKE = round.(csvData[!, 14] .*1e-6, digits=truncatingDigits)
        if !isempty(data.y[ismissing.(data.y)])
            deleteIndices = findall(x -> ismissing(x), data.y)
            deleteat!(data, deleteIndices)
        end
        if !isempty(data.erroy[.!iszero.(data.erroy)])
            CSV.write(
                "outputData/$(targetNucleus)/$(outputPATH)/DAT/$(fileID).dat", 
                DataFrame(A = data.x, TKE = data.TKE, ydata = data.y, yerro = data.erroy),
                writeheader=true, newline="\r\n", delim=' ', header=["A", "TKE", "$(ydataID)", "err$(ydataID)"]
            )
        else
            CSV.write(
                "outputData/$(targetNucleus)/$(outputPATH)/DAT/$(fileID).dat", 
                DataFrame(A = data.x, TKE = data.TKE, ydata = data.y),
                writeheader=true, newline="\r\n", delim=' ', header=["A", "TKE", "$(ydataID)"]
            )
        end
        scatter!(dataPlot, data.x, data.TKE, data.y, label=legendLabel, markershape=:xcross)
    elseif xdataID == "ZAp"
        data.Z = div.(csvData[!, 26], 1e3)
        if !isempty(data.y[ismissing.(data.y)])
            deleteIndices = findall(x -> ismissing(x), data.y)
            deleteat!(data, deleteIndices)
        end
        data.y = round.(data.y, digits=truncatingDigits)
        if !isempty(data.erroy[.!iszero.(data.erroy)])
            data.erroy = round.(data.erroy, digits=truncatingDigits)
            CSV.write(
                "outputData/$(targetNucleus)/$(outputPATH)/DAT/$(fileID).dat", 
                DataFrame(Z = data.Z, Ap = data.x, ydata = data.y, yerro = data.erroy),
                writeheader=true, newline="\r\n", delim=' ', header=["Z", "Ap", "$(ydataID)", "err$(ydataID)"]
            )
        else
            CSV.write(
                "outputData/$(targetNucleus)/$(outputPATH)/DAT/$(fileID).dat",
                DataFrame(Z = data.Z, Ap = data.x, ydata = data.y, yerro = data.erroy),
                writeheader=true, newline="\r\n", delim=' ', header=["Z", "Ap", "$(ydataID)"]
            )
        end
        scatter!(dataPlot, data.Z, data.x, data.y, label=legendLabel, markershape=:xcross)
    end

end
end
rm("tempData/", recursive=true)
if isempty(readdir("outputData/$(targetNucleus)/$(outputPATH)/DAT/"))
    print('\n')
    println(lpad("", 70, "#"))
    println(lpad(rpad("  No relevant data found in EXFOR!  ", 55, "#"), 70, "#"))
    println(lpad("", 70, "#"))
    print('\n')
    rm("outputData/$(targetNucleus)/$(outputPATH)/", recursive=true)
else
    savefig(dataPlot, "outputData/$(targetNucleus)/$(outputPATH)/$(outputPATH).png")
    display(dataPlot)
end
println("*ending program execution at $(Dates.format(now(), "HH:MM:SS"))")
println("*program execution successful after $(round(Dates.value(now()-start_time)/60000, digits=2)) minutes!")
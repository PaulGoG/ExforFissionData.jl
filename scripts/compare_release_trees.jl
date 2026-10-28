# Invariance check between the retrieval trees of two releases.
#
#     julia scripts/compare_release_trees.jl <old-data-root> <new-data-root>
#     julia scripts/compare_release_trees.jl --status <old-data-root> <new-data-root>
#
# Each root holds <system>/<observable>/. By default, for every observable of the old tree:
#
#   - every file but the run record (the tables, relative/ and subentries/) must be present in
#     the new tree and byte-identical; files the new tree adds to such a directory are listed; a
#     table (.dat) that differs is summarised by rows: row counts, abscissa values lost and
#     gained, and the largest change of the ordinate at a shared abscissa value;
#   - the run records are compared key by key. The [run] table, the timestamps
#     (`retrieved_utc`, `retrieved_earliest_utc`, `retrieved_latest_utc`) and keys the old
#     record does not hold are expected to differ and are only counted; a key removed, or a
#     value changed, is printed.
#
# Observables only the new tree holds are listed. Exits 1 on any difference that is not of the
# expected kinds.
#
# --status compares only the accepted sets: per observable held by both trees, the old and new
# accepted counts and the datasets that changed status, a lost one with its rejection reason in
# the new record. It reads nothing but the identifiers and reasons, so records of an older schema
# compare too; it always exits 0. Read-only in both modes.

include(joinpath(@__DIR__, "..", "activate.jl"))

using SHA: sha256
using TOML: TOML

const TIMESTAMP_KEYS = ("retrieved_utc", "retrieved_earliest_utc", "retrieved_latest_utc")

const USAGE = "usage: compare_release_trees.jl [--status] <old-root> <new-root>"

function observables(root)
    found = String[]
    for system in readdir(root; join = true)
        isdir(system) || continue
        for observable in readdir(system; join = true)
            isfile(joinpath(observable, "retrieval.toml")) &&
                push!(found, joinpath(basename(system), basename(observable)))
        end
    end
    return sort!(found)
end

function data_files(directory)
    files = String[]
    for (path, _, names) in walkdir(directory), name in names
        name == "retrieval.toml" && continue
        push!(files, relpath(joinpath(path, name), directory))
    end
    return sort!(files)
end

digest(path) = bytes2hex(open(sha256, path))

# Differences between two values of a record at `path`: removed keys and changed values are
# pushed to `differences`, keys only the new record holds to `added`.
function compare!(differences, added, old, new, path)
    if old isa AbstractDict && new isa AbstractDict
        for key in sort!(collect(keys(old)))
            key in TIMESTAMP_KEYS && continue
            here = isempty(path) ? key : string(path, ".", key)
            if haskey(new, key)
                compare!(differences, added, old[key], new[key], here)
            else
                push!(differences, "$(here): removed (was $(repr(old[key])))")
            end
        end
        for key in setdiff(keys(new), keys(old))
            push!(
                added,
                isempty(path) ? key :
                string(replace(path, r"\[[^\]]*\]" => "[]"), ".", key),
            )
        end
    elseif old != new
        push!(differences, "$(path): $(repr(old)) -> $(repr(new))")
    end
    return nothing
end

# The entries of an array of tables keyed by dataset identifier.
by_identifier(entries) = Dict(String(entry["identifier"]) => entry for entry in entries)

function compare_records(old, new)
    differences = String[]
    added = Set{String}()
    for key in sort!(collect(keys(old)))
        key == "run" && continue
        if !haskey(new, key)
            push!(differences, "$(key): removed")
        elseif key in ("accepted", "rejected", "slices")
            a, b = by_identifier(old[key]), by_identifier(new[key])
            for identifier in sort!(collect(keys(a)))
                if haskey(b, identifier)
                    compare!(
                        differences,
                        added,
                        a[identifier],
                        b[identifier],
                        "$(key)[$(identifier)]",
                    )
                else
                    push!(differences, "$(key)[$(identifier)]: no longer $(key)")
                end
            end
            for identifier in sort!(collect(setdiff(keys(b), keys(a))))
                push!(differences, "$(key)[$(identifier)]: newly $(key)")
            end
        else
            compare!(differences, added, old[key], new[key], key)
        end
    end
    for key in setdiff(keys(new), keys(old))
        push!(added, key)
    end
    return differences, added
end

# Ordinate by abscissa key of a written table: the header line is skipped, the first
# `quantities` columns are the abscissa and the next one the ordinate. `nothing` for a file
# that does not read as such a table.
function ordinate_index(path, quantities)
    index = Dict{String, Float64}()
    rows = 0
    for line in Iterators.drop(eachline(path), 1)
        fields = split(line)
        isempty(fields) && continue
        length(fields) > quantities || return nothing
        value = tryparse(Float64, fields[quantities + 1])
        value === nothing && return nothing
        index[join(fields[1:quantities], ' ')] = value
        rows += 1
    end
    return index, rows
end

# Row-level summary of two versions of a table, or `nothing` where either is not a table.
function row_summary(old_path, new_path, quantities)
    old, new = ordinate_index(old_path, quantities), ordinate_index(new_path, quantities)
    (old === nothing || new === nothing) && return nothing
    (a, rows_a), (b, rows_b) = old, new
    shared = intersect(keys(a), keys(b))
    change = isempty(shared) ? 0.0 : maximum(abs(a[k] - b[k]) for k in shared)
    return string(
        "rows ",
        rows_a,
        " -> ",
        rows_b,
        "; lost ",
        length(setdiff(keys(a), keys(b))),
        ", gained ",
        length(setdiff(keys(b), keys(a))),
        "; largest change at a shared value ",
        round(change; sigdigits = 3),
    )
end

function compare_trees(old_root, new_root)
    old, new = observables(old_root), observables(new_root)
    files = identical = 0
    failures = 0
    added_keys = Set{String}()
    for observable in old
        a, b = joinpath(old_root, observable), joinpath(new_root, observable)
        if !isdir(b)
            println(observable, ": missing from the new tree")
            failures += 1
            continue
        end
        old_record = TOML.parsefile(joinpath(a, "retrieval.toml"))
        new_record =
            isfile(joinpath(b, "retrieval.toml")) ?
            TOML.parsefile(joinpath(b, "retrieval.toml")) : Dict{String, Any}()
        quantities = length(get(get(old_record, "query", Dict()), "abscissa", Any[]))
        for file in data_files(a)
            files += 1
            if !isfile(joinpath(b, file))
                println(observable, "/", file, ": missing from the new tree")
                failures += 1
            elseif digest(joinpath(a, file)) != digest(joinpath(b, file))
                summary =
                    endswith(file, ".dat") && quantities > 0 ?
                    row_summary(joinpath(a, file), joinpath(b, file), quantities) : nothing
                println(
                    observable,
                    "/",
                    file,
                    ": differs",
                    summary === nothing ? "" : string("; ", summary),
                )
                failures += 1
            else
                identical += 1
            end
        end
        for file in setdiff(data_files(b), data_files(a))
            println(observable, "/", file, ": only in the new tree")
            failures += 1
        end
        differences, added = compare_records(old_record, new_record)
        union!(added_keys, added)
        for difference in differences
            println(observable, "/retrieval.toml: ", difference)
            failures += 1
        end
    end
    println()
    println("observables of the old tree: ", length(old))
    println("data files compared: ", files, ", byte-identical: ", identical)
    println(
        "new record keys: ",
        isempty(added_keys) ? "none" : join(sort!(collect(added_keys)), ", "),
    )
    println("observables only in the new tree: ", join(setdiff(new, old), ", "))
    println("differences beyond [run], timestamps and new keys: ", failures)
    return failures == 0 ? 0 : 1
end

# Accepted identifiers and rejection reasons of a record, whatever else its schema holds.
accepted_set(record) = Set(
    string(entry["identifier"]) for
    entry in get(record, "accepted", Any[]) if haskey(entry, "identifier")
)
rejection_reasons(record) = Dict(
    string(entry["identifier"]) => string(get(entry, "reason", "(no reason recorded)"))
    for entry in get(record, "rejected", Any[]) if haskey(entry, "identifier")
)

function compare_status(old_root, new_root)
    load(root) = Dict(
        key => TOML.parsefile(joinpath(root, key, "retrieval.toml")) for
        key in observables(root)
    )
    old, new = load(old_root), load(new_root)
    println(
        rpad("observable", 40),
        rpad("old", 6),
        rpad("new", 6),
        rpad("lost", 6),
        "gained",
    )
    for key in sort!(collect(intersect(keys(old), keys(new))))
        a, b = accepted_set(old[key]), accepted_set(new[key])
        lost = sort!(collect(setdiff(a, b)))
        gained = sort!(collect(setdiff(b, a)))
        println(
            rpad(key, 40),
            rpad(length(a), 6),
            rpad(length(b), 6),
            rpad(length(lost), 6),
            length(gained),
        )
        reasons = rejection_reasons(new[key])
        for identifier in lost
            println(
                "    - ",
                identifier,
                ": ",
                get(reasons, identifier, "(not in the new record)"),
            )
        end
        for identifier in gained
            println("    + ", identifier)
        end
    end
    for key in sort!(collect(setdiff(keys(old), keys(new))))
        println(rpad(key, 40), "only in the old tree")
    end
    for key in sort!(collect(setdiff(keys(new), keys(old))))
        println(rpad(key, 40), "only in the new tree")
    end
    return 0
end

function main(arguments)
    status = !isempty(arguments) && first(arguments) == "--status"
    roots = status ? arguments[2:end] : arguments
    length(roots) == 2 || throw(ArgumentError(USAGE))
    old_root, new_root = abspath.(roots)
    for root in (old_root, new_root)
        isdir(root) || throw(ArgumentError("no data tree at $(root)"))
    end
    return status ? compare_status(old_root, new_root) : compare_trees(old_root, new_root)
end

exit(main(ARGS))

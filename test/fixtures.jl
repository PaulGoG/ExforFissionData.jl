# Synthetic EXFOR responses with the exact column layout of the `op=csv&plus=2` rendering.
#
# Fixtures are built rather than committed: the layout is the thing under test, so writing it out
# here keeps the expectation visible, and no archive data needs to enter the repository.

"""
    exfor_row(; kwargs...) -> Vector{String}

One row of the csv rendering, with every field empty unless named.

Recognised keywords mirror the column names: `dataset_id`, `year`, `author`, `value_kind`, `y`,
`dy`, `incident_ev`, `secondary_ev`, `product_za`, `isomer` and `reaction_code`.
"""
function exfor_row(;
    dataset_id = "10000002",
    year = 1975,
    author = "A.Author+",
    value_kind = "Data(PART/FIS)",
    y = 1.0,
    dy = missing,
    incident_ev = missing,
    secondary_ev = missing,
    product_za = missing,
    isomer = missing,
    reaction_code = "92-U-233(N,F)MASS,CHN,FY",
)
    fields = fill("", length(EXFOR_HEADER))
    show_or_blank(value) = value === missing ? "" : string(value)
    fields[1] = string(dataset_id)
    fields[2] = string(year)
    fields[3] = string(author)
    fields[4] = string(value_kind)
    fields[5] = show_or_blank(y)
    fields[6] = show_or_blank(dy)
    fields[11] = show_or_blank(incident_ev)
    fields[14] = show_or_blank(secondary_ev)
    fields[26] = show_or_blank(product_za)
    fields[27] = show_or_blank(isomer)
    fields[39] = string('"', reaction_code, '"')
    return fields
end

"""
    exfor_csv(rows; header = EXFOR_HEADER) -> String

Assemble rows into a csv body. `header` may be altered to exercise the layout check.
"""
function exfor_csv(rows::AbstractVector; header = EXFOR_HEADER)
    buffer = IOBuffer()
    println(buffer, join(header, ','))
    for row in rows
        println(buffer, join(row, ','))
    end
    return String(take!(buffer))
end

"""
    test_query(; kwargs...) -> Query

A query with thermal defaults, for selection and reduction tests.

The reaction code and the EXFOR quantity code are derived, as `load_configuration` derives them,
so a fixture cannot pair an ordinate with a quantity the loader would refuse.
"""
function test_query(;
    target_Z = 92,
    target_A = 233,
    channel = "nth",
    abscissa = ["mass"],
    ordinate = "yield",
    energy_min = 0.0,
    energy_max = 1.0e-7,
)
    return ExforFissionData.Query(
        target_Z,
        target_A,
        channel,
        ExforFissionData.CHANNEL_REACTION[channel],
        ExforFissionData.ORDINATE_QUANTITY[ordinate],
        abscissa,
        ordinate,
        energy_min,
        energy_max,
        channel == "sf",
    )
end

"""
    exfor_subentry(; kwargs...) -> String

The text of an entry excerpt as `x4get?sub=` returns it, in the fixed-column layout of the EXFOR
Formats Manual: subentry 001 of `entry`, then subentry `subentry`, each with its BIB section and
its COMMON section or NOCOMMON, the second with its DATA section.

# Keywords
- `entry`, `subentry`: the entry number (5 characters) and the subentry identifier (8).
- `bib`: the BIB records of `subentry`.
- `entry_common`, `common`: the COMMON sections of subentry 001 and of `subentry`, as named
  tuples of `headings`, `units` and `values`, optionally `pointers`; NOCOMMON when `headings`
  is empty.
- `headings`, `units`, `pointers`: the columns of the DATA section.
- `rows`: the lines of the DATA section, one value per column, `missing` for a blank field.

Counters are right-adjusted to end at columns 22 and 33; values are written with `string`, so
`63.51` and `100.0` appear as such.
"""
function exfor_subentry(;
    entry = "10000",
    subentry = "10000002",
    bib = ["REACTION   (92-U-235(N,F)MASS,PRE,FY)"],
    entry_common = (headings = String[], units = String[], values = Float64[]),
    common = (headings = String[], units = String[], values = Float64[]),
    headings = ["MASS", "DATA"],
    units = ["NO-DIM", "PC/FIS"],
    pointers = fill(' ', length(headings)),
    rows = [[100.0, 6.0]],
)
    system(keyword, counters...) =
        rpad(keyword, 11) * join(lpad(string(counter), 11) for counter in counters)
    # Six fields per record; a row with more continues onto further records.
    records(fields) = [join(fields[i:min(i + 5, end)]) for i in 1:6:length(fields)]
    function section(kind, column_headings, column_units, column_pointers, value_rows)
        body = String[]
        append!(
            body,
            records([rpad(h, 10) * p for (h, p) in zip(column_headings, column_pointers)]),
        )
        append!(body, records([rpad(unit, 11) for unit in column_units]))
        for row in value_rows
            fields = [value === missing ? " "^11 : lpad(string(value), 11) for value in row]
            append!(body, records(fields))
        end
        n2 = kind == "COMMON" ? length(body) : length(value_rows)
        return [
            system(kind, length(column_headings), n2)
            body
            system("END" * kind, length(body))
        ]
    end
    function common_section(section_content)
        isempty(section_content.headings) && return [system("NOCOMMON", 0, 0)]
        column_pointers =
            get(section_content, :pointers, fill(' ', length(section_content.headings)))
        return section(
            "COMMON",
            section_content.headings,
            section_content.units,
            column_pointers,
            [section_content.values],
        )
    end
    function bib_section(bib_records)
        keywords = count(record -> !isempty(strip(first(record, 10))), bib_records)
        return [
            system("BIB", keywords, length(bib_records))
            bib_records
            system("ENDBIB", length(bib_records))
        ]
    end

    entry_body = [bib_section(["TITLE      synthetic"]); common_section(entry_common)]
    subentry_body = [
        bib_section(bib)
        common_section(common)
        section("DATA", headings, units, pointers, rows)
    ]
    lines = [
        system("ENTRY", entry)
        system("SUBENT", entry * "001")
        entry_body
        system("ENDSUBENT", length(entry_body))
        system("SUBENT", subentry)
        subentry_body
        system("ENDSUBENT", length(subentry_body))
        system("ENDENTRY", 2)
    ]
    return join(lines, '\n') * '\n'
end

"""
    exfor_subentry_for(rows; secondary = "E", unit = "PRT/FIS", extra = nothing, kwargs...)
        -> String

The subentry text that the csv rows of `exfor_row` correspond to, built through
`exfor_subentry`, so that a test states its data once.

The DATA columns are, in this order where present: `ELEM` and `MASS` when any `ProdZA` is
charge-coded (at least 10 000), else `MASS` alone when any `ProdZA` is given; `ISOMER` when any
`ProdM` is given; the heading `secondary`, in `EV`, when any `x3` is given; `EN` in `EV` when the
incident energy takes more than one value, which is a COMMON constant instead when it takes
one; `DATA` in `unit` from `y`; `DATA-ERR` in `unit` when any `dy` is given. A blank csv field
is a blank field here.

# Keywords
- `secondary`: the heading of the secondary energy, `"E"`, `"TKE"`, `"E-CM"`.
- `unit`: the unit of `DATA` and `DATA-ERR`.
- `extra`: columns to append, as `(headings = [...], units = [...], values = [...])` with one
  vector of values per row.

`subentry` defaults to the first eight characters of the identifier of the first row; every
other keyword passes through to `exfor_subentry` and overrides what is derived here.
"""
function exfor_subentry_for(
    rows::AbstractVector;
    secondary = "E",
    unit = "PRT/FIS",
    extra = nothing,
    kwargs...,
)
    field(row, index) = isempty(row[index]) ? missing : parse(Float64, row[index])
    csv_column(index) = Union{Missing, Float64}[field(row, index) for row in rows]
    product = csv_column(26)
    isomer = csv_column(27)
    y = csv_column(5)
    dy = csv_column(6)
    secondary_energy = csv_column(14)
    incident_energy = csv_column(11)

    headings = String[]
    units = String[]
    columns = Vector{Union{Missing, Float64}}[]
    function add!(heading, heading_unit, values)
        push!(headings, heading)
        push!(units, heading_unit)
        push!(columns, values)
    end

    products = collect(skipmissing(product))
    if any(≥(10_000), products)
        charge = [ismissing(p) ? missing : Float64(round(Int, p) ÷ 1000) for p in product]
        mass = [ismissing(p) ? missing : Float64(round(Int, p) % 1000) for p in product]
        add!("ELEM", "NO-DIM", charge)
        add!("MASS", "NO-DIM", mass)
    elseif !isempty(products)
        add!("MASS", "NO-DIM", product)
    end
    any(!ismissing, isomer) && add!("ISOMER", "NO-DIM", isomer)
    any(!ismissing, secondary_energy) && add!(secondary, "EV", secondary_energy)
    incident = unique(skipmissing(incident_energy))
    common = (headings = String[], units = String[], values = Float64[])
    if length(incident) > 1
        add!("EN", "EV", incident_energy)
    elseif length(incident) == 1
        common = (headings = ["EN"], units = ["EV"], values = [only(incident)])
    end
    add!("DATA", unit, y)
    any(!ismissing, dy) && add!("DATA-ERR", unit, dy)
    if extra !== nothing
        for (j, heading) in enumerate(extra.headings)
            add!(heading, extra.units[j], [row_values[j] for row_values in extra.values])
        end
    end

    data_rows = [[values[i] for values in columns] for i in eachindex(rows)]
    return exfor_subentry(;
        subentry = first(first(rows)[1], 8),
        headings,
        units,
        rows = data_rows,
        common,
        kwargs...,
    )
end

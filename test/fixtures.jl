# Synthetic EXFOR responses with the exact column layout of the `op=csv&plus=2` rendering.
#
# Fixtures are built rather than committed: the layout is the thing under test, so writing it out
# here keeps the expectation visible, and no archive data needs to enter the repository.

using ExforFissionData: EXFOR_HEADER

"""
    exfor_row(; kwargs...) -> Vector{String}

One row of the csv rendering, with every field empty unless named.

Recognised keywords mirror the column names: `dataset_id`, `year`, `author`, `value_kind`, `y`,
`dy`, `incident_ev`, `secondary_ev`, `product`, `product_za`, `isomer`, `reaction_code`, and
`independent_variables` for the `indVars` column.
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
    product = missing,
    product_za = missing,
    isomer = missing,
    independent_variables = missing,
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
    fields[25] = show_or_blank(product)
    fields[26] = show_or_blank(product_za)
    fields[27] = show_or_blank(isomer)
    fields[38] = show_or_blank(independent_variables)
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

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

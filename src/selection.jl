# Parsing one retrieved dataset and deciding whether it answers the query.
#
# Every rejection carries a reason. A dataset silently absent from the output is indistinguishable
# from one the archive does not hold, which makes a retrieval impossible to audit; the reasons are
# written to the run metadata alongside the accepted data.

"""
    Dataset

One EXFOR dataset, parsed and accepted for a query.

# Fields
- `identifier::String`: the EXFOR dataset identifier.
- `year::Int`: publication year of the entry.
- `author::String`: first author, as EXFOR records them, with the `+` for "et al." removed.
- `reaction_code::String`: the full EXFOR reaction code the selection matched.
- `unit::String`: the unit token of the `y:Value` column, e.g. `"PART/FIS"`.
- `table::DataFrame`: the rows retained after unit, tag and incident-energy selection.
"""
struct Dataset
    identifier::String
    year::Int
    author::String
    reaction_code::String
    unit::String
    table::DataFrame
end

"""
    Rejection

A dataset excluded from a query, with the reason.

# Fields
- `identifier::String`: the EXFOR dataset identifier.
- `reaction_code::String`: the reaction code, where one could be read; empty otherwise.
- `reason::String`: why the dataset was excluded.
"""
struct Rejection
    identifier::String
    reaction_code::String
    reason::String
end

# The first non-missing entry of a column, or `nothing` when every entry is missing.
function _first_present(column)
    for value in column
        ismissing(value) || return value
    end
    return nothing
end

"""
    parse_dataset(identifier, body) -> DataFrame

Parse the csv rendering of one dataset, validating the column layout.

Throws an `ArgumentError` naming the dataset when the header does not match
[`EXFOR_HEADER`](@ref), or when the archive returned no data at all — which is a different
failure and must not be reported as a changed layout.
"""
function parse_dataset(identifier::AbstractString, body::AbstractString)
    # Distinguished from a layout change deliberately. An empty body or an application-level
    # error message says nothing about the column contract, and reporting it as a schema
    # mismatch sends the reader to `src/schema.jl` to look for a problem that is not there.
    is_usable_response(body) || throw(
        ArgumentError(
            "dataset $(identifier): the archive returned no usable data for this identifier, \
             so nothing could be parsed. This is a response failure rather than a change in \
             the csv layout, and it is usually transient — re-running retries it.",
        ),
    )
    table = CSV.read(
        IOBuffer(body),
        DataFrame;
        header = 1,
        normalizenames = false,
        silencewarnings = true,
        stringtype = String,
    )
    validate_header(names(table), "dataset $(identifier)")
    return table
end

"""
    select_dataset(identifier, body, query) -> Union{Dataset,Rejection}

Decide whether one retrieved dataset answers `query`, and reduce it to the rows that do.

Selection proceeds in the order below, and the first failure is reported:

1. the dataset is non-empty and carries a reaction code;
2. the `y:Value` column marks measurements rather than limits, and is not in arbitrary units;
3. the reaction code satisfies the composed tag rule of the abscissa and ordinate;
4. for induced fission, at least one row lies within the configured incident-energy window —
   and only those rows are retained;
5. the product identification is consistent with the abscissa: present and mass-coded for the
   fragment-mass abscissae, present and charge-coded for the charge abscissae, and absent for
   the energy abscissae.

Step 4 is a row filter rather than a whole-dataset test. An EXFOR dataset frequently reports the
same product at several incident energies; admitting all of them and combining them later would
average an excitation function into a single number.
"""
function select_dataset(identifier::AbstractString, body::AbstractString, query)
    table = parse_dataset(identifier, body)
    isempty(table) && return Rejection(identifier, "", "dataset is empty")

    code_entry = _first_present(table[!, COL_REACTION_CODE])
    code_entry === nothing &&
        return Rejection(identifier, "", "dataset carries no reaction code")
    code = String(code_entry)

    kind_entry = _first_present(table[!, COL_VALUE_KIND])
    kind_entry === nothing &&
        return Rejection(identifier, code, "dataset carries no value-kind column")
    kind = String(kind_entry)

    if occursin('?', kind)
        return Rejection(identifier, code, "value kind \"$(kind)\" is marked uncertain")
    end
    if !is_measurement(kind)
        return Rejection(
            identifier,
            code,
            "value kind \"$(kind)\" is a limit, not a measurement",
        )
    end
    if !has_absolute_scale(kind)
        return Rejection(identifier, code, "value kind \"$(kind)\" has no absolute scale")
    end
    unit = last(parse_value_kind(kind))

    rule = tag_rule(query.abscissa, query.ordinate)
    reason = rejection_reason(rule, code)
    reason === nothing || return Rejection(identifier, code, reason)

    # Incident energy. Spontaneous fission carries no incident particle, so the window does not
    # apply; for induced fission the window selects rows.
    if !query.spontaneous
        energies = table[!, COL_INCIDENT_ENERGY]
        keep = map(energies) do value
            ismissing(value) && return false
            energy = Float64(value) * EV_TO_MEV
            query.energy_min ≤ energy ≤ query.energy_max
        end
        if !any(keep)
            present = collect(skipmissing(energies))
            range = if isempty(present)
                "no incident energy recorded"
            else
                string(
                    "incident energies ",
                    minimum(present) * EV_TO_MEV,
                    " to ",
                    maximum(present) * EV_TO_MEV,
                    " MeV",
                )
            end
            return Rejection(
                identifier,
                code,
                "$(range), outside the window $(query.energy_min) to $(query.energy_max) MeV",
            )
        end
        table = table[keep, :]
    end

    product = collect(skipmissing(table[!, COL_PRODUCT_ZA]))
    if query.abscissa in ("E", "TKE")
        isempty(product) || return Rejection(
            identifier,
            code,
            "abscissa \"$(query.abscissa)\" expects no reaction product, but the dataset \
             identifies one",
        )
    else
        isempty(product) && return Rejection(
            identifier,
            code,
            "abscissa \"$(query.abscissa)\" needs a reaction product, which the dataset does \
             not identify",
        )
        if query.abscissa in ("A", "Ap", "ATKE")
            # A bare mass number, so it must look like one. `ProdZA` is 1000·Z + A whenever the
            # product is charge-resolved, which for Z ≥ 10 exceeds 10⁴ — but for a light charge-
            # resolved product it does not: an α from ternary fission is 2004, and taken as a
            # mass number that is a fragment four times too heavy to exist. Bounding the value
            # from above is what separates the two codings for light products, and no bare
            # fission-fragment mass approaches the mass of the fissioning nucleus.
            maximum(product) > MAXIMUM_FRAGMENT_MASS && return Rejection(
                identifier,
                code,
                "abscissa \"$(query.abscissa)\" expects bare mass numbers, but the products \
                 reach $(maximum(product)), which is charge-coded rather than a mass",
            )
            minimum(product) ≤ MINIMUM_FRAGMENT_MASS && return Rejection(
                identifier,
                code,
                "product mass numbers reach $(minimum(product)), too light to be a fission \
                 fragment",
            )
        elseif query.abscissa in ("Z", "ZAp")
            minimum(product) < 1e4 && return Rejection(
                identifier,
                code,
                "abscissa \"$(query.abscissa)\" expects charge-coded products, but the \
                 products are bare mass numbers",
            )
        end
    end

    year_entry = _first_present(table[!, COL_YEAR])
    author_entry = _first_present(table[!, COL_AUTHOR])
    year = year_entry === nothing ? 0 : round(Int, year_entry)
    author = author_entry === nothing ? "unknown" : replace(String(author_entry), "+" => "")

    return Dataset(String(identifier), year, author, code, unit, table)
end

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

Throws a [`LayoutError`](@ref) naming the dataset when the header does not match
[`EXFOR_HEADER`](@ref), and an `ArgumentError` when the archive returned no data at all — which
is a different failure and must not be reported as a changed layout.
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
    declared_variables(table) -> Vector{Int}

The independent-variable families the rendering declares for a dataset, read from its `indVars`
column as the digits of [`VARIABLE_FAMILIES`](@ref); empty when the column is blank.
"""
function declared_variables(table::DataFrame)
    families = Set{Int}()
    for value in skipmissing(table[!, COL_INDEPENDENT_VARIABLES])
        text = value isa Real ? string(round(Int, value)) : string(value)
        for character in text
            family = isdigit(character) ? parse(Int, character) : 0
            haskey(VARIABLE_FAMILIES, family) && push!(families, family)
        end
    end
    return sort!(collect(families))
end

"""
    varying_variables(table, abscissa) -> Vector{String}

The declared independent variables that `abscissa` does not account for and that take more than
one value over `table`, each as its heading and the number of values.

Projecting a dataset onto an abscissa asserts that nothing else varies. A variable held at one
value is a condition of the measurement and leaves the projection meaningful; one that varies
makes every abscissa value a family of rows, and no combination of them is the observable asked
for — a mean over kinetic-energy gates is not a mass yield. The incident energy is left to the
window and to the check that follows it.
"""
function varying_variables(table::DataFrame, abscissa::AbstractVector{<:AbstractString})
    accounted = Set(ABSCISSA_FAMILY[quantity] for quantity in abscissa)
    push!(accounted, INCIDENT_ENERGY_FAMILY)
    varying = String[]
    for family in declared_variables(table)
        family in accounted && continue
        heading, column = VARIABLE_FAMILIES[family]
        count = length(unique(skipmissing(table[!, column])))
        count > 1 && push!(varying, "$(heading) ($(count) values)")
    end
    return varying
end

"""
    select_dataset(identifier, body, query) -> Union{Dataset,Rejection}

Decide whether one retrieved dataset answers `query`, and reduce it to the rows that do.

Selection proceeds in the order below, and the first failure is reported:

1. the dataset is non-empty and carries a reaction code;
2. the `y:Value` column marks measurements rather than limits, and is not in arbitrary units;
3. the reaction code satisfies the composed tag rule of the abscissa and ordinate;
4. the reaction code carries no spectrum qualifier that contradicts the entrance channel; see
   [`CHANNEL_FORBIDDEN_QUALIFIERS`](@ref);
5. for induced fission, at least one row lies within the configured incident-energy window —
   and only those rows are retained — and the retained rows share one incident energy;
6. no independent variable the rendering declares, other than the abscissa's own, varies over
   the retained rows; see [`varying_variables`](@ref);
7. the product identification is consistent with the abscissa: present and mass-coded for the
   fragment-mass abscissae, present and charge-coded for the charge abscissae, and absent for
   the energy abscissae.

Step 5 is a row filter rather than a whole-dataset test. An EXFOR dataset frequently reports the
same product at several incident energies; admitting all of them and combining them later would
average an excitation function into a single number. For the same reason a window that still
holds several energies of one dataset rejects it: the rows are different measurements, and the
rejection names the energies so that the window can be narrowed to the one wanted.
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
    # Arbitrary units are fatal for most observables and normal for a spectrum, which is
    # conventionally measured relative and normalised afterwards. Where they are admitted the
    # data is written apart from absolute data rather than mixed with it.
    if !has_absolute_scale(kind) && !tolerates_relative_scale(query.ordinate)
        return Rejection(identifier, code, "value kind \"$(kind)\" has no absolute scale")
    end
    unit = last(parse_value_kind(kind))

    rule = tag_rule(query.abscissa, query.ordinate)
    reason = rejection_reason(rule, code)
    reason === nothing || return Rejection(identifier, code, reason)
    conflict = channel_qualifier_conflict(query.channel, code)
    if conflict !== nothing
        return Rejection(
            identifier,
            code,
            "reaction code carries \"$(conflict)\" ($(SPECTRUM_QUALIFIERS[conflict])), which \
             names a neutron spectrum no measurement in channel \"$(query.channel)\" was made \
             in",
        )
    end

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
        retained = sort!(unique(Float64.(skipmissing(table[!, COL_INCIDENT_ENERGY]))))
        if length(retained) > 1
            return Rejection(
                identifier,
                code,
                "$(length(retained)) incident energies, $(retained[begin] * EV_TO_MEV) to \
                 $(retained[end] * EV_TO_MEV) MeV, lie inside the window; rows at different \
                 energies are different measurements and are not combined — narrow the \
                 window to one of them",
            )
        end
    end

    varying = varying_variables(table, query.abscissa)
    if !isempty(varying)
        return Rejection(
            identifier,
            code,
            "also tabulated against $(join(varying, ", ")), which abscissa \
             $(query.abscissa) does not include; projecting it out would average over it",
        )
    end

    product = collect(skipmissing(table[!, COL_PRODUCT_ZA]))
    # An abscissa made of energies alone identifies no nuclide; every other one does.
    identifies_product =
        !all(
            quantity -> quantity in ("neutron_energy", "total_kinetic_energy"),
            query.abscissa,
        )
    if !identifies_product
        isempty(product) || return Rejection(
            identifier,
            code,
            "abscissa $(query.abscissa) expects no reaction product, but the dataset \
             identifies one",
        )
    else
        isempty(product) && return Rejection(
            identifier,
            code,
            "abscissa $(query.abscissa) needs a reaction product, which the dataset does \
             not identify",
        )
        if !("charge" in query.abscissa)
            # A bare mass number, so it must look like one. `ProdZA` is 1000·Z + A whenever the
            # product is charge-resolved, which for Z ≥ 10 exceeds 10⁴ — but for a light charge-
            # resolved product it does not: an α from ternary fission is 2004, and taken as a
            # mass number that is a fragment four times too heavy to exist. Bounding the value
            # from above is what separates the two codings for light products, and no bare
            # fission-fragment mass approaches the mass of the fissioning nucleus.
            maximum(product) > MAXIMUM_FRAGMENT_MASS && return Rejection(
                identifier,
                code,
                "abscissa $(query.abscissa) expects bare mass numbers, but the products \
                 reach $(maximum(product)), which is charge-coded rather than a mass",
            )
            minimum(product) ≤ MINIMUM_FRAGMENT_MASS && return Rejection(
                identifier,
                code,
                "product mass numbers reach $(minimum(product)), too light to be a fission \
                 fragment",
            )
        else
            minimum(product) < 1e4 && return Rejection(
                identifier,
                code,
                "abscissa $(query.abscissa) expects charge-coded products, but the \
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

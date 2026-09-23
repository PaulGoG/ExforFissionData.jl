# Parsing one retrieved dataset and deciding whether it answers the query.
#
# Selection runs in two stages. The csv rendering is screened first, for everything it can
# answer: the reaction code, the value kind and unit, and the incident-energy window. What a
# dataset is tabulated against is then read from the subentry DATA table, since the rendering
# truncates a non-integer mass and drops the variables it does not recognise. The two are aligned
# row by row, and a dataset on which they disagree is rejected.
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
- `table::DataFrame`: the rows of the csv rendering retained after unit, tag and
  incident-energy selection.
- `columns::DataFrame`: the subentry DATA columns of the same rows, in the same order, one
  column per heading with element type `Union{Missing,Float64}`. A repeated heading is made
  unique by a suffix, a second `FLAG` becoming `FLAG_1`.
- `units::Dict{String,String}`: the unit of each heading of `columns`, the first occurrence of a
  repeated heading deciding.
"""
struct Dataset
    identifier::String
    year::Int
    author::String
    reaction_code::String
    unit::String
    table::DataFrame
    columns::DataFrame
    units::Dict{String, String}
end

"""
    Screened

A dataset that passed every test the csv rendering can answer.

# Fields
- `identifier::String`, `year::Int`, `author::String`, `reaction_code::String`,
  `unit::String`: as on [`Dataset`](@ref).
- `table::DataFrame`: the full parsed csv rendering, every row.
- `keep::BitVector`: the rows inside the incident-energy window, all of them for spontaneous
  fission.

The subentry stage aligns `table` with the DATA table before applying `keep`, since both are in
the archive's row order.
"""
struct Screened
    identifier::String
    year::Int
    author::String
    reaction_code::String
    unit::String
    table::DataFrame
    keep::BitVector
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
        on_error = :collect,
        stringtype = String,
    )
    validate_header(names(table), "dataset $(identifier)")
    return table
end

"""
    screen_dataset(identifier, body, query) -> Union{Screened,Rejection}

The first stage of [`select_dataset`](@ref): every test the csv rendering of one dataset can
answer, in the order below, the first failure being reported.

1. the dataset is non-empty and carries a reaction code;
2. the `y:Value` column marks measurements rather than limits, and is not in arbitrary units;
3. the reaction code satisfies the composed tag rule of the abscissa and ordinate;
4. the reaction code carries no spectrum qualifier that contradicts the entrance channel; see
   [`CHANNEL_FORBIDDEN_QUALIFIERS`](@ref);
5. for induced fission, at least one row lies within the configured incident-energy window,
   and the rows inside it share one incident energy.

Step 5 marks rows rather than removing them, so that the table stays aligned with the subentry
DATA table until the second stage has compared the two.

# Arguments
- `identifier::AbstractString`: the dataset identifier.
- `body::AbstractString`: the csv rendering of the dataset.
- `query`: the [`Query`](@ref) to answer.

# Returns
A [`Screened`](@ref) or a [`Rejection`](@ref). Throws as [`parse_dataset`](@ref) does.
"""
function screen_dataset(identifier::AbstractString, body::AbstractString, query)
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
    keep = trues(nrow(table))
    if !query.spontaneous
        energies = table[!, COL_INCIDENT_ENERGY]
        keep = BitVector(map(energies) do value
            ismissing(value) && return false
            energy = Float64(value) * EV_TO_MEV
            query.energy_min ≤ energy ≤ query.energy_max
        end)
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
        retained = sort!(unique(Float64.(skipmissing(energies[keep]))))
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

    year_entry = _first_present(table[keep, COL_YEAR])
    author_entry = _first_present(table[keep, COL_AUTHOR])
    year = year_entry === nothing ? 0 : round(Int, year_entry)
    author = author_entry === nothing ? "unknown" : replace(String(author_entry), "+" => "")

    return Screened(String(identifier), year, author, code, unit, table, keep)
end

# The first row on which the csv rendering and the DATA table disagree, described, or `nothing`
# when they agree. The rendering truncates a mass, so the product is compared with the floor of
# the subentry mass; an energy is compared in MeV.
function _misalignment(table::DataFrame, data::SubentryColumns)
    product = table[!, COL_PRODUCT_ZA]
    m = column(data, "MASS")
    z = column(data, "ELEM")
    for i in 1:nrow(table)
        ismissing(product[i]) && continue
        za = round(Int, product[i])
        if m !== nothing && z === nothing
            mass = data.values[m][i]
            ismissing(mass) && continue
            floor(Int, mass) == za ||
                return "row $(i): csv ProdZA $(product[i]) against subentry MASS $(mass)"
        elseif m !== nothing && z !== nothing
            mass = data.values[m][i]
            charge = data.values[z][i]
            (ismissing(mass) || ismissing(charge)) && continue
            za == 1000 * round(Int, charge) + floor(Int, mass) ||
                return "row $(i): csv ProdZA $(product[i]) against subentry ELEM, MASS \
                        $(charge), $(mass)"
        elseif z !== nothing
            charge = data.values[z][i]
            ismissing(charge) && continue
            za ÷ 1000 == round(Int, charge) ||
                return "row $(i): csv ProdZA $(product[i]) against subentry ELEM $(charge)"
        end
    end

    secondary = table[!, COL_SECONDARY_ENERGY]
    e = column(data, "E")
    e === nothing && (e = column(data, "TKE"))
    e === nothing && return nothing
    factor = energy_factor(data.units[e])
    factor === nothing && return nothing
    for i in 1:nrow(table)
        value = data.values[e][i]
        (ismissing(secondary[i]) || ismissing(value)) && continue
        isapprox(secondary[i] * EV_TO_MEV, value * factor; rtol = 1.0e-6, atol = 1.0e-12) ||
            return "row $(i): csv x3(eV) $(secondary[i]) against subentry \
                    $(data.headings[e]) $(value)"
    end
    return nothing
end

# The DATA columns as a table, one column per heading, and the unit of each heading.
function _column_table(data::SubentryColumns)
    units = Dict{String, String}()
    for (heading, unit) in zip(data.headings, data.units)
        haskey(units, heading) || (units[heading] = unit)
    end
    isempty(data.headings) && return (DataFrame(), units)
    pairs = [heading => values for (heading, values) in zip(data.headings, data.values)]
    return (DataFrame(pairs...; makeunique = true), units)
end

"""
    select_dataset(screened, subentry_text, query) -> Union{Dataset,Rejection}

Decide whether one retrieved dataset answers `query`, and reduce it to the rows that do.

The csv rendering has been screened by [`screen_dataset`](@ref), steps 1 to 5 below; the
subentry DATA table then settles what the dataset is tabulated against. The first failure is
reported.

1. the dataset is non-empty and carries a reaction code;
2. the `y:Value` column marks measurements rather than limits, and is not in arbitrary units;
3. the reaction code satisfies the composed tag rule of the abscissa and ordinate;
4. the reaction code carries no spectrum qualifier that contradicts the entrance channel; see
   [`CHANNEL_FORBIDDEN_QUALIFIERS`](@ref);
5. for induced fission, at least one row lies within the configured incident-energy window,
   and the rows inside it share one incident energy;
6. the subentry parses, and, for a spectrum, its energies are not in the centre-of-mass frame
   (`E-CM`, `DATA-CM`);
7. the DATA table, restricted to the lines that carry a datum in this dataset's `DATA` column,
   has one line per row of the rendering and agrees with it row by row: the truncated product
   against `MASS` and `ELEM`, the secondary energy against `E` or `TKE`. Only then are the rows
   of step 5 retained;
8. no independent variable of the DATA table other than the abscissa's own varies over the
   retained rows; see [`varying_columns`](@ref);
9. the DATA table carries a column for every quantity of the abscissa, or its bin pair, and an
   energy column is in a unit [`energy_factor`](@ref) converts;
10. the product identification is consistent with the abscissa: present and mass-coded for the
    fragment-mass abscissae, present and charge-coded for the charge abscissae, and absent for
    the energy abscissae.

Step 5 is a row filter rather than a whole-dataset test. An EXFOR dataset frequently reports the
same product at several incident energies; admitting all of them and combining them later would
average an excitation function into a single number. For the same reason a window that still
holds several energies of one dataset rejects it: the rows are different measurements, and the
rejection names the energies so that the window can be narrowed to the one wanted.

The frame is tested before the tables are compared, since a centre-of-mass spectrum has no
`DATA` column and varies in `E-CM`, and would otherwise be rejected for a reason that does not
name its frame.

# Arguments
- `screened::Screened`: the outcome of [`screen_dataset`](@ref).
- `subentry_text::AbstractString`: the text `x4get?sub=` returns for the dataset.
- `query`: the [`Query`](@ref) to answer.

# Returns
A [`Dataset`](@ref) or a [`Rejection`](@ref). A [`SubentryError`](@ref) becomes a rejection;
any other exception propagates.
"""
function select_dataset(screened::Screened, subentry_text::AbstractString, query)
    identifier = screened.identifier
    code = screened.reaction_code
    subentry = try
        parse_subentry(subentry_text, identifier)
    catch exception
        exception isa SubentryError || rethrow()
        return Rejection(identifier, code, "subentry: " * exception.msg)
    end

    # A centre-of-mass spectrum heads its columns E-CM and DATA-CM, so it is told from its
    # headings before any row is compared.
    if "neutron_energy" in query.abscissa &&
       any(heading -> heading in ("E-CM", "DATA-CM"), subentry.data.headings)
        return Rejection(
            identifier,
            code,
            "energies are in the centre-of-mass frame (E-CM), not the laboratory frame of a \
             spectrum",
        )
    end

    # The rendering writes one row per line that carries a datum: a line whose DATA field is
    # blank — the pointed column of another dataset holds the value there — has no row. The
    # DATA table is restricted to the lines with a datum before the two are compared.
    datum = column(subentry.data, "DATA")
    datum === nothing && return Rejection(
        identifier,
        code,
        "the subentry DATA table has no DATA column; its values are limits or derived \
         quantities the rendering does not present as measurements",
    )
    data = restrict(subentry.data, BitVector(map(!ismissing, subentry.data.values[datum])))

    rows = nrow(screened.table)
    lines = line_count(data)
    lines == rows || return Rejection(
        identifier,
        code,
        "the csv rendering has $(rows) rows and the subentry DATA table $(lines) lines, so \
         they cannot be aligned",
    )
    misalignment = _misalignment(screened.table, data)
    misalignment === nothing || return Rejection(
        identifier,
        code,
        "the csv rendering and the subentry DATA table disagree at " * misalignment,
    )

    table = screened.table[screened.keep, :]
    data = restrict(data, screened.keep)

    varying = varying_columns(data, query.abscissa)
    if !isempty(varying)
        return Rejection(
            identifier,
            code,
            "also tabulated against $(join(varying, ", ")), which abscissa \
             $(query.abscissa) does not include; projecting it out would average over it",
        )
    end

    for quantity in query.abscissa
        indices, _ = abscissa_columns(data, quantity)
        if isempty(indices)
            value_headings, bin_headings = ABSCISSA_HEADINGS[quantity]
            pair = isempty(bin_headings) ? "" : ", or the pair $(join(bin_headings, "/"))"
            return Rejection(
                identifier,
                code,
                "abscissa quantity \"$(quantity)\" needs a $(join(value_headings, "/")) \
                 column$(pair), which the subentry DATA table does not carry",
            )
        end
        quantity in ("neutron_energy", "total_kinetic_energy") || continue
        for index in indices
            unit = data.units[index]
            energy_factor(unit) === nothing && return Rejection(
                identifier,
                code,
                "unit \"$(unit)\" of column $(data.headings[index]) is not an energy unit \
                 this package converts",
            )
        end
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

    columns, units = _column_table(data)
    return Dataset(
        identifier,
        screened.year,
        screened.author,
        code,
        screened.unit,
        table,
        columns,
        units,
    )
end

"""
    select_dataset(identifier, body, subentry_text, query) -> Union{Dataset,Rejection}

The two stages of selection in one call: [`screen_dataset`](@ref) over the csv rendering
`body`, then [`select_dataset`](@ref) over the subentry text of a dataset that passed.
"""
function select_dataset(
    identifier::AbstractString,
    body::AbstractString,
    subentry_text::AbstractString,
    query,
)
    screened = screen_dataset(identifier, body, query)
    screened isa Rejection && return screened
    return select_dataset(screened, subentry_text, query)
end

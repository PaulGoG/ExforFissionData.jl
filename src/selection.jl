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
- `record::Dict{String,Any}`: what selection read of the dataset beyond its columns, written to
  the run record under the same keys: `ordinate_frame` and `ordinate_frame_evidence` of a mean
  neutron energy, `maxwellian_temperature_mev` and `maxwellian_temperature_source` of a ratio
  to a Maxwellian, `ratio_numerator`, `ratio_denominator` and `ratio_orientation` of a ratio
  of two spectra. Empty for every other dataset, and for the eight-argument constructor.
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
    record::Dict{String, Any}
end

Dataset(identifier, year, author, reaction_code, unit, table, columns, units) = Dataset(
    identifier,
    year,
    author,
    reaction_code,
    unit,
    table,
    columns,
    units,
    Dict{String, Any}(),
)

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
    screen_dataset(identifier, body, query; widths = WidthColumn[]) -> Union{Screened,Rejection}

The first stage of [`select_dataset`](@ref): every test the csv rendering of one dataset can
answer, in the order below, the first failure being reported.

1. the dataset is non-empty and carries a reaction code;
2. the `y:Value` column marks measurements rather than limits, and is not in arbitrary units;
3. the reaction code satisfies the composed tag rule of the abscissa and ordinate — or, for a
   dataset of [`CURATED_DATASETS`](@ref), the curated ordinate is the one asked for and the
   code satisfies the abscissa rule; see [`curation_rejection`](@ref). Under the ordinate
   [`REFERENCE_RATIO_ORDINATE`](@ref) the code is instead the ratio of the spectrum of the
   system and that of 252-Cf(sf); see [`spectrum_ratio`](@ref). A slice of the joint
   distribution is not Y(A, TKE) ([`SLICE_DATASETS`](@ref)), and a pre-neutron mass abscissa
   refuses the entries whose masses are provisional ([`PROVISIONAL_MASS_ENTRIES`](@ref));
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
- `widths`: the width columns the configuration names, which alone the ordinate
  `total_kinetic_energy_dispersion` reads; see [`WidthColumn`](@ref).

# Returns
A [`Screened`](@ref) or a [`Rejection`](@ref). Throws as [`parse_dataset`](@ref) does.
"""
function screen_dataset(
    identifier::AbstractString,
    body::AbstractString,
    query;
    widths::AbstractVector{WidthColumn} = WidthColumn[],
)
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
    if !has_absolute_scale(kind) &&
       !tolerates_relative_scale(query.ordinate, query.abscissa)
        return Rejection(identifier, code, "value kind \"$(kind)\" has no absolute scale")
    end
    unit = last(parse_value_kind(kind))

    # A width is read from the datasets of the mean the configuration names, and only from
    # them; a width of one fragment's energy is selected as that energy is.
    # A dataset the configuration does not name is judged as a mean TKE first, so that the record
    # gives the substantive reason where there is one; it is refused as unnamed only after.
    ordinate = query.ordinate
    width = nothing
    if ordinate == WIDTH_ORDINATE
        excluded = get(WIDTH_EXCLUSIONS, String(identifier), nothing)
        excluded === nothing || return Rejection(identifier, code, excluded)
        width = mapped_width(widths, identifier)
        ordinate = width === nothing ? "total_kinetic_energy" : width.of
    end
    # Provisional masses disqualify a dataset against pre-neutron mass whatever its code says,
    # so this reason is given first.
    if "mass" in query.abscissa
        provisional = provisional_mass(identifier)
        provisional === nothing || return Rejection(identifier, code, provisional)
    end
    curation = get(CURATED_DATASETS, String(identifier), nothing)
    reason = something(
        slice_rejection(identifier, query.abscissa, ordinate),
        if ordinate == REFERENCE_RATIO_ORDINATE
            # The one ordinate read from a combination of reaction codes.
            ratio = spectrum_ratio(code, system_reaction(query), query.channel)
            ratio isa String ? ratio : nothing
        elseif curation === nothing
            rejection_reason(tag_rule(query.abscissa, ordinate), code)
        else
            curation_rejection(curation, query.abscissa, ordinate, code)
        end,
        Some(nothing),
    )
    reason === nothing || return Rejection(identifier, code, reason)
    if query.ordinate == WIDTH_ORDINATE && width === nothing
        return Rejection(
            identifier,
            code,
            "no width column of this dataset is named in the configuration ([[width]])",
        )
    end
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
            za == ZA_CHARGE_FACTOR * round(Int, charge) + floor(Int, mass) ||
                return "row $(i): csv ProdZA $(product[i]) against subentry ELEM, MASS \
                        $(charge), $(mass)"
        elseif z !== nothing
            charge = data.values[z][i]
            ismissing(charge) && continue
            za ÷ ZA_CHARGE_FACTOR == round(Int, charge) ||
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

"""
Relative tolerance within which a value of the csv rendering restates the value of its subentry
line. The rendering writes six significant digits, 101.9375 MeV as `1.01938e+8` eV, so the two
differ by up to five parts in a million.
"""
const RENDERING_TOLERANCE = 1.0e-5

# The first row on which the ordinate of the csv rendering and the datum column `datum` of the
# DATA table disagree as energies, described, or `nothing` when they agree; both are compared in
# MeV. A unit that is no energy is described likewise.
function _ordinate_misalignment(
    table::DataFrame,
    data::SubentryColumns,
    datum::Int,
    unit::AbstractString,
)
    heading = data.headings[datum]
    rendered = energy_factor(unit)
    tabulated = energy_factor(data.units[datum])
    (rendered === nothing || tabulated === nothing) &&
        return "the ordinate: the rendering gives it in $(unit) and the subentry heads \
                $(heading) $(data.units[datum]), which are not both energy units this \
                package converts"
    ordinate = table[!, COL_Y]
    for i in 1:nrow(table)
        value = data.values[datum][i]
        (ismissing(ordinate[i]) || ismissing(value)) && continue
        isapprox(ordinate[i] * rendered, value * tabulated; rtol = RENDERING_TOLERANCE) ||
            return "row $(i): csv y $(ordinate[i]) $(unit) against subentry $(heading) \
                    $(value) $(data.units[datum])"
    end
    return nothing
end

"""
    neutron_energy_refusal(ordinate, unit) -> Union{String,Nothing}

The reason the values `ordinate`, in `unit`, are not mean neutron energies, or `nothing` when
none exceeds [`MAXIMUM_NEUTRON_KINETIC_ENERGY`](@ref): the number of rows above the bound and
the largest value, or a unit that is no energy.
"""
function neutron_energy_refusal(ordinate::AbstractVector, unit::AbstractString)
    factor = energy_factor(unit)
    factor === nothing &&
        return "the ordinate is in $(unit), which is not an energy unit this package converts"
    values = Float64[v * factor for v in skipmissing(ordinate)]
    above = count(>(MAXIMUM_NEUTRON_KINETIC_ENERGY), values)
    above == 0 && return nothing
    return "$(above) of $(length(values)) rows hold more than \
            $(MAXIMUM_NEUTRON_KINETIC_ENERGY) MeV, up to \
            $(round(maximum(values); sigdigits = 4)) MeV, which no mean neutron energy \
            reaches: the column holds another energy, a fragment kinetic energy for one, \
            under the code of a neutron energy"
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
    select_dataset(screened, subentry_text, query; widths = WidthColumn[])
        -> Union{Dataset,Rejection}

Decide whether one retrieved dataset answers `query`, and reduce it to the rows that do.

The csv rendering has been screened by [`screen_dataset`](@ref); the subentry DATA table then
settles what the dataset is tabulated against. The first failure is reported.

1–5. the csv tests of [`screen_dataset`](@ref), in its order;
6. the subentry parses; for a spectrum, its energies are not in the centre-of-mass frame
   (`E-CM`, `DATA-CM`); a ratio to the spectrum of 252-Cf(sf) has no variable headed for its
   numerator or denominator alone (`-NM`, `-DN`), so that both spectra are taken at one
   outgoing energy; and a DATA column the subentry gives in arbitrary units is taken as
   such, whatever unit the csv rendering reports, and passes only where the observable admits a
   relative scale. A mean neutron energy exceeds [`MAXIMUM_NEUTRON_KINETIC_ENERGY`](@ref) on
   no row of step 5; see [`neutron_energy_refusal`](@ref);
7. the DATA table, restricted to the lines that carry a datum in this dataset's datum column —
   `DATA`, or `DATA-CM` for an ordinate of [`CENTRE_OF_MASS_ORDINATES`](@ref); see
   [`datum_heading`](@ref) — has one line per row of the rendering and agrees with it row by
   row: the truncated product against `MASS` and `ELEM`, the secondary energy against `E` or
   `TKE`, and for those ordinates the value itself against the datum column. Only then are the
   rows of step 5 retained, less the lines a compilation defect of [`ARCHIVE_DEFECTS`](@ref)
   marks — and a defect record the archive no longer matches rejects the dataset;
8. a mean neutron energy is not stated to be in the laboratory frame; see
   [`ordinate_frame`](@ref). No independent variable of the DATA table other than the abscissa's
   own varies over the retained rows; see [`varying_columns`](@ref);
9. the DATA table carries a column for every quantity of the abscissa, or its bin pair, and an
   energy column is in a unit [`energy_factor`](@ref) converts;
10. the product identification is consistent with the abscissa: present and mass-coded for the
    fragment-mass abscissae, present and charge-coded for the charge abscissae, and absent for
    the energy abscissae;
11. a spectrum given as a ratio to a Maxwellian states the temperature of that Maxwellian; see
    [`maxwellian_temperature`](@ref).

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
- `widths`: the width columns the configuration names, which alone the ordinate
  `total_kinetic_energy_dispersion` reads; see [`WidthColumn`](@ref).

# Returns
A [`Dataset`](@ref) or a [`Rejection`](@ref). A [`SubentryError`](@ref) becomes a rejection;
any other exception propagates.
"""
function select_dataset(
    screened::Screened,
    subentry_text::AbstractString,
    query;
    widths::AbstractVector{WidthColumn} = WidthColumn[],
)
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

    # The two spectra of a ratio are taken at one outgoing energy: a variable headed for the
    # numerator or the denominator alone (-NM, -DN) says they are not.
    if query.ordinate == REFERENCE_RATIO_ORDINATE
        split_headings =
            filter(h -> endswith(h, "-NM") || endswith(h, "-DN"), subentry.data.headings)
        isempty(split_headings) || return Rejection(
            identifier,
            code,
            "numerator and denominator are tabulated against variables of their own \
             ($(join(split_headings, ", "))), not both at one outgoing energy",
        )
    end

    # The rendering writes one row per line that carries a datum: a line whose DATA field is
    # blank — the pointed column of another dataset holds the value there — has no row. The
    # DATA table is restricted to the lines with a datum before the two are compared.
    datum_name = datum_heading(query.ordinate, subentry.data.headings)
    datum = datum_name === nothing ? nothing : column(subentry.data, datum_name)
    datum === nothing && return Rejection(
        identifier,
        code,
        "the subentry DATA table has no DATA column; its values are limits or derived \
         quantities the rendering does not present as measurements",
    )
    data = restrict(subentry.data, BitVector(map(!ismissing, subentry.data.values[datum])))

    # A fragment energy coded as a neutron energy is named for what it is before anything else
    # is asked of its table.
    if query.ordinate in CENTRE_OF_MASS_ORDINATES
        refusal =
            neutron_energy_refusal(screened.table[screened.keep, COL_Y], screened.unit)
        refusal === nothing || return Rejection(identifier, code, refusal)
    end

    width = query.ordinate == WIDTH_ORDINATE ? mapped_width(widths, identifier) : nothing
    if width !== nothing
        index = column(data, width.column)
        index === nothing && return Rejection(
            identifier,
            code,
            "the configuration names column $(width.column) as a width, which the subentry \
             DATA table does not carry",
        )
        unit = data.units[index]
        convertible = if width.holds == "variance"
            haskey(VARIANCE_UNIT_FACTORS, unit)
        else
            energy_factor(unit) !== nothing
        end
        convertible || return Rejection(
            identifier,
            code,
            "column $(width.column) is headed $(unit), which is not a unit of a \
             $(replace(width.holds, '_' => ' ')) of an energy this package converts",
        )
        stale = width_row_refusal(identifier, data, width.column)
        stale === nothing || return Rejection(identifier, code, stale)
    end

    # The rendering can misstate the unit: 23268002 is counts, ARB-UNITS in its subentry and
    # PART/FIS in the csv. An arbitrary scale the subentry states is not overruled.
    dataset_unit = screened.unit
    subentry_unit = subentry.data.units[datum]
    if is_relative_unit(subentry_unit) && !is_relative_unit(dataset_unit)
        tolerates_relative_scale(query.ordinate, query.abscissa) || return Rejection(
            identifier,
            code,
            "the subentry gives DATA in $(subentry_unit), which the csv rendering reports as \
             $(dataset_unit); the dataset has no absolute scale",
        )
        dataset_unit = subentry_unit
    end
    curated = get(CURATED_DATASETS, identifier, nothing)
    (curated === nothing || curated.unit === nothing) || (dataset_unit = curated.unit)

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
    # A datum in the centre-of-mass frame is read from its own column, so the rendering is held
    # against that column line by line before it stands for it.
    if query.ordinate in CENTRE_OF_MASS_ORDINATES
        misalignment = _ordinate_misalignment(screened.table, data, datum, screened.unit)
        misalignment === nothing || return Rejection(
            identifier,
            code,
            "the csv rendering and the subentry DATA table disagree at " * misalignment,
        )
    end

    keep = copy(screened.keep)
    defects = get(ARCHIVE_DEFECTS, identifier, nothing)
    if defects !== nothing
        marked = defect_lines(defects, data)
        marked isa String && return Rejection(identifier, code, marked)
        keep .&= .!marked
    end
    table = screened.table[keep, :]
    data = restrict(data, keep)

    # What selection reads of the dataset beyond its columns, for the run record.
    record = Dict{String, Any}()
    if query.ordinate in CENTRE_OF_MASS_ORDINATES
        frame = ordinate_frame(identifier, data.headings)
        frame.frame == "laboratory" && return Rejection(
            identifier,
            code,
            "the mean neutron energy is in the laboratory frame, not the centre-of-mass \
             frame of the fragment: " * frame.evidence,
        )
        record["ordinate_frame"] = frame.frame
        record["ordinate_frame_evidence"] = frame.evidence
    end

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
        quantity in ENERGY_ABSCISSAE || continue
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
    identifies_product = !all(quantity -> quantity in ENERGY_ABSCISSAE, query.abscissa)
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
            # product is charge-resolved, which for Z ≥ 10 reaches `CHARGE_CODED_MINIMUM` — but
            # for a light charge-resolved product it does not: an α from ternary fission is 2004,
            # and taken as a mass number that is a fragment four times too heavy to exist.
            # Bounding the value from above is what separates the two codings for light
            # products, and no bare fission-fragment mass approaches the mass of the fissioning
            # nucleus.
            maximum(product) > MAXIMUM_FRAGMENT_MASS && return Rejection(
                identifier,
                code,
                "abscissa $(query.abscissa) expects bare mass numbers, but the products \
                 reach $(maximum(product)), which is charge-coded rather than a mass",
            )
            minimum(product) < MINIMUM_FRAGMENT_MASS && return Rejection(
                identifier,
                code,
                "product mass numbers reach $(minimum(product)), too light to be a fission \
                 fragment",
            )
        else
            minimum(product) < CHARGE_CODED_MINIMUM && return Rejection(
                identifier,
                code,
                "abscissa $(query.abscissa) expects charge-coded products, but the \
                 products are bare mass numbers",
            )
        end
    end

    # A multiplicity headed PC/FIS is written on its subentry's scale, which needs the csv
    # rendering to restate every line by one factor.
    if query.ordinate in MULTIPLICITY_ORDINATES && subentry_unit == PERCENT_PER_FISSION
        rendering_scale(table[!, COL_Y], data.values[column(data, "DATA")]) === nothing &&
            return Rejection(
                identifier,
                code,
                "the subentry heads the multiplicity $(PERCENT_PER_FISSION), a miscoding of \
                 a number per fission, and the csv rendering does not restate its lines by \
                 one factor, so the scale of the subentry cannot be recovered",
            )
    end

    # The record of a ratio says which of the two spectra is the numerator.
    if query.ordinate == REFERENCE_RATIO_ORDINATE
        ratio = spectrum_ratio(code, system_reaction(query), query.channel)
        ratio isa String && return Rejection(identifier, code, ratio)
        record["ratio_numerator"] = ratio.numerator
        record["ratio_denominator"] = ratio.denominator
        record["ratio_orientation"] = ratio.orientation
    end

    # A ratio to a Maxwellian states a spectrum only with the temperature it was formed with.
    if query.ordinate == MAXWELLIAN_RATIO_ORDINATE
        temperature = maxwellian_temperature(identifier, subentry, data)
        temperature isa String && return Rejection(identifier, code, temperature)
        record["maxwellian_temperature_mev"] = temperature.temperature
        record["maxwellian_temperature_source"] = temperature.source
    end

    columns, units = _column_table(data)
    return Dataset(
        identifier,
        screened.year,
        screened.author,
        code,
        dataset_unit,
        table,
        columns,
        units,
        record,
    )
end

"""
    select_dataset(identifier, body, subentry_text, query; widths = WidthColumn[])
        -> Union{Dataset,Rejection}

The two stages of selection in one call: [`screen_dataset`](@ref) over the csv rendering
`body`, then [`select_dataset`](@ref) over the subentry text of a dataset that passed.
"""
function select_dataset(
    identifier::AbstractString,
    body::AbstractString,
    subentry_text::AbstractString,
    query;
    widths::AbstractVector{WidthColumn} = WidthColumn[],
)
    screened = screen_dataset(identifier, body, query; widths)
    screened isa Rejection && return screened
    return select_dataset(screened, subentry_text, query; widths)
end

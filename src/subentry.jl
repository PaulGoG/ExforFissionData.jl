# Reading of the numerical sections of an EXFOR subentry: the fixed-column COMMON and DATA
# sections of IAEA-NDS-207, the EXFOR Formats Manual, chapters 2, 4 and 5.
#
# The csv rendering is not enough for every dataset. It truncates a non-integer mass to an
# integer and drops the independent variables it does not recognise. The subentry is the
# archive's own statement of what a dataset is tabulated against: every heading, unit and value
# as the compiler entered them, resolved here to the columns of one dataset.

"""
    SubentryError(message)

A subentry whose numerical sections cannot be read as the format prescribes, or which does not
hold the dataset asked of it.

A type of its own so that the pipeline can record it as a rejection of that dataset rather than
a defect of this package.
"""
struct SubentryError <: Exception
    msg::String
end

Base.showerror(io::IO, exception::SubentryError) =
    print(io, "SubentryError: ", exception.msg)

"""
    SubentryColumns(headings, units, pointers, values)

One numerical section of a subentry, restricted to the columns of one dataset.

# Fields
- `headings::Vector{String}`: the 10-character data headings, stripped (`"MASS"`,
  `"DATA-ERR"`).
- `units::Vector{String}`: the unit of each column, stripped (`"NO-DIM"`, `"PC/FIS"`).
- `pointers::Vector{Char}`: the pointer of each column, `' '` where none.
- `values::Vector{Vector{Union{Missing,Float64}}}`: one vector per column, one entry per line of
  the section, `missing` for a blank field.

All four vectors have one entry per column.
"""
struct SubentryColumns
    headings::Vector{String}
    units::Vector{String}
    pointers::Vector{Char}
    values::Vector{Vector{Union{Missing, Float64}}}
end

"""
    Subentry(identifier, pointer, entry_common, common, data)

The numerical content of one dataset.

# Fields
- `identifier::String`: the subentry identifier, 8 characters.
- `pointer::Union{Nothing,Char}`: the pointer of the dataset, `nothing` when it names none.
- `entry_common::SubentryColumns`: the COMMON section of subentry 001, the constants of the
  whole entry.
- `common::SubentryColumns`: the subentry's own COMMON section.
- `data::SubentryColumns`: the DATA table of the subentry.

Every section holds only the columns of this dataset. An absent section is a
[`SubentryColumns`](@ref) with no columns.
"""
struct Subentry
    identifier::String
    pointer::Union{Nothing, Char}
    entry_common::SubentryColumns
    common::SubentryColumns
    data::SubentryColumns
end

"""Width in columns of one field of a numerical section, per the EXFOR Formats Manual."""
const FIELD_WIDTH = 11

"""Number of fields on one record of a numerical section, per the EXFOR Formats Manual."""
const FIELDS_PER_RECORD = 6

"""
Width in columns of the data-carrying part of a record, per the EXFOR Formats Manual; columns
67–80, when present, are identification.
"""
const RECORD_WIDTH = 66

# Matches a mantissa followed directly by a signed exponent with the `E` omitted, `1.4-1`.
const _IMPLICIT_EXPONENT = r"^([+-]?(?:\d+\.?\d*|\.\d+))([+-]\d+)$"

"""
    parse_exfor_number(field) -> Union{Missing,Float64}

The value of one numerical field of a COMMON or DATA section.

The field is FORTRAN-readable floating point: the decimal point is always present, the number
may sit anywhere in the field, the exponent may be written without `E` or with the double
precision `D`, and blanks may occur inside the field. `1.4-1` and `1.40    E-01` read as 0.14,
`1.2D-3` as 0.0012.

# Arguments
- `field::AbstractString`: the field, usually 11 characters.

# Returns
`missing` for a field with no non-blank character, the value otherwise. Throws a
[`SubentryError`](@ref) when the field is not a finite number.

# Example

```julia
julia> parse_exfor_number("   1.4-1   ")
0.14
```
"""
function parse_exfor_number(field::AbstractString)
    compact = filter(!isspace, field)
    isempty(compact) && return missing
    compact = replace(compact, 'D' => 'e', 'd' => 'e')
    if !occursin('e', compact) && !occursin('E', compact)
        implicit = match(_IMPLICIT_EXPONENT, compact)
        if implicit !== nothing
            compact = string(implicit.captures[1], 'e', implicit.captures[2])
        end
    end
    value = tryparse(Float64, compact)
    if value === nothing || !isfinite(value)
        throw(SubentryError("cannot read \"$(field)\" as a number"))
    end
    return value
end

"""
    dataset_pointer(identifier) -> Union{Nothing,Char}

The pointer of an EXFOR dataset: the ninth character of its identifier, or `nothing` for an
identifier of eight characters.

# Arguments
- `identifier::AbstractString`: the dataset identifier.

# Returns
The pointer as a `Char`, or `nothing`. Throws an `ArgumentError`, as
[`subentry_identifier`](@ref) does, unless `identifier` has eight or nine characters.

# Example

```julia
julia> dataset_pointer("30666002I")
'I': ASCII/Unicode U+0049 (category Lu: Letter, uppercase)
```
"""
function dataset_pointer(identifier::AbstractString)
    subentry_identifier(identifier)
    return length(identifier) == 9 ? last(identifier) : nothing
end

# A section with no columns, standing for NOCOMMON and for sections the text does not hold.
function _no_columns()
    return SubentryColumns(String[], String[], Char[], Vector{Union{Missing, Float64}}[])
end

# One record: the data-carrying columns of a line, padded with blanks to the full width.
function _record(line::AbstractString)
    truncated = first(line, RECORD_WIDTH)
    return string(truncated, " "^(RECORD_WIDTH - length(truncated)))
end

# The system identifier of a record, its first whitespace token; empty for a blank record.
function _system_identifier(record::AbstractString)
    stripped = lstrip(record)
    stop = findfirst(isspace, stripped)
    return stop === nothing ? stripped : SubString(stripped, 1, prevind(stripped, stop))
end

# The counters N1 and N2 of a system record, its second and third tokens.
function _counters(record::AbstractString)
    tokens = split(record)
    n1 = length(tokens) ≥ 2 ? tryparse(Int, tokens[2]) : nothing
    n2 = length(tokens) ≥ 3 ? tryparse(Int, tokens[3]) : nothing
    if n1 === nothing || n2 === nothing
        throw(
            SubentryError(
                "cannot read the counters N1, N2 of the record \"$(rstrip(record))\"",
            ),
        )
    end
    return n1::Int, n2::Int
end

# The subentry number carried by a SUBENT record.
function _subentry_number(record::AbstractString)
    tokens = split(record)
    length(tokens) ≥ 2 ||
        throw(SubentryError("the record \"$(rstrip(record))\" names no subentry"))
    return String(tokens[2])
end

# The index of the record after the ENDBIB closing the BIB section opened at `start`.
function _skip_bib(records::Vector{String}, start::Int, subentry::AbstractString)
    for index in (start + 1):length(records)
        _system_identifier(records[index]) == "ENDBIB" && return index + 1
    end
    throw(SubentryError("subentry $(subentry): BIB section has no ENDBIB record"))
end

# Field `k` of a record, counted from 1 within the record.
function _field(record::AbstractString, k::Integer)
    start = nextind(record, 0, FIELD_WIDTH * (k - 1) + 1)
    stop = nextind(record, 0, FIELD_WIDTH * k)
    return SubString(record, start, stop)
end

# The COMMON or DATA section whose system record is `records[start]`, and the index of the
# record after its closing ENDCOMMON or ENDDATA. A row of the section spans
# `cld(n1, FIELDS_PER_RECORD)` records; COMMON holds one value row, DATA holds `n2`.
function _read_section(
    records::Vector{String},
    start::Int,
    n1::Int,
    n2::Int,
    kind::String,
    subentry::AbstractString,
)
    (n1 ≥ 0 && n2 ≥ 0) || throw(
        SubentryError("subentry $(subentry): $(kind) record carries a negative counter"),
    )
    records_per_row = cld(n1, FIELDS_PER_RECORD)
    if kind == "COMMON" && n2 != 3 * records_per_row
        throw(
            SubentryError(
                "subentry $(subentry): COMMON record gives $(n2) records for $(n1) fields, \
                 the format prescribes $(3 * records_per_row)",
            ),
        )
    end
    rows = kind == "COMMON" ? 1 : n2
    stop = start + (2 + rows) * records_per_row + 1
    if stop > length(records) || _system_identifier(records[stop]) != "END" * kind
        throw(
            SubentryError(
                "subentry $(subentry): $(kind) section does not end where its counters \
                 say",
            ),
        )
    end

    headings = Vector{String}(undef, n1)
    units = Vector{String}(undef, n1)
    pointers = Vector{Char}(undef, n1)
    values = Vector{Vector{Union{Missing, Float64}}}(undef, n1)
    for j in 1:n1
        offset = cld(j, FIELDS_PER_RECORD)
        k = mod1(j, FIELDS_PER_RECORD)
        heading = _field(records[start + offset], k)
        headings[j] = String(strip(first(heading, FIELD_WIDTH - 1)))
        pointers[j] = last(heading)
        units[j] = String(strip(_field(records[start + records_per_row + offset], k)))
        column_values = Vector{Union{Missing, Float64}}(undef, rows)
        for i in 1:rows
            record = records[start + (1 + i) * records_per_row + offset]
            column_values[i] = parse_exfor_number(_field(record, k))
        end
        values[j] = column_values
    end
    return SubentryColumns(headings, units, pointers, values), stop + 1
end

# The columns of `columns` belonging to the dataset with `pointer`: those without a pointer
# and those carrying this one.
function _select_columns(columns::SubentryColumns, pointer::Union{Nothing, Char})
    keep = findall(p -> p == ' ' || p == pointer, columns.pointers)
    return SubentryColumns(
        columns.headings[keep],
        columns.units[keep],
        columns.pointers[keep],
        columns.values[keep],
    )
end

"""
    parse_subentry(text, identifier) -> Subentry

The numerical content of one dataset, read from the entry excerpt the archive returns for
`x4get?sub=<subentry>`.

The excerpt holds subentry 001 of the entry and the subentry of the dataset. The COMMON section
of the first and the COMMON and DATA sections of the second are read at their fixed columns and
restricted to the columns of the dataset: those without a pointer and those carrying the pointer
of `identifier`. BIB sections are skipped.

# Arguments
- `text::AbstractString`: the subentry text.
- `identifier::AbstractString`: the dataset identifier, 8 characters or 9 with a pointer.

# Returns
A [`Subentry`](@ref). Throws a [`SubentryError`](@ref) when the text is not a usable response,
does not hold the subentry or its DATA section, has a section whose extent disagrees with its
counters or holds a field that is not a number, or when the pointer of `identifier` does not
match the columns of the subentry; an `ArgumentError` when `identifier` is malformed.

# Example

```julia
julia> subentry = parse_subentry(text, "400170021");

julia> subentry.data.headings
```
"""
function parse_subentry(text::AbstractString, identifier::AbstractString)
    subentry = subentry_identifier(identifier)
    pointer = dataset_pointer(identifier)
    entry = first(subentry, 5)
    is_usable_response(text) ||
        throw(SubentryError("the archive returned no subentry text for $(subentry)"))

    records = String[_record(line) for line in eachline(IOBuffer(String(text)))]
    entry_subentry = entry * "001"
    entry_common = _no_columns()
    common = _no_columns()
    data::Union{Nothing, SubentryColumns} = nothing
    seen = false
    current = ""
    index = 1
    while index ≤ length(records)
        record = records[index]
        keyword = _system_identifier(record)
        if keyword == "SUBENT"
            current = _subentry_number(record)
            seen = seen || current == subentry
            index += 1
        elseif keyword == "ENDSUBENT"
            current = ""
            index += 1
        elseif keyword == "BIB"
            # Free text may open a record with a word that is also a system identifier.
            index = _skip_bib(records, index, current)
        elseif keyword == "COMMON" || keyword == "DATA"
            kind = String(keyword)
            n1, n2 = _counters(record)
            section, index = _read_section(records, index, n1, n2, kind, current)
            if kind == "COMMON"
                current == entry_subentry && (entry_common = section)
                current == subentry && (common = section)
            elseif current == subentry
                data = section
            end
        else
            index += 1
        end
    end
    seen || throw(SubentryError("subentry $(subentry) is not in the text"))
    data === nothing && throw(SubentryError("subentry $(subentry) has no DATA section"))

    if pointer === nothing
        any(!=(' '), data.pointers) && throw(
            SubentryError(
                "subentry $(subentry) holds pointed columns, but dataset $(identifier) \
                 names no pointer",
            ),
        )
    else
        any(columns -> pointer in columns.pointers, (entry_common, common, data)) || throw(
            SubentryError(
                "dataset pointer '$(pointer)' is carried by no column of subentry \
                 $(subentry)",
            ),
        )
    end
    return Subentry(
        subentry,
        pointer,
        _select_columns(entry_common, pointer),
        _select_columns(common, pointer),
        _select_columns(data, pointer),
    )
end

"""
    column(columns, heading) -> Union{Nothing,Int}

The index of the first column of `columns` whose heading is `heading`, or `nothing` when no
column carries it.

# Example

```julia
julia> column(subentry.data, "MASS")
1
```
"""
function column(columns::SubentryColumns, heading::AbstractString)
    return findfirst(==(heading), columns.headings)
end

"""
    line_count(columns) -> Int

The number of lines of a section: the length of its value vectors, 0 when it has no columns.
"""
function line_count(columns::SubentryColumns)
    return isempty(columns.values) ? 0 : length(first(columns.values))
end

# Heading prefixes of the columns auxiliary to a datum: monitors, assumed values, flags,
# miscellaneous information, and the kT of a Maxwellian average.
const _AUXILIARY_PREFIXES = ("MONIT", "ASSUM", "FLAG", "MISC", "KT")

"""
    heading_class(heading) -> Symbol

The role of a data heading: `:independent`, `:incident` or `:auxiliary`.

The Formats Manual makes a data heading an independent variable, a datum, or something
auxiliary to a datum: its uncertainty, a monitor, an assumed value, a flag, a resolution, a
normalisation, miscellaneous information explained in the BIB. Only the first kind can turn a
projection into an average. The datum and everything auxiliary to it are `:auxiliary` here; the
incident energy, `EN` and its variants, is `:incident`, since the window handles it. A heading
this table does not know is treated as an independent variable, which is the conservative
reading.

# Arguments
- `heading::AbstractString`: a data heading, as [`SubentryColumns`](@ref) holds it.

# Example

```julia
julia> heading_class("DATA-ERR"), heading_class("EN-DUMMY"), heading_class("TKE")
(:auxiliary, :incident, :independent)
```
"""
function heading_class(heading::AbstractString)
    h = strip(heading)
    occursin("DATA", h) && return :auxiliary
    occursin("ERR", h) && return :auxiliary
    if any(prefix -> startswith(h, prefix), _AUXILIARY_PREFIXES) ||
       endswith(h, "-FLAG") ||
       occursin("-RSL", h) ||
       occursin("-NRM", h) ||
       endswith(h, "-DIG")
        return :auxiliary
    end
    startswith(h, "EN") && return :incident
    return :independent
end

"""
For each abscissa quantity, the subentry headings that carry it, in order of preference, and
the pair of headings that carry it as a bin, of which the midpoint is taken.

The total kinetic energy is headed `TKE`, or `E` where the compiler defined `E` as the energy
of both fragments under `EN-SEC` (`14065004`, `21095008`, `(E,LF+HF)` and `(E,FF)`); the tag
rule of the joint abscissa already requires the reaction code to name TKE, so an `E` column
under that abscissa is the total kinetic energy and not a fragment-energy gate. Where both
headings are present `TKE` is taken and `E` counts as a variable of its own.
"""
const ABSCISSA_HEADINGS = Dict(
    "mass" => (["MASS"], ["MASS-MIN", "MASS-MAX"]),
    "product_mass" => (["MASS"], ["MASS-MIN", "MASS-MAX"]),
    "charge" => (["ELEM"], String[]),
    "neutron_energy" => (["E"], ["E-MIN", "E-MAX"]),
    "total_kinetic_energy" => (["TKE", "E"], ["TKE-MIN", "TKE-MAX"]),
)

"""
    abscissa_columns(data, quantity) -> (indices, binned)

The columns of `data` that carry the abscissa quantity `quantity`; see
[`ABSCISSA_HEADINGS`](@ref).

# Arguments
- `data::SubentryColumns`: the DATA table of one dataset.
- `quantity::AbstractString`: an abscissa quantity, `"mass"` or `"neutron_energy"`.

# Returns
`([index], false)` for the column carrying the value itself, else `([low, high], true)` for
the two columns of the bin pair when both are present, else `(Int[], false)`.
"""
function abscissa_columns(data::SubentryColumns, quantity::AbstractString)
    value_headings, bin_headings = ABSCISSA_HEADINGS[quantity]
    for heading in value_headings
        index = column(data, heading)
        index === nothing || return ([index], false)
    end
    if length(bin_headings) == 2
        low = column(data, bin_headings[1])
        high = column(data, bin_headings[2])
        (low === nothing || high === nothing) || return ([low, high], true)
    end
    return (Int[], false)
end

"""
    covered_headings(abscissa) -> Set{String}

Every heading of [`ABSCISSA_HEADINGS`](@ref) for the quantities of `abscissa`, the value
heading and both bin headings, together with `ISOMER` when the charge is among them: the isomer
is part of the product identification the charge abscissa resolves.
"""
function covered_headings(abscissa::AbstractVector{<:AbstractString})
    covered = Set{String}()
    for quantity in abscissa
        value_headings, bin_headings = ABSCISSA_HEADINGS[quantity]
        union!(covered, value_headings, bin_headings)
    end
    "charge" in abscissa && push!(covered, "ISOMER")
    return covered
end

"""
    varying_columns(data, abscissa) -> Vector{String}

The independent variables of a DATA table that `abscissa` does not cover and that take more
than one value, each as `"<heading> [<unit>] (<n> values)"`.

Projecting a dataset onto an abscissa asserts that nothing else varies. A variable held at one
value is a condition of the measurement and leaves the projection meaningful; one that varies
makes every abscissa value a family of rows, and no combination of them is the observable asked
for. Only headings [`heading_class`](@ref) calls `:independent` count, and
the incident energy is left to the window.

# Arguments
- `data::SubentryColumns`: the DATA table of one dataset, restricted to the retained rows.
- `abscissa::AbstractVector{<:AbstractString}`: the abscissa of the query.

# Example

```julia
julia> varying_columns(data, ["mass"])
1-element Vector{String}:
 "TKE [MEV] (200 values)"
```
"""
function varying_columns(data::SubentryColumns, abscissa::AbstractVector{<:AbstractString})
    covered = covered_headings(abscissa)
    varying = String[]
    for (heading, unit, values) in zip(data.headings, data.units, data.values)
        heading in covered && continue
        heading_class(heading) == :independent || continue
        count = length(unique(skipmissing(values)))
        count > 1 && push!(varying, "$(heading) [$(unit)] ($(count) values)")
    end
    return varying
end

"""
    restrict(columns, keep) -> SubentryColumns

The lines of `columns` that `keep` marks, with the same headings, units and pointers.

Throws a `DimensionMismatch` when `keep` does not have one entry per line.
"""
function restrict(columns::SubentryColumns, keep::AbstractVector{Bool})
    if !isempty(columns.values) && line_count(columns) != length(keep)
        throw(
            DimensionMismatch(
                "a mask of $(length(keep)) entries cannot select from a section of \
                 $(line_count(columns)) lines",
            ),
        )
    end
    return SubentryColumns(
        copy(columns.headings),
        copy(columns.units),
        copy(columns.pointers),
        Vector{Union{Missing, Float64}}[values[keep] for values in columns.values],
    )
end

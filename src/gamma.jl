# Prompt γ rays: what defines each measurement, and the readings its reaction code cannot give.
#
# A prompt-γ quantity is defined by the γ-energy range the photons were detected over, the time
# window after fission they were counted in, and the corrections made for what lies outside
# either. The total γ energy per fission differs between experiments by up to about 1 MeV on
# these definitions alone, so a value is not usable without them. They are read from the
# subentry where it states them, as a heading or in its text, else from the publication it
# cites, and recorded per dataset. Nothing is cut on them: a set over a narrow range is written
# beside a full-range one and flagged.

"""
The prompt-γ ordinates that are quantities per fission, tabulated against nothing or against a
property of the whole fission: the multiplicity, the total energy and the mean photon energy.
"""
const GAMMA_PER_FISSION_ORDINATES =
    ("gamma_multiplicity_per_fission", "gamma_energy_per_fission", "gamma_mean_energy")

"""
The abscissae each prompt-γ ordinate is retrieved against; the configuration validator refuses
every other pairing. An empty abscissa is a quantity per fission, written one row per dataset.
"""
const GAMMA_OBSERVABLES = Dict{String, Vector{Vector{String}}}(
    "gamma_multiplicity_per_fission" => [String[], ["mass"], ["total_kinetic_energy"]],
    "gamma_energy_per_fission" =>
        [String[], ["mass"], ["total_kinetic_energy"], ["neutron_number"]],
    "gamma_mean_energy" => [String[], ["mass"]],
    "gamma_multiplicity" => [["mass"]],
    "gamma_energy" => [["mass"]],
)

"""
What a definition of a prompt-γ measurement rests on, as the `_basis` keys of the run record: a
heading of the entry with its value (`entry`), the free text of the entry (`subentry text`), the
publication it cites (`publication`), or nothing (`unstated`).
"""
const DEFINITION_BASES = ("entry", "subentry text", "publication", "unstated")

"""
Kinds of time window: a gate that selects the photons counted as prompt, or the window within
which a photon had to arrive for the event to be recorded at all.
"""
const WINDOW_KINDS = ("prompt gate", "acquisition trigger")

"""
    GammaStatement

One statement defining a prompt-γ measurement that no heading of its entry carries: a γ-energy
range, a time window, a time resolution, or a correction.

# Fields
- `quantity::Symbol`: `:range`, `:window`, `:resolution` or `:correction`.
- `low::Float64`, `high::Float64`: the bounds, in MeV for a range and in ns for a window or a
  resolution; `NaN` for a bound the statement leaves open. A resolution is held in `high`.
- `kind::String`: for a window, one of [`WINDOW_KINDS`](@ref); empty otherwise.
- `basis::String`: `"subentry text"` or `"publication"`, of [`DEFINITION_BASES`](@ref).
- `evidence::String`: the words, verbatim. Those of the subentry are looked for in its text at
  every retrieval, and the place they are found is recorded with them.
- `location::String`: for a publication, its DOI and page; empty for the subentry, whose place is
  found.
"""
struct GammaStatement
    quantity::Symbol
    low::Float64
    high::Float64
    kind::String
    basis::String
    evidence::String
    location::String
    function GammaStatement(quantity, low, high, kind, basis, evidence, location)
        quantity in (:range, :window, :resolution, :correction) || throw(
            ArgumentError("statement quantity $(quantity) is not one this package reads"),
        )
        basis in ("subentry text", "publication") || throw(
            ArgumentError("statement basis \"$(basis)\" is not a text or a publication"),
        )
        quantity == :window &&
            !(kind in WINDOW_KINDS) &&
            throw(ArgumentError("window kind \"$(kind)\" is not one of $(WINDOW_KINDS)"))
        basis == "publication" &&
            isempty(location) &&
            throw(ArgumentError("a statement of a publication needs its DOI and page"))
        return new(quantity, low, high, kind, basis, evidence, location)
    end
end

gamma_range(low, high, evidence; publication = "") = GammaStatement(
    :range,
    low,
    high,
    "",
    isempty(publication) ? "subentry text" : "publication",
    evidence,
    publication,
)
gamma_window(low, high, kind, evidence; publication = "") = GammaStatement(
    :window,
    low,
    high,
    kind,
    isempty(publication) ? "subentry text" : "publication",
    evidence,
    publication,
)
gamma_resolution(value, evidence) =
    GammaStatement(:resolution, NaN, value, "", "subentry text", evidence, "")
gamma_correction(evidence) =
    GammaStatement(:correction, NaN, NaN, "", "subentry text", evidence, "")

const _PLEASONTON_1972 = "Pleasonton, Ferguson and Schmitt 1972, doi:10.1103/PhysRevC.6.1023, \
    p. 1023 (abstract)"

const _PLEASONTON_WINDOW = gamma_window(
    0.0,
    5.0,
    "prompt gate",
    "The average number and average energy of γ rays emitted within ∼5 nsec after fission",
    publication = _PLEASONTON_1972,
)

"""
Statements defining prompt-γ measurements that no heading of their entries carries, keyed by
entry (five characters), subentry (eight) or dataset identifier; a dataset takes those of all
three. A statement of the subentry text is looked for in it at every retrieval and its place
recorded; one the text no longer holds refuses the dataset until the statement is reviewed.

A window of the publication applies only to the measurement it describes: the abstract of
Pleasonton 1972 is that of the 235-U measurement, whose values 14214 gives (6.51 photons, 6.43 MeV
and 0.99 MeV per photon, the numbers of the abstract), and not that of the other systems of the
same report.
"""
const GAMMA_STATEMENTS = Dict{String, Vector{GammaStatement}}(
    "14214004" => [_PLEASONTON_WINDOW],
    "14214005" => [_PLEASONTON_WINDOW],
    "14214027" => [_PLEASONTON_WINDOW],
    "14197" => [_PLEASONTON_WINDOW],
    "14735" => [
        gamma_window(
            0.0,
            2000.0,
            "prompt gate",
            "these emitted within less than 2 microseconds of the fission process",
        ),
    ],
    "23197" => [
        gamma_resolution(1.5, "Time resolution < 1.5 nsec."),
        gamma_correction("Fitting detector response"),
    ],
    "23197009" => [gamma_range(0.1, NaN, "Energy range > 0.1 MeV .")],
    "23174004" => [
        gamma_correction(
            "Attenuation of gamma-rays in air was taken into account by extrapolating the \
             number of gamma-rays to zero distance.",
        ),
    ],
    "23283" => [
        gamma_correction(
            "The response function matrix was produced by performing a large series of \
             Geant4 simulations of monochromatic sources",
        ),
    ],
    "23417" => [
        gamma_correction(
            "The response matrix of the detection system for unfolding of the measured \
             spectra was determined by detailed GEANT4 simulations.",
        ),
    ],
    "23783" => [
        gamma_correction(
            "A deficit in the low-energy gamma rays was observed in the 252Cf benchmark \
             measurement.",
        ),
    ],
    "237830031" =>
        [gamma_correction("Data before applying correction factor of 1.30.")],
    "237830041" => [
        gamma_correction(
            "Average total gamma-ray energy before applying correction factor of 1.07.",
        ),
    ],
    "31729" => [
        gamma_correction(
            "correction for attenuation of gamma-rays in the material of the ionization \
             chamber and neutron-gamma overlap cause by a reduced timing resolution. This \
             correction amounted to values smaller than 0.32.",
        ),
    ],
    "317290074" => [
        gamma_correction(
            "Measured for 300 keV to 6 MeV, and renormalized to average for 100 keV to 6 MeV",
        ),
    ],
    "317290094" => [
        gamma_correction(
            "Measured for 300 keV to 6 MeV, and renormalized to average for 100 keV to 6 MeV",
        ),
    ],
    "317290075" => [
        gamma_correction(
            "Measured for 500 keV to 6 MeV, and renormalized to average for 100 keV to 6 MeV",
        ),
    ],
    "317290095" => [
        gamma_correction(
            "Measured for 500 keV to 6 MeV, and renormalized to average for 100 keV to 6 MeV",
        ),
    ],
    "31778" => [
        gamma_window(
            0.0,
            300.0,
            "acquisition trigger",
            "The system was triggered whenever a gamma ray was detected within a window of \
             300 ns following the fission trigger.",
        ),
        gamma_correction("The detectors response functions simulated with GEANT4."),
    ],
    "32788" => [
        gamma_range(
            NaN,
            NaN,
            "The contributions of extrapolation of the gamma -ray pulse height spectrum below \
             the discrimination level is around 0.8%.",
        ),
    ],
    "41580" => [
        gamma_range(
            0.32,
            5.12,
            "Gamma-quanta were registered in energy range of 320 - 5120 keV during 4 microsec \
             after FF registration.",
        ),
        gamma_window(
            0.0,
            4000.0,
            "prompt gate",
            "Gamma-quanta were registered in energy range of 320 - 5120 keV during 4 microsec \
             after FF registration.",
        ),
    ],
)

"""
    gamma_statements(identifier) -> Vector{GammaStatement}

The statements of [`GAMMA_STATEMENTS`](@ref) for a dataset: those of its entry, its subentry and
itself, in that order.
"""
function gamma_statements(identifier::AbstractString)
    keys = unique([first(identifier, 5), first(identifier, 8), String(identifier)])
    return reduce(vcat, (get(GAMMA_STATEMENTS, key, GammaStatement[]) for key in keys))
end

# The BIB of a subentry text as blocks: subentry, keyword, pointer and the text, whitespace
# collapsed. A line whose keyword field is blank continues the block above it, unless it opens
# a new pointer.
struct BibBlock
    subentry::String
    keyword::String
    pointer::Char
    text::String
end

_collapse(text::AbstractString) = strip(replace(text, r"\s+" => " "))

function bib_blocks(text::AbstractString)
    blocks = BibBlock[]
    subentry = ""
    inside = false
    keyword = ""
    pointer = ' '
    buffer = String[]
    flush!() = (
        isempty(buffer) || push!(
            blocks,
            BibBlock(subentry, keyword, pointer, _collapse(join(buffer, ' '))),
        );
        empty!(buffer)
    )
    for raw in eachline(IOBuffer(String(text)))
        line = rpad(first(raw, 66), 66)
        label = strip(line[1:10])
        if label == "SUBENT"
            subentry = strip(split(raw)[2])
            continue
        elseif label == "BIB"
            inside = true
            continue
        elseif label == "ENDBIB"
            flush!()
            inside = false
            continue
        end
        inside || continue
        marker = line[11]
        if !isempty(label)
            flush!()
            keyword = label
            pointer = marker
        elseif marker != ' '
            flush!()
            pointer = marker
        end
        push!(buffer, line[12:end])
    end
    flush!()
    return blocks
end

"""
    locate_statement(text, evidence) -> Union{String,Nothing}

Where in the subentry text `text` the words `evidence` stand, as `"subentry 41580001,
DETECTOR"`; `nothing` when they stand nowhere. Line breaks and indentation are ignored.
"""
function locate_statement(text::AbstractString, evidence::AbstractString)
    wanted = _collapse(evidence)
    for block in bib_blocks(text)
        occursin(wanted, block.text) || continue
        return "subentry $(block.subentry), $(block.keyword)"
    end
    return nothing
end

# The text of the code of one reaction and the words written after it: the parenthesised code
# up to its matching parenthesis, and the rest.
function _split_reaction(text::AbstractString)
    start = findfirst('(', text)
    start === nothing && return ("", String(text))
    depth = 0
    for i in eachindex(text)
        i < start && continue
        c = text[i]
        c == '(' && (depth += 1)
        c == ')' && (depth -= 1)
        depth == 0 && return (text[start:i], strip(text[nextind(text, i):end]))
    end
    return (text[start:end], "")
end

"""
    reaction_text(text, identifier) -> String

The words the compiler wrote after the reaction code of `identifier` under REACTION, whitespace
collapsed; empty when there are none. A dataset with a pointer takes the reaction of its pointer.
"""
function reaction_text(text::AbstractString, identifier::AbstractString)
    subentry = first(identifier, 8)
    pointer = length(identifier) == 9 ? last(identifier) : ' '
    for block in bib_blocks(text)
        block.subentry == subentry && block.keyword == "REACTION" || continue
        block.pointer == pointer || continue
        return String(last(_split_reaction(block.text)))
    end
    return ""
end

"""
    bib_text(text, subentry, keyword) -> String

The text of one keyword of the BIB of `subentry`, its pointers joined, whitespace collapsed;
empty when the subentry has none.
"""
function bib_text(text::AbstractString, subentry::AbstractString, keyword::AbstractString)
    parts = [
        block.text for block in bib_blocks(text) if
        block.subentry == subentry && block.keyword == keyword
    ]
    return join(parts, " ")
end

"""
The interval, in MeV, of a mean photon energy: the prompt fission γ rays of the actinides
average 0.8 to 1.0 MeV per photon over their full range and up to about 1.8 MeV over a range
that starts at 1 MeV (Makii 2019, 23541005).
"""
const MEAN_PHOTON_ENERGY_INTERVAL = (0.3, 2.5)

"""
The interval, in MeV, of a total prompt γ energy per fission: 6 to 9 MeV for the actinides over
a full range, 4 MeV over 1 to 6 MeV (Makii 2019).
"""
const TOTAL_GAMMA_ENERGY_INTERVAL = (3.0, 15.0)

"""What a prompt-γ energy coded `KE` is read as, as `quantity_reading` of the run record."""
const GAMMA_ENERGY_READINGS = ("total_energy_per_fission", "mean_photon_energy")

"""
    QuantityReading(reading, basis, evidence)

What a prompt-γ energy coded `KE` holds, and what establishes it.

# Fields
- `reading::String`: one of [`GAMMA_ENERGY_READINGS`](@ref).
- `basis::String`: `"REACTION text"`, `"publication"` or `"magnitude"`.
- `evidence::String`: the words of the REACTION, or the values and the interval they lie in.
"""
struct QuantityReading
    reading::String
    basis::String
    evidence::String
end

const _TOTAL_WORDS = r"(?i)\btotal\b"
const _MEAN_WORDS =
    r"(?i)\b(per|of one|of single|of a single) (gamma|photon)\b|\bsingle gamma\b|\baverage (gamma|photon)(-ray)?s? energy\b"

"""
    gamma_energy_reading(text, values) -> Union{QuantityReading,String}

Whether the prompt-γ energies `values`, in MeV, coded `KE`, are the total energy per fission or
the mean photon energy, or the reason they cannot be told.

The magnitude decides, the two intervals [`TOTAL_GAMMA_ENERGY_INTERVAL`](@ref) and
[`MEAN_PHOTON_ENERGY_INTERVAL`](@ref) being disjoint. The REACTION text `text` is the basis
where it names the quantity — "total", or an energy per gamma, per photon or of one gamma — and
agrees with the magnitude; a text that names the other quantity refuses the dataset, and a
reading on magnitude alone is recorded as such.
"""
function gamma_energy_reading(text::AbstractString, values::AbstractVector{<:Real})
    isempty(values) && return "no value to read"
    within(interval) = all(v -> interval[1] ≤ v ≤ interval[2], values)
    magnitude = if within(TOTAL_GAMMA_ENERGY_INTERVAL)
        "total_energy_per_fission"
    elseif within(MEAN_PHOTON_ENERGY_INTERVAL)
        "mean_photon_energy"
    else
        return "the values, $(round(minimum(values); sigdigits = 3)) to \
                $(round(maximum(values); sigdigits = 3)) MeV, lie in neither the interval of a \
                total prompt γ energy per fission, $(TOTAL_GAMMA_ENERGY_INTERVAL[1]) to \
                $(TOTAL_GAMMA_ENERGY_INTERVAL[2]) MeV, nor that of a mean photon energy, \
                $(MEAN_PHOTON_ENERGY_INTERVAL[1]) to $(MEAN_PHOTON_ENERGY_INTERVAL[2]) MeV"
    end
    total, mean = occursin(_TOTAL_WORDS, text), occursin(_MEAN_WORDS, text)
    stated =
        total == mean ? nothing : total ? "total_energy_per_fission" : "mean_photon_energy"
    if stated === nothing
        interval =
            magnitude == "total_energy_per_fission" ? TOTAL_GAMMA_ENERGY_INTERVAL :
            MEAN_PHOTON_ENERGY_INTERVAL
        return QuantityReading(
            magnitude,
            "magnitude",
            "the values, $(round(minimum(values); sigdigits = 3)) to \
             $(round(maximum(values); sigdigits = 3)) MeV, lie in $(interval[1]) to \
             $(interval[2]) MeV" * (
                isempty(text) ? "; the REACTION carries no text" :
                "; the REACTION text \"$(text)\" names neither"
            ),
        )
    end
    stated == magnitude || return "the REACTION text \"$(text)\" names the \
        $(replace(stated, '_' => ' ')), but the values, $(round(minimum(values); sigdigits = 3)) \
        to $(round(maximum(values); sigdigits = 3)) MeV, are a $(replace(magnitude, '_' => ' '))"
    return QuantityReading(stated, "REACTION text", text)
end

"""
Prompt-γ datasets refused whatever they are asked as, keyed by entry, subentry or dataset
identifier, with the reason: K X-rays and discrete lines coded as γ rays, delayed γ rays, the γ
field of a source without fission coincidence, and sets the survey of 2026-10-14 found to be no
measurement of the prompt γ rays of thermal or spontaneous fission. The archive codes all of
them `0-G-0` or `G`.
"""
const GAMMA_REFUSALS = Dict{String, String}(
    "33071" => "K X-rays, not γ rays: the subentries give the mean energy and the multiplicity \
        of the K X-rays of the light and heavy fragments (Kapoor 1968)",
    "33072" => "K X-rays, not γ rays: the multiplicity of the K X-rays of the light and heavy \
        fission fragments (Kapoor 1969)",
    "41699" => "U K-alpha X-rays of the fissioning atom, not prompt γ rays (Popeko 1975)",
    "41733" => "K-alpha1 X-rays registered at neutron resonances, not prompt γ rays \
        (Dlouhy 1980)",
    "41698" => "K X-ray spectra of the heavy fragments, not prompt γ rays (Donichkin 1973)",
    "12691" => "intensities of discrete 2+ to 0+ transitions of individual products, not the \
        prompt γ emission of the fission (Cheifetz 1971)",
    "30418" => "intensities of discrete transitions of individual products (Ajitanand 1975)",
    "14479" => "discrete isomeric transitions of fragments stopped in a detector (John 1970)",
    "40966" => "discrete lines of individual products at 3 MeV incident energy, without \
        fission coincidence (Filatenkov 1988)",
    "41723" => "discrete lines of individual products at resonance energies (Bogdzel 1987)",
    "20135" => "discrete lines at the 8.79 eV resonance, some from microsecond isomers \
        (Weigmann 1969)",
    "22958" => "discrete lines of the 1.9 µs isomer of Zr-98, delayed (Simpson 2006)",
    "30225" => "delayed γ rays of the β decay of bromine fission products (Cojocaru 1966)",
    "23174002" => "the time distribution of γ rays after fission, prompt and delayed, in \
        arbitrary units (Skarsvag 1970)",
    "23174003" => "the time distribution of γ rays after fission, prompt and delayed, fitted, \
        in arbitrary units (Skarsvag 1970)",
    "23857005" => "the γ multiplicity of ternary fission, which only MSC and the REACTION text \
        mark (Singer 1997)",
    "41582" => "the γ field of 252-Cf neutron sources measured without fission coincidence \
        (Kolevatov 1979)",
    "41507" => "an upper limit on the bremsstrahlung of fission fragments, 36 to 90 MeV \
        (Varlachev 2007)",
)

"""
Datasets of 14214 (Pleasonton, ORNL-4844, Table 1) that give the multiplicity or the energy of
the prompt γ rays of one fragment group, light or heavy: kept in the record of the dataset
refused, with the value, and not written as tables (ruling of 2026-10-14).
"""
const GAMMA_FRAGMENT_GROUPS = Dict{String, String}(
    "14214010" => "light",
    "14214011" => "light",
    "14214012" => "heavy",
    "14214013" => "heavy",
    "14214014" => "light",
    "14214015" => "light",
    "14214016" => "heavy",
    "14214017" => "heavy",
    "14214018" => "light",
    "14214019" => "light",
    "14214020" => "heavy",
    "14214021" => "heavy",
    "14214022" => "light",
    "14214023" => "light",
    "14214024" => "heavy",
    "14214025" => "heavy",
)

"""
    gamma_refusal(identifier, code, value, uncertainty, kind) -> Union{String,Nothing}

The reason a dataset coded for prompt γ rays is refused by curation whatever it is asked as, or
`nothing`: one of [`GAMMA_REFUSALS`](@ref), or a fragment-group value of
[`GAMMA_FRAGMENT_GROUPS`](@ref), stated with its value as the rendering gives it.
"""
function gamma_refusal(identifier::AbstractString, code, value, uncertainty, kind)
    for key in unique([first(identifier, 5), first(identifier, 8), String(identifier)])
        reason = get(GAMMA_REFUSALS, key, nothing)
        reason === nothing || return reason
    end
    group = get(GAMMA_FRAGMENT_GROUPS, String(identifier), nothing)
    group === nothing && return nothing
    quantity = has_code(code, "SF6:KE") ? "energy" : "multiplicity"
    stated = ismissing(uncertainty) ? string(value) : "$(value) ± $(uncertainty)"
    return "the prompt γ $(quantity) of the $(group) fragment group, $(stated) \
            $(String(kind)), as the subentry gives it: a group value, kept in this record and \
            not written as a table"
end

"""
    structured_range(subentry, data) -> Union{Tuple{Float64,Float64,String},Nothing}

The γ-energy range a heading of the entry states, in MeV, with the headings read: `E-MIN` and
`E-MAX` of the DATA table where each holds one value, else of a COMMON section; a bound the
headings leave open is `NaN`. `nothing` when no heading states either bound.
"""
function structured_range(subentry::Subentry, data::SubentryColumns)
    bounds = Dict{String, Tuple{Float64, String}}()
    for heading in ("E-MIN", "E-MAX")
        index = column(data, heading)
        if index !== nothing
            values = unique(skipmissing(data.values[index]))
            length(values) == 1 && (bounds[heading] = (only(values), data.units[index]))
        end
        haskey(bounds, heading) && continue
        constant = common_constant(subentry, heading)
        constant === nothing || (bounds[heading] = constant)
    end
    isempty(bounds) && return nothing
    mev(heading) =
        haskey(bounds, heading) ?
        first(bounds[heading]) * something(energy_factor(last(bounds[heading])), NaN) : NaN
    evidence = join(
        [
            "$(heading) $(first(bounds[heading])) $(last(bounds[heading]))" for
            heading in ("E-MIN", "E-MAX") if haskey(bounds, heading)
        ],
        ", ",
    )
    return (mev("E-MIN"), mev("E-MAX"), evidence)
end

"""
    incident_energy_basis(subentry, data, energies) -> String

How the incident energy of a dataset of induced fission was established: the energy the csv
rendering gives, in MeV, and the heading of the subentry it comes from, with its value, unit and
section. The listings of the archive carry no energy window, so the record says what put the
dataset inside the thermal one.
"""
function incident_energy_basis(subentry::Subentry, data::SubentryColumns, energies)
    stated =
        isempty(energies) ? "no incident energy" :
        "the incident energy $(join(energies, ", ")) MeV of the csv rendering"
    sources = String[]
    for (section, place) in (
        (data, "DATA"),
        (subentry.common, "COMMON of subentry $(first(subentry.identifier, 8))"),
        (subentry.entry_common, "COMMON of subentry $(first(subentry.identifier, 5))001"),
    )
        for (heading, unit, values) in zip(section.headings, section.units, section.values)
            (startswith(heading, "EN") || startswith(heading, "KT")) || continue
            present = unique(skipmissing(values))
            isempty(present) && continue
            push!(sources, "$(heading) $(join(present, ", ")) $(unit) ($(place))")
        end
    end
    isempty(sources) && return "$(stated); the subentry heads no incident energy"
    return "$(stated), from $(join(sources, "; "))"
end

"""
    gamma_definition(identifier, code, range, text) -> Union{Dict{String,Any},String}

The definition of a prompt-γ measurement, as the keys of its run record: the γ-energy range,
the time window and the time resolution, each with its basis and evidence; the corrections
stated; whether the archive codes the set as partial (`PAR`). The range is that of the
headings of the entry, `range`, where they state one ([`structured_range`](@ref)), else that of the statements of
[`GAMMA_STATEMENTS`](@ref), which also give the window, the resolution and the corrections. The
CORRECTION text of the entry and of the subentry is recorded as it stands.

Returns the reason the dataset is refused where a statement of the subentry text is no longer
found in it.
"""
function gamma_definition(
    identifier::AbstractString,
    code::AbstractString,
    range::Union{Nothing, Tuple{Float64, Float64, String}},
    text::AbstractString,
)
    record = Dict{String, Any}()
    statements = gamma_statements(identifier)
    located = String[]
    for statement in statements
        if statement.basis == "subentry text"
            place = locate_statement(text, statement.evidence)
            place === nothing &&
                return "the curated statement \"$(statement.evidence)\" is no \
                longer in the subentry text; the statement must be reviewed"
            push!(located, place)
        else
            push!(located, statement.location)
        end
    end
    described(i) = "\"$(statements[i].evidence)\" ($(located[i]))"
    of(kind) = findfirst(s -> s.quantity == kind, statements)

    stated = of(:range)
    if range !== nothing
        isnan(range[1]) || (record["gamma_energy_min_mev"] = range[1])
        isnan(range[2]) || (record["gamma_energy_max_mev"] = range[2])
        record["gamma_energy_range_basis"] = "entry"
        record["gamma_energy_range_evidence"] = range[3]
    elseif stated !== nothing
        statement = statements[stated]
        isnan(statement.low) || (record["gamma_energy_min_mev"] = statement.low)
        isnan(statement.high) || (record["gamma_energy_max_mev"] = statement.high)
        record["gamma_energy_range_basis"] = statement.basis
        record["gamma_energy_range_evidence"] = described(stated)
    else
        record["gamma_energy_range_basis"] = "unstated"
    end

    window = of(:window)
    if window === nothing
        record["time_window_basis"] = "unstated"
    else
        statement = statements[window]
        record["time_window_ns"] = [statement.low, statement.high]
        record["time_window_kind"] = statement.kind
        record["time_window_basis"] = statement.basis
        record["time_window_evidence"] = described(window)
    end
    resolution = of(:resolution)
    if resolution !== nothing
        record["time_resolution_ns"] = statements[resolution].high
        record["time_resolution_evidence"] = described(resolution)
    end

    corrections = String[
        described(i) for i in eachindex(statements) if statements[i].quantity == :correction
    ]
    for subentry_identifier in (first(identifier, 5) * "001", first(identifier, 8))
        stated_text = bib_text(text, subentry_identifier, "CORRECTION")
        isempty(stated_text) || push!(
            corrections,
            "\"$(stated_text)\" (subentry $(subentry_identifier), CORRECTION)",
        )
    end
    record["corrections_stated"] = unique(corrections)
    record["gamma_range_partial"] = has_code(code, "SF5:PAR")
    return record
end

"""
    gamma_definition_unstated(record) -> Vector{String}

What the definition in `record` leaves unstated, `"range"` and `"window"`; a range stated in
words without a value counts as unstated.
"""
function gamma_definition_unstated(record::AbstractDict)
    unstated = String[]
    haskey(record, "gamma_energy_min_mev") ||
        haskey(record, "gamma_energy_max_mev") ||
        push!(unstated, "range")
    haskey(record, "time_window_ns") || push!(unstated, "window")
    return unstated
end

"""The Boltzmann constant in eV per kelvin (CODATA 2018, exact)."""
const BOLTZMANN_EV_PER_K = 8.617333262e-5

"""
Incident energies the csv rendering misstates, keyed by entry, as the energy in eV that replaces
the rendering's before the incident-energy window is applied, and the evidence. Entry 31729
(Oberstedt 2013) states the temperature of a cold neutron beam, `KT-K` 100 K in the COMMON
section of subentry 31729001 beside INC-SPECT 'Cold neutron beam', and the rendering gives that
number as an incident energy of 100 eV; the beam's kT is 8.6 meV.
"""
const INCIDENT_ENERGY_READINGS = Dict{String, Tuple{Float64, String}}(
    "31729" => (
        BOLTZMANN_EV_PER_K * 100.0,
        "the entry states the temperature of a cold neutron beam, KT-K 100 K (COMMON of \
         subentry 31729001; INC-SPECT 'Cold neutron beam'), which the csv rendering gives as \
         an incident energy of 100 eV; read as kT = 8.6e-3 eV",
    ),
)

"""
    incident_energy_reading(identifier) -> Union{Tuple{Float64,String},Nothing}

The incident energy in eV, and its evidence, that replaces the rendering's for `identifier`; see
[`INCIDENT_ENERGY_READINGS`](@ref).
"""
incident_energy_reading(identifier::AbstractString) =
    get(INCIDENT_ENERGY_READINGS, first(identifier, 5), nothing)

"""
    StatedValue

A prompt-γ value its entry states with its uncertainty outside any DATA table — in the
additional results (ADD-RES) of a subentry — read as a dataset of its own (ruling of
2026-10-14). The words are looked for in the subentry text at every retrieval, and both numbers
must stand in them; nothing is formed from other quantities.

# Fields
- `source::String`: the subentry stating the value, eight characters; the dataset's identifier.
- `target_Z::Int`, `target_A::Int`, `channel::String`: the fissioning system.
- `ordinate::String`: the ordinate the value is, of [`GAMMA_PER_FISSION_ORDINATES`](@ref).
- `value::Float64`, `uncertainty::Float64`: in `unit`.
- `unit::String`: the unit token, `"MEV"`.
- `evidence::String`: the words stating the value, verbatim.
- `author::String`, `year::Int`: the first author and the year of the entry.
- `incident_energy_ev::Float64`: the incident energy of the measurement, eV; `NaN` for
  spontaneous fission.
- `incident_evidence::String`: what the entry states of it.
- `range::Union{Nothing,Tuple{Float64,Float64,String}}`: the γ-energy range a heading of the
  entry states for the same measurement, in MeV, with the headings read.
- `partial::Bool`: whether the archive codes the measurement partial (`PAR`).
- `reason::String`: what the value is, for the record.
"""
struct StatedValue
    source::String
    target_Z::Int
    target_A::Int
    channel::String
    ordinate::String
    value::Float64
    uncertainty::Float64
    unit::String
    evidence::String
    author::String
    year::Int
    incident_energy_ev::Float64
    incident_evidence::String
    range::Union{Nothing, Tuple{Float64, Float64, String}}
    partial::Bool
    reason::String
end

const _GATERA_RANGE = (
    0.1,
    7.0,
    "E-MIN 0.1 MEV, E-MAX 7.0 MEV in the COMMON sections of subentries 31778006 to 31778009, \
     the multiplicities and mean energies of the same spectra",
)

const _GATERA_INCIDENT = "EN 0.0253 EV (COMMON of subentry 31778001)"

_gatera(source, value, uncertainty, detector) = StatedValue(
    source,
    94,
    239,
    "nth",
    "gamma_energy_per_fission",
    value,
    uncertainty,
    "MEV",
    "Total gamma energy $(value) +/- $(rpad(string(uncertainty), 4, '0')) MeV",
    "A.Gatera",
    2017,
    0.0253,
    _GATERA_INCIDENT,
    _GATERA_RANGE,
    true,
    "the total prompt γ energy per fission of $(detector), stated with its uncertainty in \
     the ADD-RES of its unfolded spectrum; the multiplicities and mean energies of 31778006 to \
     31778009 are of the same spectra (Gatera 2017, doi:10.1103/PhysRevC.95.064609)",
)

"""
Values of [`StatedValue`](@ref) the survey of 2026-10-14 found: the total prompt γ energy per
fission of Oberstedt 2013 (235-U), Gatera 2017 (239-Pu, three detectors and their summed
spectrum) and Makii 2019 (235-U, over 1 to 6 MeV), which their entries state in ADD-RES and in no
DATA table.
"""
const STATED_VALUES = StatedValue[
    StatedValue(
        "31729001",
        92,
        235,
        "nth",
        "gamma_energy_per_fission",
        6.92,
        0.09,
        "MEV",
        "Total gamma energy 6.92 +/- 0.09 MeV (average for #Q489, #Q491, #315)",
        "A.Oberstedt",
        2013,
        BOLTZMANN_EV_PER_K * 100.0,
        "KT-K 100 K (COMMON of subentry 31729001), a cold neutron beam ('Cold neutron \
         beam', INC-SPECT); kT = 8.6e-3 eV",
        (
            0.1,
            6.0,
            "E-MIN 0.1 MEV, E-MAX 6.0 MEV in the COMMON sections of subentries 31729007 and \
             31729009, the multiplicities and mean energies of the three detectors averaged",
        ),
        true,
        "the total prompt γ energy per fission, the average of the three detectors whose \
         multiplicities and mean energies 31729008 and 31729010 average, stated with its \
         uncertainty in the ADD-RES of the entry (Oberstedt 2013, \
         doi:10.1103/PhysRevC.87.051602)",
    ),
    _gatera("31778002", 6.18, 0.10, "the LaBr3:Ce detector (Q489)"),
    _gatera("31778003", 6.17, 0.09, "the LaBr3:Ce detector (5414)"),
    _gatera("31778004", 6.42, 0.10, "the LaBr3:Ce detector (5415)"),
    _gatera("31778005", 6.27, 0.11, "the spectrum summed over the three detectors"),
    StatedValue(
        "23541005",
        92,
        235,
        "nth",
        "gamma_energy_per_fission",
        4.07,
        0.07,
        "MEV",
        "Average total gamma energy 4.07 +- 0.07 MeV",
        "H.Makii",
        2019,
        5.0e-3,
        "EN-DUMMY 5 MILLI-EV (COMMON of subentry 23541001), a cold neutron beam",
        (1.0, 6.0, "E-MIN 1.0 MEV, E-MAX 6.0 MEV in the DATA table of subentry 23541005"),
        true,
        "the total prompt γ energy per fission over 1 to 6 MeV, stated with its uncertainty \
         in the ADD-RES of the subentry of the multiplicity and the mean energy over the same \
         range (Makii 2019, doi:10.1103/PhysRevC.100.044610)",
    ),
]

"""
    stated_values(query) -> Vector{StatedValue}

The values of [`STATED_VALUES`](@ref) that answer `query`: of its system and ordinate, per
fission.
"""
stated_values(query) = [
    value for
    value in STATED_VALUES if (value.target_Z, value.target_A, value.channel) ==
    (query.target_Z, query.target_A, query.channel) &&
        value.ordinate == query.ordinate &&
        isempty(query.abscissa)
]

"""
Datasets listed under another quantity than their ordinate's, admitted by name, keyed by ordinate
and abscissa: Skarsvag 1970 (23174004), the prompt γ multiplicity per fission above 100 keV, which
the archive lists under `MLT` alone (ruling of 2026-10-14). Nothing else under that quantity
comes in this way.
"""
const NAMED_LISTINGS = Dict{Tuple{String, Vector{String}}, Tuple{String, Vector{String}}}(
    ("gamma_multiplicity_per_fission", String[]) => ("MLT", ["23174004"]),
)

"""
    named_listing(query) -> Union{Tuple{String,Vector{String}},Nothing}

The quantity and the datasets of [`NAMED_LISTINGS`](@ref) for the observable of `query`.
"""
named_listing(query) = get(NAMED_LISTINGS, (query.ordinate, query.abscissa), nothing)

"""
    UnadmittedValue

A value an entry states in an auxiliary column of a DATA table, with no uncertainty column beside
it, which the ruling of 2026-10-14 does not admit as a dataset: kept, with its words and its
place, among the reasons of the rejections of the observable it would answer.

# Fields
- `identifier::String`: the dataset whose subentry holds the column.
- `target_Z::Int`, `target_A::Int`, `channel::String`, `ordinate::String`: the observable.
- `heading::String`, `value::Float64`, `unit::String`: the column, the value and its unit.
- `definition::String`: the words of `MISC-COL` defining the column, verbatim.
"""
struct UnadmittedValue
    identifier::String
    target_Z::Int
    target_A::Int
    channel::String
    ordinate::String
    heading::String
    value::Float64
    unit::String
    definition::String
end

"""
Values of [`UnadmittedValue`](@ref): the total prompt γ energy per fission of Smith 1956 and Sokol
1991 and the mean photon energy of Krupa 2004, each in a MISC column of a dataset written for
another quantity.
"""
const UNADMITTED_VALUES = UnadmittedValue[
    UnadmittedValue(
        "14320004",
        98,
        252,
        "sf",
        "gamma_energy_per_fission",
        "MISC",
        8.2,
        "MEV",
        "Total energy loss in photons from Table 2.",
    ),
    UnadmittedValue(
        "415800031",
        98,
        252,
        "sf",
        "gamma_energy_per_fission",
        "MISC",
        9.6,
        "MEV",
        "Average energy per fission <E-tot>",
    ),
    UnadmittedValue(
        "23814004",
        98,
        252,
        "sf",
        "gamma_mean_energy",
        "MISC1",
        0.83,
        "MEV",
        "Average energy per one gamma.",
    ),
]

"""
    unadmitted_values(query) -> Vector{UnadmittedValue}

The values of [`UNADMITTED_VALUES`](@ref) that would answer `query`, a quantity per fission.
"""
unadmitted_values(query) = [
    value for
    value in UNADMITTED_VALUES if (value.target_Z, value.target_A, value.channel) ==
    (query.target_Z, query.target_A, query.channel) &&
        value.ordinate == query.ordinate &&
        isempty(query.abscissa)
]

"""
    unadmitted_note(value, text) -> String

The reason recorded for an [`UnadmittedValue`](@ref), read from the subentry text `text`: the
value as its column holds it and the words defining the column, with their place; or why the
reading must be reviewed, where the column or the words are no longer there.
"""
function unadmitted_note(value::UnadmittedValue, text::AbstractString)
    subentry = try
        parse_subentry(text, value.identifier)
    catch exception
        exception isa SubentryError || rethrow()
        return "the subentry of $(value.identifier) cannot be read: $(exception.msg)"
    end
    index = column(subentry.data, value.heading)
    held =
        index !== nothing && any(
            v -> !ismissing(v) && isapprox(v, value.value; rtol = 1.0e-9),
            subentry.data.values[index],
        )
    place = locate_statement(text, value.definition)
    (held && place !== nothing) || return "the curated reading of $(value.value) \
        $(value.unit) in column $(value.heading) of $(value.identifier) no longer matches the \
        subentry; the reading must be reviewed"
    return "$(value.identifier) states $(value.value) $(value.unit) in its column \
            $(value.heading), \"$(value.definition)\" ($(place)), with no uncertainty column \
            beside it: no dataset under the ruling on values outside the DATA column, kept here"
end

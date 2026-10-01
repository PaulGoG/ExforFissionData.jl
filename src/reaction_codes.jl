# The reaction-code grammar.
#
# EXFOR identifies what a dataset measures with a reaction code such as
#
#     92-U-233(N,F)ELEM/MASS,CUM,FY
#
# whose comma-separated subfields name the product (SF4), the branch (SF5), the parameter (SF6),
# the particle considered (SF7), the modifiers (SF8) and the data type (SF9), each holding one or
# more codes joined by `/` (EXFOR Formats Manual, IAEA-NDS-207, chapter 6). A code is read into
# those subfields and every test compares whole codes in a named subfield: `DE` is the energy
# differential of SF6 and never a part of `DERIV`, `KE` never a part of `KEP`. The vocabulary is
# still applied inconsistently across entries, so which codes each observable requires and
# forbids is empirical: the tables below encode observed failures of the upstream labelling, each
# annotated with what it catches, and a rule that looks redundant usually guards a real entry.

"""
    reaction_fields(code) -> Union{Vector{Vector{String}},Nothing}

The codes of subfields SF4 to SF9 of a single EXFOR reaction, one vector per subfield in that
order, each subfield split at its `/` separators; `nothing` when `code` is a combination of
several reactions — a ratio, sum, difference or product, written in parentheses — or is not a
reaction code at all.

Parenthesised codes keep their parentheses: `(SEC)`, "compiler uncertain if secondary", is a
code of its own and not `SEC`.

# Example

```jldoctest
julia> ExforFissionData.reaction_fields("92-U-235(N,F)ELEM/MASS,IND,FY,,FIS")
6-element Vector{Vector{String}}:
 ["ELEM", "MASS"]
 ["IND"]
 ["FY"]
 []
 ["FIS"]
 []
```
"""
function reaction_fields(code::AbstractString)
    text = strip(String(code))
    startswith(text, "(") && return nothing
    parsed = match(r"^[^()]+\([^()]*\)([^()]*(?:\([^()]*\)[^()]*)*)$", text)
    parsed === nothing && return nothing
    subfields = split(something(parsed.captures[1], ""), ',')
    length(subfields) > 6 && return nothing
    fields = [String[] for _ in 4:9]
    for (k, subfield) in enumerate(subfields)
        fields[k] = String[c for c in split(subfield, '/') if !isempty(c)]
    end
    return fields
end

"""
Codes that a tag of the key's form also accepts: `AKE`, average kinetic energy, is the coding of
the same mean that the archive used before `KE` replaced it in SF6 (the histories of 21995010,
22650013, 40112013 and many more record the change). `KEP`, the most probable kinetic energy,
and `KEM`, the temperature of a Maxwellian (Dictionary 32), are not synonyms.
"""
const CODE_SYNONYMS = Dict("SF6:KE" => ("KE", "AKE"))

# The subfield a tag names, 4 to 9, or 0 for any subfield, and the code: `SF5:PRE` is (5, "PRE").
function _locate(tag::AbstractString)
    if ncodeunits(tag) > 4 && startswith(tag, "SF") && tag[4] == ':' && tag[3] in '4':'9'
        return (tag[3] - '0', String(tag[5:end]))
    end
    return (0, String(tag))
end

# Whether the subfields `fields` hold the code a tag names. A tag is `SFn:CODE`, a code in
# subfield n, or a bare `CODE` in any subfield; tags joined by ` & ` must all hold.
function _holds(tag::AbstractString, fields::Vector{Vector{String}})
    for part in split(tag, " & ")
        subfield, code = _locate(part)
        if subfield == 0
            any(field -> code in field, fields) || return false
        else
            accepted = get(CODE_SYNONYMS, part, (code,))
            any(in(fields[subfield - 3]), accepted) || return false
        end
    end
    return true
end

# A tag as a reason reads it: `"PRE" in SF5`.
function _describe(tag::AbstractString)
    parts = map(split(tag, " & ")) do part
        subfield, code = _locate(part)
        subfield == 0 ? "\"$(code)\"" : "\"$(code)\" in SF$(subfield)"
    end
    return join(parts, " with ")
end

"""
    has_code(code, tag) -> Bool

Whether the reaction code `code` holds the code a tag names — `"SF8:MSC"` for `MSC` among the
modifiers, `"TKE"` for `TKE` in any subfield; false for a combination of reactions.
"""
function has_code(code::AbstractString, tag::AbstractString)
    fields = reaction_fields(code)
    return fields !== nothing && _holds(tag, fields)
end

"""
    TagRule(require_all, require_any, forbid)

A test over the subfields of an EXFOR reaction code, by whole codes.

A code matches when it is a single reaction whose subfields hold every tag of `require_all`, at
least one tag of `require_any` (when that list is non-empty), and none of `forbid`. A tag is
`SFn:CODE` for a code in subfield n, or a bare `CODE` for one in any subfield; tags joined by
` & ` must all hold. [`CODE_SYNONYMS`](@ref) lists the codes a tag also accepts.

# Fields
- `require_all::Vector{String}`: tags that must all hold.
- `require_any::Vector{String}`: tags of which at least one must hold; an empty list imposes no
  constraint.
- `forbid::Vector{String}`: tags of which none may hold.
"""
struct TagRule
    require_all::Vector{String}
    require_any::Vector{String}
    forbid::Vector{String}
end

"""
    matches(rule, code) -> Bool

Whether an EXFOR reaction code satisfies `rule`.
"""
matches(rule::TagRule, code::AbstractString) = rejection_reason(rule, code) === nothing

"""
    rejection_reason(rule, code) -> Union{String,Nothing}

Why `code` fails `rule` — the first forbidden code present, the first required code absent, or
the absence of every alternative — or `nothing` when it matches.

Used to record why a dataset was excluded, so that an exclusion can be audited rather than
merely observed.
"""
function rejection_reason(rule::TagRule, code::AbstractString)
    fields = reaction_fields(code)
    if fields === nothing
        return startswith(strip(String(code)), "(") ?
               "a combination of reaction codes (a ratio, sum, difference or product), not \
                the quantity itself" :
               "not a reaction code this package reads"
    end
    for tag in rule.forbid
        _holds(tag, fields) && return "forbidden code $(_describe(tag))"
    end
    for tag in rule.require_all
        _holds(tag, fields) || return "missing required code $(_describe(tag))"
    end
    isempty(rule.require_any) && return nothing
    any(tag -> _holds(tag, fields), rule.require_any) && return nothing
    return "none of the alternatives $(join(_describe.(rule.require_any), ", ")) present"
end

"""
Codes rejected for every observable, besides any combination of reactions.

| Tag | Excludes |
| :--- | :--- |
| `SF9:RECOM` | recommended values, not a measurement |
| `SF5:TER` | ternary fission |
| `SF6:RAT` | a ratio rather than the quantity itself |
| `SF7:G` | a γ-related quantity |
| `SF4:0-G-0` | γ rays as the product |
| `SF5:DL` | delayed rather than prompt emission |
| `SF5:CUM`, `SF5:(CUM)` | cumulative yield, or one the compiler could not tell from it |
| `SF8:RAW` | uncorrected data |

`REL` (relative data) is deliberately absent, since excluding it removes datasets that are
wanted, and is recorded per dataset through [`SCALE_QUALIFIERS`](@ref). `CHN`, a chain yield,
is a post-neutron product mass and is refused beside a pre-neutron mass by the abscissa rules
rather than here.
"""
const BASE_FORBID = [
    "SF9:RECOM",
    "SF5:TER",
    "SF6:RAT",
    "SF7:G",
    "SF4:0-G-0",
    "SF5:DL",
    "SF5:CUM",
    "SF5:(CUM)",
    "SF8:RAW",
]

# Abscissa rules, keyed by the `abscissa` list of the configuration. An abscissa is a joint
# index, so the key is a list of quantities rather than a composite token: the two-quantity
# rules are not the composition of the one-quantity ones and have to be stated in their own
# right. `(SEC)` is refused wherever `SEC` is: a compiler uncertain whether a quantity is
# post-neutron has not established that it is pre-neutron either.
#
#   mass                  pre-neutron fragment mass: mass-resolved, not charge-resolved, not
#                         differential in energy, and neither independent nor secondary, which
#                         would make it post-neutron, nor a chain (CHN), the post-neutron
#                         product mass, nor provisional (PRV): a mass from the two fragment
#                         energies uncorrected for neutron emission. 23802002, 23815002,
#                         23815003, 23815005 and 23588002 are provisional yields
#   product_mass          post-neutron fragment mass: as mass, but requiring the
#                         independent or secondary marking and forbidding the pre-neutron one
#   charge                fragment charge: charge-resolved, not mass-resolved
#   neutron_energy        energy abscissa of a spectrum
#   total_kinetic_energy  total kinetic energy, as TKE or as DE of both fragments; beside
#                         mass, the mass is pre-neutron as for mass alone
const ABSCISSA_RULES = Dict{Vector{String}, TagRule}(
    ["mass"] => TagRule(
        ["SF4:MASS"],
        String[],
        [
            "TKE",
            "SF4:ELEM",
            "SF5:SEC",
            "SF5:(SEC)",
            "SF5:PRV",
            "SF5:CHN",
            "SF6:DE",
            "SF5:IND",
        ],
    ),
    ["product_mass"] => TagRule(
        ["SF4:MASS"],
        ["SF5:SEC", "SF5:IND"],
        ["TKE", "SF4:ELEM", "SF5:PRE", "SF6:DE"],
    ),
    ["charge"] =>
        TagRule(String[], ["SF4:ELEM", "SF5:CHG"], ["TKE", "SF4:MASS", "SF6:DE"]),
    ["neutron_energy"] => TagRule(
        String[],
        ["SF6:KE", "SF6:DE"],
        ["SF4:MASS", "SF4:ELEM", "TKE", "SF7:LF+HF"],
    ),
    ["total_kinetic_energy"] =>
        TagRule(String[], ["TKE", "SF6:DE & SF7:LF+HF"], ["SF4:MASS", "SF4:ELEM"]),
    ["charge", "product_mass"] => TagRule(
        ["SF4:MASS", "SF4:ELEM"],
        ["SF5:SEC", "SF5:IND"],
        ["SF6:KE", "SF6:DE", "SF5:PRE"],
    ),
    ["mass", "total_kinetic_energy"] => TagRule(
        ["SF4:MASS"],
        ["TKE", "SF6:DE & SF7:LF+HF"],
        ["SF4:ELEM", "SF5:SEC", "SF5:(SEC)", "SF5:PRV", "SF5:CHN", "SF5:IND"],
    ),
)

# Ordinate rules, composed with the abscissa rule. The key is the value of `ordinate` in the
# configuration.
#
#   multiplicity                       prompt multiplicity per fragment (PR prompt, FRG per
#                                      fragment)
#   multiplicity_per_fission           prompt multiplicity per fragment pair (PR, and not per
#                                      fragment)
#   yield                              fission yield (FY). The quantity code `FY` also files the
#                                      most probable charge (ZP) against mass, which the
#                                      abscissa rule alone admits
#   fragment_kinetic_energy            pre-neutron fragment kinetic energy
#   product_kinetic_energy             post-neutron fragment kinetic energy
#   total_kinetic_energy               pre-neutron total kinetic energy (LF+HF, both fragments):
#                                      KE, or AKE, the older coding of the same mean; not KEP,
#                                      the most probable value. MSC marks a quantity outside the
#                                      standard definition, and every such dataset against mass
#                                      is something else: the TKE of fragments with provisional
#                                      masses (33082004), the maximal TKE of cold fragmentation
#                                      (23589002), the TKE at which neutron emission stops
#                                      (23118008, 23175011), a TKE against mass ratio in
#                                      alpha-energy windows (30916007)
#   total_kinetic_energy_dispersion    the width of the pre-neutron TKE distribution at fixed
#                                      mass: the datasets of the mean, whose MISC column the
#                                      configuration names ([[width]]); a width of one
#                                      fragment's energy takes the fragment_kinetic_energy rule
#   post_neutron_total_kinetic_energy  the same, post-neutron: SEC required, since a blank
#                                      branch establishes nothing — 40232003 leaves it blank
#                                      over provisional masses — and (SEC) is uncertain
#   neutron_kinetic_energy             centre-of-mass neutron energy, per neutron (,N)
#   spectrum                           prompt fission neutron spectrum (DE, energy-differential)
#   spectrum_maxwellian_ratio          the same, as a ratio to a Maxwellian (MXD)
#
# MSC excludes miscellaneous groupings; DA excludes angle-differential spectra, and FRG, NUM
# and PAR beside PR the per-fragment, per-multiplicity and partial ones.
const ORDINATE_RULES = Dict{String, TagRule}(
    "multiplicity" => TagRule(["SF5:PR", "SF5:FRG"], String[], ["SF8:MSC"]),
    "multiplicity_per_fission" => TagRule(["SF5:PR"], String[], ["SF8:MSC", "SF5:FRG"]),
    "yield" => TagRule(["SF6:FY"], String[], String[]),
    "fragment_kinetic_energy" =>
        TagRule(["SF6:KE", "SF5:PRE"], String[], ["SF7:LF+HF", "SF7:N"]),
    "product_kinetic_energy" =>
        TagRule(["SF6:KE"], String[], ["SF7:LF+HF", "SF7:N", "SF5:PRE"]),
    "total_kinetic_energy" =>
        TagRule(["SF6:KE", "SF7:LF+HF", "SF5:PRE"], String[], ["SF7:N", "SF8:MSC"]),
    "total_kinetic_energy_dispersion" =>
        TagRule(["SF6:KE", "SF7:LF+HF", "SF5:PRE"], String[], ["SF7:N", "SF8:MSC"]),
    "post_neutron_total_kinetic_energy" =>
        TagRule(["SF6:KE", "SF7:LF+HF", "SF5:SEC"], String[], ["SF7:N"]),
    "neutron_kinetic_energy" =>
        TagRule(["SF6:KE", "SF5:PR", "SF7:N"], String[], ["SF5:PRE"]),
    "spectrum" => TagRule(
        ["SF5:PR", "SF6:DE"],
        String[],
        ["SF6:DA", "SF5:FRG", "SF5:NUM", "SF5:PAR", "SF8:MXD", "SF8:MSC"],
    ),
    "spectrum_maxwellian_ratio" => TagRule(
        ["SF5:PR", "SF6:DE", "SF8:MXD"],
        String[],
        ["SF6:DA", "SF5:FRG", "SF5:NUM", "SF5:PAR"],
    ),
)

"""
The ASCII symbol of each abscissa quantity, as the literature writes it.

The configuration spells a quantity out, so that a file a user edits explains itself; a path and
a column header carry the symbol, which is the field's own nomenclature and what every other file
in this toolchain uses. `nu_vs_A_TKE` says what
`multiplicity_vs_mass_total_kinetic_energy` says, and a directory listing stays readable.
"""
const ABSCISSA_TOKEN = Dict(
    "mass" => "A",
    "product_mass" => "A_p",
    "charge" => "Z",
    "neutron_energy" => "E",
    "total_kinetic_energy" => "TKE",
)

"""
The ASCII symbol of each ordinate quantity; see [`ABSCISSA_TOKEN`](@ref).

A quantity appearing in both vocabularies — the total kinetic energy, which is an abscissa of a
yield and an ordinate against mass — carries the same symbol in both.
"""
const ORDINATE_TOKEN = Dict(
    "multiplicity" => "nu",
    "multiplicity_per_fission" => "nu_bar",
    "yield" => "Y",
    "fragment_kinetic_energy" => "E_K",
    "product_kinetic_energy" => "E_K_p",
    "total_kinetic_energy" => "TKE",
    "total_kinetic_energy_dispersion" => "sigma_TKE",
    "post_neutron_total_kinetic_energy" => "TKE_p",
    "neutron_kinetic_energy" => "eps",
    "spectrum" => "spectrum",
    "spectrum_maxwellian_ratio" => "spectrum_maxwellian_ratio",
)

"""
Ordinates for which a measurement in arbitrary units is a standard, interpretable form.

A prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
and the published comparisons are ratios to a Maxwellian in which only the shape carries the
physics. Excluding relative spectra therefore removes most of what the archive holds: of the 125
datasets it offers for 235-U(n,f) under `MFQ`, 42 answer the `spectrum` query in arbitrary units
against 15 in absolute ones. A thermal incident-energy window narrows both, to 11 and 6.

Every other ordinate is excluded from this, because a relative value there is not a form anyone
can interpret — a kinetic energy in arbitrary units is not an energy, and a multiplicity is a
count per fragment whose scale is the whole quantity.

A relative dataset cannot be put on a common scale with any other, not even another relative one,
so [`retrieve`](@ref) writes these to their own directory rather than beside absolute data.
"""
const RELATIVE_SCALE_ORDINATES = ("spectrum", "spectrum_maxwellian_ratio")

"""
Observables, as abscissa and ordinate, for which arbitrary units are a standard form besides the
ordinates of [`RELATIVE_SCALE_ORDINATES`](@ref): the joint yield Y(A, TKE). It is recorded event
by event and published as counts on a grid — 23268002 is 30 000 cells of counts — and what it
carries is the TKE distribution at each mass, which a consumer normalises to a mass yield. A
one-dimensional Y(A) in arbitrary units has no such use and stays excluded.
"""
const RELATIVE_SCALE_OBSERVABLES = [(["mass", "total_kinetic_energy"], "yield")]

"""
    tolerates_relative_scale(ordinate[, abscissa]) -> Bool

Whether `ordinate`, against `abscissa` when given, admits datasets in arbitrary units; see
[`RELATIVE_SCALE_ORDINATES`](@ref) and [`RELATIVE_SCALE_OBSERVABLES`](@ref).
"""
tolerates_relative_scale(ordinate::AbstractString) = ordinate in RELATIVE_SCALE_ORDINATES

function tolerates_relative_scale(
    ordinate::AbstractString,
    abscissa::AbstractVector{<:AbstractString},
)
    return tolerates_relative_scale(ordinate) ||
           (String[abscissa...], String(ordinate)) in RELATIVE_SCALE_OBSERVABLES
end

"""
Rules of one abscissa and ordinate together, added to the composition of the two.

A yield against pre-neutron mass must carry the pre-neutron branch `PRE`. The mass abscissa
alone admits whatever the branch leaves unsaid, and for a yield that is not pre-neutron: of the
yields against mass the archive offers, the pre-neutron ones carry `PRE`, the post-neutron chain
yields `CHN`, the provisional ones `PRV`. The requirement cannot sit on the mass abscissa itself,
since a multiplicity against mass is coded `MASS,PR/FRG,NU`, the fragment's own mass, and carries
no branch. A yield whose entry establishes a pre-neutron mass by its method without the code
saying so is read in [`CURATED_DATASETS`](@ref).
"""
const OBSERVABLE_RULES = Dict{Tuple{Vector{String}, String}, TagRule}(
    (["mass"], "yield") => TagRule(["SF5:PRE"], String[], String[]),
    (["mass", "total_kinetic_energy"], "yield") =>
        TagRule(["SF5:PRE"], String[], String[]),
)

"""
    tag_rule(abscissa, ordinate) -> TagRule

Compose the selection rule for an observable from its abscissa and ordinate rules.

`abscissa` is the list of quantities the observable is tabulated against — `["mass"]`, or
`["mass", "total_kinetic_energy"]` for a joint index.

The requirements of both are taken together, with those of [`OBSERVABLE_RULES`](@ref) for the
pair, and the forbidden tags of all are added to [`BASE_FORBID`](@ref). When both contribute a
`require_any` list the observable is not expressible, since the two alternatives cannot be
imposed independently; that combination is rejected by the configuration validator rather than
silently mis-selected.

# Example

```jldoctest
julia> rule = ExforFissionData.tag_rule(["mass"], "multiplicity");

julia> ExforFissionData.matches(rule, "98-CF-252(0,F)MASS,PR/FRG,NU")
true
```
"""
function tag_rule(abscissa::AbstractVector{<:AbstractString}, ordinate::AbstractString)
    x = ABSCISSA_RULES[String[abscissa...]]
    y = ORDINATE_RULES[String(ordinate)]
    require_any = if isempty(y.require_any)
        x.require_any
    elseif isempty(x.require_any)
        y.require_any
    else
        throw(
            ArgumentError(
                "abscissa $(abscissa) and ordinate \"$(ordinate)\" both impose alternative \
                 tags ($(x.require_any) and $(y.require_any)); the combination cannot be \
                 selected by these tests and is not supported",
            ),
        )
    end
    both = get(
        OBSERVABLE_RULES,
        (String[abscissa...], String(ordinate)),
        TagRule(String[], String[], String[]),
    )
    return TagRule(
        vcat(x.require_all, y.require_all, both.require_all),
        require_any,
        vcat(BASE_FORBID, x.forbid, y.forbid, both.forbid),
    )
end

"""Abscissae this package can retrieve, each a list of quantities, in configuration vocabulary."""
const ABSCISSAE = sort!(collect(keys(ABSCISSA_RULES)))

"""Ordinates this package can retrieve, in configuration vocabulary."""
const ORDINATES = sort!(collect(keys(ORDINATE_RULES)))

"""
Reaction-code qualifiers that bear on whether a value is on an absolute, directly comparable
scale, mapped to what each means.

None of these causes a dataset to be rejected — several are admitted deliberately. They are
recorded per dataset in the run record so that a consumer renormalising a directory of files
knows which of them are not on the same footing, rather than having to re-read the reaction
codes to find out.
"""
const SCALE_QUALIFIERS = Dict(
    "MSC" => "miscellaneous: not a standard EXFOR quantity definition",
    "REL" => "relative: an arbitrary scale, not absolute",
    "CHN" => "chain yield rather than an independent or mass yield",
    "DERIV" => "derived from other data rather than measured",
    "FCT" => "a correction factor has been applied",
)

"""
Reaction-code qualifiers naming the neutron spectrum that induced fission.

Recorded for the same reason: a thermal and a fission-spectrum-averaged measurement of the same
quantity are different numbers.
"""
const SPECTRUM_QUALIFIERS = Dict(
    "MXW" => "Maxwellian-averaged",
    "SPA" => "spectrum-averaged, spectrum unspecified",
    "FIS" => "fission-neutron-spectrum-averaged",
    "FST" => "fast-reactor-spectrum-averaged",
    "EPI" => "epithermal",
)

"""
The subfield each qualifier of [`SCALE_QUALIFIERS`](@ref) and [`SPECTRUM_QUALIFIERS`](@ref) is
coded in: the data type `DERIV` in SF9, the branches `CHN` in SF5, every other one among the
modifiers of SF8 (Dictionaries 31, 34 and 35).
"""
const QUALIFIER_SUBFIELD = Dict(
    "MSC" => 8,
    "REL" => 8,
    "CHN" => 5,
    "DERIV" => 9,
    "FCT" => 8,
    "MXW" => 8,
    "SPA" => 8,
    "FIS" => 8,
    "FST" => 8,
    "EPI" => 8,
)

"""
    qualifier_tag(qualifier) -> String

The tag of a qualifier in its subfield, `"SF8:MXW"` for `"MXW"`; see
[`QUALIFIER_SUBFIELD`](@ref).
"""
qualifier_tag(qualifier::AbstractString) = "SF$(QUALIFIER_SUBFIELD[qualifier]):$(qualifier)"

"""
    code_qualifiers(code) -> Vector{String}

The qualifiers of [`SCALE_QUALIFIERS`](@ref) and [`SPECTRUM_QUALIFIERS`](@ref) present in a
reaction code, each with its meaning, for the run record.
"""
function code_qualifiers(code::AbstractString)
    found = String[]
    for table in (SCALE_QUALIFIERS, SPECTRUM_QUALIFIERS)
        for tag in sort(collect(keys(table)))
            has_code(code, qualifier_tag(tag)) &&
                push!(found, string(tag, ": ", table[tag]))
        end
    end
    return found
end

"""
Ordinates whose value is itself an energy, and which are therefore restated in MeV.

`spectrum` and `spectrum_maxwellian_ratio` are excluded: the first is a density in energy and
the second is already dimensionless.
"""
const ENERGY_ORDINATES = (
    "fragment_kinetic_energy",
    "product_kinetic_energy",
    "total_kinetic_energy",
    "post_neutron_total_kinetic_energy",
    "neutron_kinetic_energy",
)

"""
Ordinates that count neutrons per fission.

A count of order one is never a percentage. A subentry that heads one of these
[`PERCENT_PER_FISSION`](@ref) has miscoded the unit, and its values are the multiplicity itself;
the csv rendering, converting the token, divides them by 100. Such a dataset is written on the
scale of its subentry; see [`rendering_scale`](@ref).
"""
const MULTIPLICITY_ORDINATES = ("multiplicity", "multiplicity_per_fission")

"""The unit token of a percentage per fission, `PC/FIS`."""
const PERCENT_PER_FISSION = "PC/FIS"

"""
Abscissae whose values are energies, converted to MeV from the unit their subentry column is
headed with.
"""
const ENERGY_ABSCISSAE = ("neutron_energy", "total_kinetic_energy")

"""
The EXFOR quantity code each ordinate belongs to.

The quantity selects which datasets the archive offers at all; the tag rule then chooses among
them. Several ordinates impose few tags of their own and rely on the abscissa rule, so an
ordinate paired with the wrong quantity silently admits a different observable: asking for
`yield` under `NU` returns prompt multiplicities, and under `E` returns
kinetic energies, both written as though they were yields. The configuration therefore names the
ordinate alone and the quantity is read from here, which is a pairing that cannot be got wrong.
"""
const ORDINATE_QUANTITY = Dict(
    "yield" => "FY",
    "multiplicity" => "NU",
    "multiplicity_per_fission" => "NU",
    "fragment_kinetic_energy" => "E",
    "product_kinetic_energy" => "E",
    "total_kinetic_energy" => "E",
    "total_kinetic_energy_dispersion" => "E",
    "post_neutron_total_kinetic_energy" => "E",
    "neutron_kinetic_energy" => "E",
    "spectrum" => "MFQ",
    "spectrum_maxwellian_ratio" => "MFQ",
)

"""
The EXFOR reaction code each entrance channel is queried under.

The channel names the fissioning system — `Cf252_sf`, `U235_nth`, `U235_nres` — and decides the
reaction code, which is why the configuration carries the channel and not the code: the two can
disagree only if both are written down. Which datasets a neutron-induced channel admits is
settled by the incident-energy window, which must lie inside the channel's interval of
[`CHANNEL_ENERGY_BOUNDS`](@ref) and defaults to it.
"""
const CHANNEL_REACTION =
    Dict("sf" => "0,f", "nth" => "n,f", "nres" => "n,f", "nfast" => "n,f")

"""Entrance channels this package can retrieve, in configuration vocabulary."""
const CHANNELS = sort!(collect(keys(CHANNEL_REACTION)))

"""
Incident-energy interval, in MeV, that the window of each neutron-induced channel may span, as
`(floor, ceiling)`; `sf` has no incident particle and no entry. The window of a configuration
defaults to the interval and must lie inside it, so that a dataset can only be filed under a
channel whose physics it belongs to.

| Channel | Interval | Region |
| :--- | :--- | :--- |
| `nth` | 0 to 0.1 eV | 1/v region below the first resonances; Westcott thermal convention |
| `nres` | 0.1 eV to 100 keV | resonances; Doppler width against level spacing |
| `nfast` | 100 keV to 20 MeV | statistical-model region to the end of the evaluated files |

The physics and the sources behind each bound are on the "Entrance channels" page of the
documentation.
"""
const CHANNEL_ENERGY_BOUNDS =
    Dict("nth" => (0.0, 1.0e-7), "nres" => (1.0e-7, 1.0e-1), "nfast" => (1.0e-1, 20.0))

"""
Spectrum qualifiers of [`SPECTRUM_QUALIFIERS`](@ref) that name a neutron spectrum no
measurement of the channel can have been made in; a dataset carrying one is rejected.

The archive files a spectrum-averaged measurement under a dummy incident energy, so the energy
window cannot catch it: `326650021`, ²³⁵U independent yields under `,,FIS` (a fission-spectrum
irradiation), is declared at 0.0253 eV and would pass a thermal window on its energy alone.
`SPA` names an unspecified spectrum and is admitted everywhere; `MXW` is admitted under
`nfast`, where it denotes a fission-Maxwellian average.
"""
const CHANNEL_FORBIDDEN_QUALIFIERS = Dict(
    "sf" => String[],
    "nth" => ["FST", "FIS", "EPI"],
    "nres" => ["MXW", "FST", "FIS"],
    "nfast" => ["EPI"],
)

"""
    channel_qualifier_conflict(channel, code) -> Union{String,Nothing}

The first qualifier of [`CHANNEL_FORBIDDEN_QUALIFIERS`](@ref) for `channel`, in the order listed
there, that the reaction code `code` carries among its modifiers; `nothing` when the code names
no spectrum the channel excludes.

The code `"92-U-235(N,F)ELEM/MASS,IND,FY,,FIS"`, for instance, gives `"FIS"` under `"nth"`, a
fission-spectrum irradiation not being a thermal measurement, and `nothing` under `"nfast"`.
"""
function channel_qualifier_conflict(channel::AbstractString, code::AbstractString)
    for tag in CHANNEL_FORBIDDEN_QUALIFIERS[channel]
        has_code(code, qualifier_tag(tag)) && return tag
    end
    return nothing
end

# The reaction-code grammar.
#
# EXFOR identifies what a dataset measures with a reaction code such as
#
#     92-U-233(N,F)ELEM/MASS,CUM,FY
#
# whose comma-separated fields name the measured quantity, the stage of the fission process it
# refers to, and the averaging applied. The vocabulary is applied inconsistently across entries,
# so selection cannot be done by parsing the code into fields: it is done by substring tests
# tuned against the data as it actually appears. The tables below are that tuning, preserved
# from the original script and annotated with what each tag catches. They are empirical
# knowledge about the state of the archive, not a formal grammar, and a rule that looks
# redundant is more likely to be guarding against a real entry than to be dead weight.

"""
    TagRule(require_all, require_any, forbid)

A substring test over an EXFOR reaction code.

A code matches when it contains every tag of `require_all`, at least one tag of `require_any`
(when that list is non-empty), and none of `forbid`.

# Fields
- `require_all::Vector{String}`: tags that must all be present.
- `require_any::Vector{String}`: tags of which at least one must be present; an empty list
  imposes no constraint.
- `forbid::Vector{String}`: tags of which none may be present.
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
function matches(rule::TagRule, code::AbstractString)
    for tag in rule.forbid
        occursin(tag, code) && return false
    end
    for tag in rule.require_all
        occursin(tag, code) || return false
    end
    isempty(rule.require_any) && return true
    for tag in rule.require_any
        occursin(tag, code) && return true
    end
    return false
end

"""
    rejection_reason(rule, code) -> Union{String,Nothing}

The tag that caused `code` to fail `rule`, or `nothing` when it matches.

Used to record why a dataset was excluded, so that an exclusion can be audited rather than
merely observed.
"""
function rejection_reason(rule::TagRule, code::AbstractString)
    for tag in rule.forbid
        occursin(tag, code) && return "forbidden tag \"$(tag)\""
    end
    for tag in rule.require_all
        occursin(tag, code) || return "missing required tag \"$(tag)\""
    end
    isempty(rule.require_any) && return nothing
    any(tag -> occursin(tag, code), rule.require_any) && return nothing
    return "none of the alternative tags $(rule.require_any) present"
end

"""
Tags rejected for every observable.

| Tag | Excludes |
| :--- | :--- |
| `RECOM` | recommended or evaluated values, not a measurement |
| `TER` | ternary fission |
| `RAT` | a ratio rather than the quantity itself |
| `,G` | a gamma-related channel |
| `-G-` | a ground-state-resolved product in the code's product field |
| `)/(`, `)//(` | a ratio of two reaction codes, in either form |
| `DEL` | delayed rather than prompt emission |
| `CUM` | cumulative rather than independent yield |
| `RAW` | uncorrected data |

`CHN` (chain yields) and `REL` (relative data) appear in this list commented out. Excluding them
removes datasets that are wanted, so they are admitted deliberately; they remain visible here
because that is a real decision rather than an oversight, and both are recorded per dataset
through [`SCALE_QUALIFIERS`](@ref).
"""
const BASE_FORBID = [
    "RECOM",
    # "CHN",
    "TER",
    "RAT",
    # "REL",
    ",G",
    "-G-",
    ")/(",
    ")//(",
    "DEL",
    "CUM",
    "RAW",
]

# Abscissa rules. The key is the value of `abscissa` in the configuration.
#
#   A      pre-neutron fragment mass:  mass-resolved, not charge-resolved, not energy-resolved,
#          and neither independent nor secondary, which would make it post-neutron
#   Ap      post-neutron fragment mass: as A, but requiring the independent/secondary marking
#          and forbidding the pre-neutron one
#   Z       fragment charge: charge-resolved, not mass-resolved
#   E       energy abscissa of a spectrum
#   TKE     total kinetic energy
#   ZAp     charge and post-neutron mass jointly
#   ATKE    mass and total kinetic energy jointly
const ABSCISSA_RULES = Dict{String, TagRule}(
    "A" => TagRule(["MASS"], String[], ["TKE", "ELEM", "SEC", "DE", "IND"]),
    "Ap" => TagRule(["MASS"], ["SEC", "IND"], ["TKE", "ELEM", "PRE", "DE"]),
    "Z" => TagRule([","], ["ELEM", "CHG"], ["TKE", "MASS", "DE"]),
    "E" => TagRule([","], ["KE", "DE"], ["MASS", "ELEM", "TKE", "LF+HF"]),
    "TKE" => TagRule([","], ["TKE", "DE,LF+HF"], ["MASS", "ELEM"]),
    "ZAp" => TagRule(["MASS", "ELEM"], ["SEC", "IND"], ["KE", "DE", "PRE"]),
    "ATKE" => TagRule(["MASS"], ["TKE", "DE,LF+HF"], ["ELEM"]),
)

# Ordinate rules, composed with the abscissa rule. The key is the value of `ordinate` in the
# configuration.
#
#   nu                  prompt multiplicity per fragment (PR prompt, FRG per fragment)
#   nuPair              prompt multiplicity per fragment pair (PR, and not per fragment)
#   yield               fission yield; carries no tags of its own, the abscissa rule decides
#   KE / KEp            pre- and post-neutron fragment kinetic energy
#   TKE / TKEp          pre- and post-neutron total kinetic energy (LF+HF, both fragments)
#   epsE                centre-of-mass neutron energy, per neutron (,N)
#   spectrum            prompt fission neutron spectrum (DE, energy-differential)
#   spectrumRatioMXW    the same, as a ratio to a Maxwellian (MXD)
#
# MSC excludes miscellaneous groupings; /DA and PR/ exclude angular differential and
# ratio-to-prompt forms of the spectrum.
const ORDINATE_RULES = Dict{String, TagRule}(
    "nu" => TagRule(["PR", "FRG"], String[], ["MSC"]),
    "nuPair" => TagRule(["PR"], String[], ["MSC", "FRG"]),
    "yield" => TagRule(String[], String[], String[]),
    "KE" => TagRule(["KE", "PRE"], String[], ["LF+HF", ",N"]),
    "KEp" => TagRule(["KE"], String[], ["LF+HF", ",N", "PRE"]),
    "TKE" => TagRule(["KE", "LF+HF", "PRE"], String[], [",N"]),
    "TKEp" => TagRule(["KE", "LF+HF"], String[], [",N", "PRE"]),
    "epsE" => TagRule(["KE", "PR", ",N"], String[], ["PRE"]),
    "spectrum" => TagRule(["PR", "DE"], String[], ["/DA", "PR/", "FRG", "MXD", "MSC"]),
    "spectrumRatioMXW" => TagRule(["PR", "DE", "MXD"], String[], ["/DA", "PR/", "FRG"]),
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
const RELATIVE_SCALE_ORDINATES = ("spectrum", "spectrumRatioMXW")

"""
    tolerates_relative_scale(ordinate) -> Bool

Whether `ordinate` admits datasets in arbitrary units; see [`RELATIVE_SCALE_ORDINATES`](@ref).
"""
tolerates_relative_scale(ordinate::AbstractString) = ordinate in RELATIVE_SCALE_ORDINATES

"""
    tag_rule(abscissa, ordinate) -> TagRule

Compose the selection rule for an observable from its abscissa and ordinate rules.

The requirements of both are taken together and the forbidden tags of both are added to
[`BASE_FORBID`](@ref). When both contribute a `require_any` list the observable is not
expressible, since the two alternatives cannot be imposed independently by substring tests;
that combination is rejected by the configuration validator rather than silently mis-selected.

# Example

```jldoctest
julia> rule = ExforFissionData.tag_rule("A", "nu");

julia> ExforFissionData.matches(rule, "98-CF-252(0,F)MASS,PR,FRG,NU")
true
```
"""
function tag_rule(abscissa::AbstractString, ordinate::AbstractString)
    x = ABSCISSA_RULES[String(abscissa)]
    y = ORDINATE_RULES[String(ordinate)]
    require_any = if isempty(y.require_any)
        x.require_any
    elseif isempty(x.require_any)
        y.require_any
    else
        throw(
            ArgumentError(
                "abscissa \"$(abscissa)\" and ordinate \"$(ordinate)\" both impose alternative \
                 tags ($(x.require_any) and $(y.require_any)); the combination cannot be \
                 selected by substring tests and is not supported",
            ),
        )
    end
    return TagRule(
        vcat(x.require_all, y.require_all),
        require_any,
        vcat(BASE_FORBID, x.forbid, y.forbid),
    )
end

"""Abscissae this package can retrieve, in configuration vocabulary."""
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
    "SPA" => "fission-spectrum-averaged",
    "FST" => "fast-neutron-induced",
    "EPI" => "epithermal",
    "THR" => "thermal",
)

"""
    code_qualifiers(code) -> Vector{String}

The qualifiers of [`SCALE_QUALIFIERS`](@ref) and [`SPECTRUM_QUALIFIERS`](@ref) present in a
reaction code, each with its meaning, for the run record.
"""
function code_qualifiers(code::AbstractString)
    found = String[]
    for table in (SCALE_QUALIFIERS, SPECTRUM_QUALIFIERS)
        for tag in sort(collect(keys(table)))
            occursin(tag, code) && push!(found, string(tag, ": ", table[tag]))
        end
    end
    return found
end

"""
Ordinates whose value is itself an energy, and which are therefore restated in MeV.

`spectrum` and `spectrumRatioMXW` are excluded: the first is a density in energy and the second
is already dimensionless.
"""
const ENERGY_ORDINATES = ("KE", "KEp", "TKE", "TKEp", "epsE")

"""EXFOR quantity codes within the scope of this package."""
const QUANTITIES = ("NU", "FY", "E", "MFQ")

"""
The EXFOR quantity code each ordinate belongs to.

The quantity selects which datasets the archive offers at all; the tag rule then chooses among
them. Several ordinates — `yield` most of all — impose no tags of their own and rely entirely on
the abscissa rule, so pairing one with the wrong quantity silently admits a different observable:
asking for `yield` under `NU` returns prompt multiplicities, and under `E` returns kinetic
energies, both written as though they were yields. The configuration validator refuses the
mismatch rather than leaving it to be noticed in the output.
"""
const ORDINATE_QUANTITY = Dict(
    "yield" => "FY",
    "nu" => "NU",
    "nuPair" => "NU",
    "KE" => "E",
    "KEp" => "E",
    "TKE" => "E",
    "TKEp" => "E",
    "epsE" => "E",
    "spectrum" => "MFQ",
    "spectrumRatioMXW" => "MFQ",
)

"""Reaction codes within the scope of this package: neutron-induced and spontaneous fission."""
const REACTIONS = ("n,f", "0,f")

# Readings of individual datasets that no reaction-code test can make.
#
# A few datasets hold a different observable from the one their reaction code names, or one the
# code does not distinguish from it: a total kinetic energy coded as the energy of one fragment,
# a pre-neutron quantity with the branch field left blank, a mean over a selected class of events
# coded exactly as the unconditional mean. Substring tests cannot tell these apart, so each is
# read here from its subentry text, one dataset at a time, and the evidence is written beside it.
# An entry here replaces the ordinate reading of the tag rule for that dataset alone; every other
# test of the selection still applies to it.

"""
    Curation(ordinate, reason)

What one dataset holds, established from its subentry text rather than from its reaction code.

# Fields
- `ordinate::Union{Nothing,String}`: the ordinate of [`ORDINATES`](@ref) the dataset holds, or
  `nothing` when it holds none of them.
- `reason::String`: the evidence, from the subentry and, where the subentry is silent, from the
  publication it cites.
"""
struct Curation
    ordinate::Union{Nothing, String}
    reason::String
end

"""
Datasets whose ordinate is read from the subentry text, keyed by dataset identifier; see
[`Curation`](@ref).

| Dataset | Reaction code | Holds |
| :--- | :--- | :--- |
| `14101003` | `98-CF-252(0,F)MASS,,KE,LF+HF` | pre-neutron TKE, from a double-velocity measurement |
| `22780003` | `98-CF-252(0,F)MASS,PRE,KE,FF` | pre-neutron TKE, not the energy of one fragment |
| `41109007` | `92-U-235(N,F)MASS,PRE,KE,LF+HF,MXW` | none: a mean over cold-fragmentation events |

The criterion for a blank branch field is kinematic. A double-velocity measurement yields
pre-neutron masses and energies directly, since isotropic neutron emission leaves the mean
fragment velocity unchanged; a double-energy measurement yields provisional masses until they are
corrected with ν(A), and is admitted only where its entry states that correction.

A dataset listed with an ordinate is admitted under that ordinate only, and only if the abscissa
rule and [`BASE_FORBID`](@ref) admit its code; under any other ordinate it is rejected with the
reason. A dataset listed without one is rejected under every ordinate.
"""
const CURATED_DATASETS = Dict{String, Curation}(
    "14101003" => Curation(
        "total_kinetic_energy",
        "curated: a double-velocity measurement, the times of flight of both fragments \
         (Whetstone 1963, doi:10.1103/PhysRev.131.1232), with the branch field left blank. \
         Isotropic neutron emission leaves the mean fragment velocity unchanged, so masses \
         from momentum conservation of the two measured velocities, \
         A_L = A_0 v_H / (v_L + v_H), are the pre-neutron masses, broadened but not biased, \
         and the TKE formed from them is pre-neutron. A double-energy measurement differs: \
         neutron emission lowers the fragment energies, and its masses stay provisional \
         until corrected with nu(A)",
    ),
    "22780003" => Curation(
        "total_kinetic_energy",
        "curated: coded as the kinetic energy of one fragment (FF), but the column holds the \
         total kinetic energy: subentry 001 gives graphs of 'yield, TKE and TKE-dispersion', \
         the MISC column beside DATA is the 'Dispersion of TKE distribution', and DATA reaches \
         150 MeV at A = 74, where one light fragment carries about 0.7 of the total; the masses \
         are pre-neutron, neutron emission having been corrected with nu(A, TKE)",
    ),
    "41109007" => Curation(
        nothing,
        "curated: a mean over cold-fragmentation events, not over the TKE distribution; the \
         entry is 'Uranium cold fragmentation induced by thermal and fast neutrons', and DATA \
         lies 20 to 30 MeV above every unconditional mean TKE against mass of 235-U(n,f), at \
         or above the maximal cold-fragmentation TKE of 23589002",
    ),
)

"""
    curation_rejection(curation, abscissa, ordinate, code) -> Union{String,Nothing}

The reason a curated dataset with reaction code `code` does not answer the query for `abscissa`
and `ordinate`, or `nothing` when it does.

The curated ordinate stands in for the ordinate rule of [`tag_rule`](@ref); the abscissa rule
and [`BASE_FORBID`](@ref) are applied to the code as for any other dataset.
"""
function curation_rejection(
    curation::Curation,
    abscissa::AbstractVector{<:AbstractString},
    ordinate::AbstractString,
    code::AbstractString,
)
    curation.ordinate == ordinate || return curation.reason
    x = ABSCISSA_RULES[String[abscissa...]]
    return rejection_reason(
        TagRule(x.require_all, x.require_any, vcat(BASE_FORBID, x.forbid)),
        code,
    )
end

"""
    RowDefect(heading, value, occurrences, description)

Lines of one dataset's DATA table that a compilation defect makes unusable: every line whose
`heading` column holds `value`, of which the archive is expected to hold `occurrences`.

The count is a guard. An entry the archive has since corrected no longer matches it, and the
dataset is then rejected until the defect record is reviewed, rather than losing a line that is
now right.

# Fields
- `heading::String`: the DATA heading tested, e.g. `"MASS"`.
- `value::Float64`: the value that marks the defective lines.
- `occurrences::Int`: how many lines carry it.
- `description::String`: the defect, its evidence and what is done about it, written to the run
  record in a form that can be reported to the IAEA Nuclear Data Section.
"""
struct RowDefect
    heading::String
    value::Float64
    occurrences::Int
    description::String
end

"""
Compilation defects of individual datasets, keyed by dataset identifier; see [`RowDefect`](@ref).
The lines they mark are left out before the dataset is reduced, and the description is written
to the run record as `archive_defects`.
"""
const ARCHIVE_DEFECTS = Dict{String, Vector{RowDefect}}(
    "14101003" => [
        RowDefect(
            "MASS",
            133.0,
            2,
            "EXFOR 14101.003 gives MASS 133 on two lines, with DATA 193 and 192 MeV, and 134 \
             on none, so one of the two is almost certainly 134. The values are read from \
             Fig. 7 of Whetstone 1963 (doi:10.1103/PhysRev.131.1232), which has no table to \
             settle which; both lines are left out rather than averaged into a value nobody \
             measured",
        ),
    ],
)

"""
    defect_lines(defects, data) -> Union{BitVector,String}

The lines of the DATA table `data` that `defects` mark, or the reason the defect records no
longer match the archive: a heading absent, or a marked value found on a different number of
lines than recorded.
"""
function defect_lines(defects::AbstractVector{RowDefect}, data::SubentryColumns)
    marked = falses(line_count(data))
    for defect in defects
        index = column(data, defect.heading)
        index === nothing &&
            return "the recorded compilation defect concerns column $(defect.heading), which \
                    the subentry no longer carries; the defect record must be reviewed"
        lines = BitVector(map(v -> !ismissing(v) && v == defect.value, data.values[index]))
        count(lines) == defect.occurrences || return "the subentry holds \
            $(defect.heading) $(defect.value) on $(count(lines)) lines where the recorded \
            compilation defect expects $(defect.occurrences); the archive may have corrected \
            it, and the defect record must be reviewed"
        marked .|= lines
    end
    return marked
end

"""
    CorrelationGroup(members, reason)

Datasets that are repeated runs of one experiment: accepted separately, each on its own file,
and one measurement for any combination of them.

# Fields
- `members::Vector{String}`: the dataset identifiers.
- `reason::String`: why they are one experiment.
"""
struct CorrelationGroup
    members::Vector{String}
    reason::String
end

"""
Groups of datasets that repeat one experiment; see [`CorrelationGroup`](@ref). Each accepted
member carries the others as `correlated_with` in the run record, so that no weighting downstream
counts one experiment once per run.
"""
const CORRELATION_GROUPS = [
    CorrelationGroup(
        ["400170091", "400170092", "400170093", "400170094", "400170095", "400170096"],
        "six thermal-neutron runs of one experiment (Dyachenko 1969, report YFI-8, p. 7; \
         INDC(CCP)-008), each taken alternately with one fast-neutron run at 120 to 600 keV in \
         the same apparatus; they agree within 0.2 MeV over the heavy-fragment peak and are \
         one measurement for any combination, not six",
    ),
]

"""
    correlation_group(identifier) -> Union{CorrelationGroup,Nothing}

The group of [`CORRELATION_GROUPS`](@ref) that holds `identifier`, or `nothing`.
"""
function correlation_group(identifier::AbstractString)
    index = findfirst(group -> identifier in group.members, CORRELATION_GROUPS)
    return index === nothing ? nothing : CORRELATION_GROUPS[index]
end

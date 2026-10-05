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
    PairSum(deviation, uncertainty, nubar, yields, own_yields)

The scale of a prompt multiplicity tabulated against fragment mass on both sides of symmetry,
from its pair sum S = ν(A) + ν(A₀ − A) weighted with the light-fragment yield. It is recorded
beside the reading and never decides it.

# Fields
- `deviation::Float64`: S/(kν̄) − 1, with k = 1 for a multiplicity per fragment and 2 per fission.
- `uncertainty::Float64`: the standard deviation of `deviation`, from those of S and ν̄; `NaN`
  where the dataset states no uncertainty.
- `nubar::Float64`: the ν̄ S is compared with, so that S = kν̄(1 + `deviation`) can be formed
  again from the written table.
- `yields::String`: the dataset identifier of the Y(A) that S is weighted with.
- `own_yields::Bool`: whether that Y(A) is of the same experiment; otherwise it is the fallback
  for the system.
"""
struct PairSum
    deviation::Float64
    uncertainty::Float64
    nubar::Float64
    yields::String
    own_yields::Bool
end

"""
Standard deviations within which a pair sum is consistent with ν̄; see [`scale_consistent`](@ref).
"""
const PAIR_SUM_TOLERANCE_SIGMAS = 3

"""
    scale_consistent(pair_sum) -> Union{Bool,Nothing}

Whether the pair sum agrees with ν̄ within [`PAIR_SUM_TOLERANCE_SIGMAS`](@ref) standard
deviations, or `nothing` where the dataset states no uncertainty to weigh it by.
"""
scale_consistent(pair_sum::PairSum) =
    isnan(pair_sum.uncertainty) ? nothing :
    abs(pair_sum.deviation) <= PAIR_SUM_TOLERANCE_SIGMAS * pair_sum.uncertainty

"""
What a reading of the complement test rests on: the data alone, or the data corroborated by the
publication, consulted.
"""
const CLASSIFICATION_BASES = ("data", "data+paper")

"""
    ComplementReading(basis[, pair_sum])

How the complement test reads a prompt multiplicity against fragment mass coded without `FRG`.

# Fields
- `basis::String`: one of [`CLASSIFICATION_BASES`](@ref).
- `pair_sum::Union{Nothing,PairSum}`: the scale, for a dataset tabulated on both sides of
  symmetry; `nothing` for one tabulated on one side or against mass and TKE.

# Throws
- `ArgumentError` for a basis outside [`CLASSIFICATION_BASES`](@ref).
"""
struct ComplementReading
    basis::String
    pair_sum::Union{Nothing, PairSum}
    function ComplementReading(basis::String, pair_sum::Union{Nothing, PairSum} = nothing)
        basis in CLASSIFICATION_BASES || throw(
            ArgumentError(
                "classification basis \"$(basis)\" is not one of $(CLASSIFICATION_BASES)",
            ),
        )
        return new(basis, pair_sum)
    end
end

"""
    Curation([abscissa,] ordinate, reason[, notes[, unit]])
    Curation(ordinate, reason, complement)

What one dataset holds, established from its subentry text rather than from its reaction code.

# Fields
- `abscissa::Union{Nothing,Vector{String}}`: the abscissa of [`ABSCISSAE`](@ref) the dataset is
  tabulated against, when its code does not say so either; `nothing` leaves the abscissa to the
  abscissa rule.
- `ordinate::Union{Nothing,String}`: the ordinate of [`ORDINATES`](@ref) the dataset holds, or
  `nothing` when it holds none of them.
- `reason::String`: the evidence, from the subentry and, where the subentry is silent, from the
  publication it cites.
- `notes::Dict{String,String}`: further statements about the dataset for its run record, each
  under its own key.
- `unit::Union{Nothing,String}`: the unit the data are in where the subentry heads them with
  another, `"ARB-UNITS"` for event counts headed `NO-DIM`; `nothing` leaves the unit as read.
- `complement::Union{Nothing,ComplementReading}`: for a multiplicity against mass coded without
  `FRG` and read by the complement test, its basis and scale; `nothing` otherwise.
"""
struct Curation
    abscissa::Union{Nothing, Vector{String}}
    ordinate::Union{Nothing, String}
    reason::String
    notes::Dict{String, String}
    unit::Union{Nothing, String}
    complement::Union{Nothing, ComplementReading}
end

Curation(ordinate::Union{Nothing, String}, reason::String) =
    Curation(nothing, ordinate, reason, Dict{String, String}(), nothing, nothing)
Curation(ordinate::String, reason::String, complement::ComplementReading) =
    Curation(nothing, ordinate, reason, Dict{String, String}(), nothing, complement)
Curation(abscissa::Vector{String}, ordinate::String, reason::String) =
    Curation(abscissa, ordinate, reason, Dict{String, String}(), nothing, nothing)
Curation(abscissa, ordinate, reason, notes::Dict{String, String}) =
    Curation(abscissa, ordinate, reason, notes, nothing, nothing)
Curation(abscissa, ordinate, reason, notes::Dict{String, String}, unit) =
    Curation(abscissa, ordinate, reason, notes, unit, nothing)

# The prompt multiplicity against fragment mass is per fragment when SF5 carries FRG and per
# fission, the multiplicity of the fragment pair against one fragment's mass, when it does not.
# The archive holds per-fragment data coded without FRG as well, so each dataset coded MASS,PR,NU
# that a ν(A) or ν(A, TKE) retrieval meets is read from its data with the complement test of
# docs/src/conventions.md; the test values are written beside the reading, and the basis and the
# scale of the reading in its ComplementReading.

const _NUBAR = "nubar of the IAEA neutron data standards 2017, doi:10.1016/j.nds.2018.02.002"

"""
Readings of prompt-neutron multiplicities against fragment mass coded without `FRG`, keyed by
dataset identifier; see [`Curation`](@ref). Each is decided from the data alone by the complement
test under the fissioning nucleus of mass number `A_0`. For a dataset with both halves, whose
pairs `(A, A_0 - A)` span at least 90 % of the light-fragment yield, `S` is the pair sum
`nu(A) + nu(A_0 - A)` weighted with that yield and `D = nu(A) - nu(A_0 - A)`:

- per fragment: `|S/nubar - 1| <= 0.25`, and `D = 0` is rejected: `D` changes sign along the
  sawtooth, beyond its uncertainties;
- per fission: `|S/nubar - 2| <= 0.5`, and `D = 0` holds.

A dataset tabulated on one side of symmetry, or against mass and TKE, is compared with a
per-fragment dataset instead: per fragment it equals `nu_FRG(A)`, per fission the pair sum
`nu_FRG(A) + nu_FRG(A_0 - A)`. Datasets per fission keep the reading of their code,
`multiplicity_per_fission`. Those the test cannot decide, and those that hold no multiplicity
against mass, are refused under every ordinate, with the test values as the reason.

The scale does not decide the reading. Each reading carries a [`ComplementReading`](@ref): whether
the publication, consulted, corroborates it, and, for a dataset with both halves, the deviation of
`S` from what the reading predicts, [`PairSum`](@ref).
"""
const MULTIPLICITY_READINGS = Dict{String, Curation}(
    # Per fragment, coded without FRG; the publication corroborates the reading.
    "23268005" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG. Over 50 pairs (A, A_0 - A), A_0 = 252, \
         nu(A) - nu(A_0 - A) changes sign along the sawtooth (19 positive, 31 negative) and \
         reaches 3.96, a median 34 times its uncertainty, where a pair multiplicity gives zero; \
         the pair sum weighted with the yield of 23268003, the same measurement, is 3.763 +- 0.003 \
         against 3.764 +- 0.016, the $(_NUBAR). Fig. 10 of Goeoek 2014 \
         (doi:10.1103/PhysRevC.90.064611, p. 064611-6) plots it as the multiplicity of a fragment \
         of mass A, from a matrix of 'the true number of neutrons emitted by a fragment with mass \
         m*', normalised to a total of 3.759",
        ComplementReading("data+paper", PairSum(-0.0004, 0.0043, 3.764, "23268003", true)),
    ),
    "23118006" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG and called the 'total' multiplicity. Over \
         46 pairs (A, A_0 - A), A_0 = 252, nu(A) - nu(A_0 - A) changes sign along the sawtooth (18 \
         positive, 28 negative) and reaches 3.72, a median 13 times its uncertainty; the pair sum \
         weighted with the yield of 23118002, the same measurement, is 3.773 +- 0.022 against \
         3.764 +- 0.016, the $(_NUBAR). Fig. 5 of Zeynalov 2011 (doi:10.3938/jkps.59.1396, p. \
         1398), 'PFN multiplicity as a function of FF mass', is this sawtooth, set beside the \
         per-fragment data of Budtz-Jorgensen 1988",
        ComplementReading("data+paper", PairSum(0.0023, 0.0072, 3.764, "23118002", true)),
    ),
    "23175008" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG. Over 53 pairs (A, A_0 - A), A_0 = 252, \
         nu(A) - nu(A_0 - A) changes sign along the sawtooth (21 positive, 32 negative) and \
         reaches 3.82, with chi2 per pair 37 against zero; the pair sum weighted with the yield of \
         23175002, the same measurement, is 3.69 +- 0.19 against 3.764 +- 0.016, the $(_NUBAR), \
         the uncertainty being that of the digitised error bars. Fig. 11 of the authors' \
         contribution of the same title and data to INDC(NDS)-220 (Mito 1988, p. 193) shows it as \
         'the neutron multiplicity versus mass nu(A)', normalised so that both fragments together \
         emit 3.7632; the article itself, Nucl. Phys. A 490, 307 \
         (doi:10.1016/0375-9474(88)90508-8), was not consulted",
        ComplementReading("data+paper", PairSum(-0.0198, 0.0498, 3.764, "23175002", true)),
    ),
    "23175010" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG; the REACTION text reads 'average neutron \
         multiplicity for fragments from mass 115 to 132 versus TKE'. At equal TKE, over 100 pairs \
         (A, A_0 - A) within 115 to 132, A_0 = 252, nu(A) - nu(A_0 - A) reaches 4.96 with chi2 per \
         pair 16, where a pair multiplicity gives zero; read at the mean TKE of 23175003, it \
         differs from the per-fragment nu(A) of 23175008 by 0.46 rms over 18 masses and from its \
         pair sum by 2.03. Fig. 13 of the authors' contribution of the same title and data to \
         INDC(NDS)-220 (Mito 1988, p. 196) plots 'the neutron multiplicity for fragments from mass \
         117 to 132' against TKE, 'approximated for each fragment by a straight line', and the \
         pair quantity apart, in its Fig. 12; the article itself, Nucl. Phys. A 490, 307 \
         (doi:10.1016/0375-9474(88)90508-8), was not consulted",
        ComplementReading("data+paper"),
    ),
    "21834009" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG; the REACTION text reads 'average number \
         of neutrons emitted per fragment'. Over 45 pairs (A, A_0 - A), A_0 = 236, nu(A) - nu(A_0 \
         - A) changes sign along the sawtooth, with chi2 per pair 28 against zero; the pair sum \
         weighted with the yield of 21834002, the same measurement at the same energy, is 2.484 +- \
         0.023 against 2.484, nubar at 0.5 MeV in ENDF/B-VIII.0 (doi:10.1016/j.nds.2018.02.001), \
         taken without an uncertainty. Table VIII of KfK-3220 (1981, doi:10.5445/IR/270016605) \
         gives 'the average number of neutrons emitted per fragment', negative values included",
        ComplementReading("data+paper", PairSum(0.0, 0.0091, 2.4836, "21834002", true)),
    ),
    "21834010" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG; the REACTION text reads 'average number \
         of neutrons emitted per fragment'. Over 45 pairs (A, A_0 - A), A_0 = 236, nu(A) - nu(A_0 \
         - A) changes sign along the sawtooth, with chi2 per pair 14 against zero; the pair sum \
         weighted with the yield of 21834003, the same measurement at the same energy, is 3.256 +- \
         0.046 against 3.141, nubar at 5.55 MeV in ENDF/B-VIII.0 (doi:10.1016/j.nds.2018.02.001), \
         taken without an uncertainty, 3.7 % above it. Table VIII of KfK-3220 (1981, \
         doi:10.5445/IR/270016605) gives 'the average number of neutrons emitted per fragment', \
         negative values included",
        ComplementReading("data+paper", PairSum(0.0366, 0.0145, 3.1411, "21834003", true)),
    ),
    # Per fragment, coded without FRG, by the data alone; the publication was not consulted.
    "41689004" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, \
         Yad. Fiz. 25, 723 (1977), 'Number and spectra of neutrons for fixed fragments', Fig. 2, \
         was not consulted. Over 9 pairs (A, A_0 - A) of its 4-u grid, A_0 = 252, nu(A) - nu(A_0 - \
         A) changes sign along the sawtooth and reaches 2.43, a median 7 times its uncertainty, \
         chi2 per pair 45 against zero; the pair sum weighted with the yield of 23268003, the \
         252-Cf fallback, the entry having no Y(A), is 3.95 +- 0.07 against 3.764 +- 0.016, the \
         $(_NUBAR), 4.8 % above it",
        ComplementReading("data", PairSum(0.0480, 0.0192, 3.764, "23268003", false)),
    ),
    "41502005" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, AIP \
         Conf. Proc. 769, 1003 (2005, doi:10.1063/1.1945175), was not consulted. Over 10 pairs \
         (A, A_0 - A) of its 4-u grid, A_0 = 236, nu(A) - nu(A_0 - A) changes sign along the \
         sawtooth and reaches 2.72, a median 7 times its uncertainty, chi2 per pair 105 against \
         zero; the pair sum weighted with the yield of 21981006, the 235-U fallback, the entry \
         having no Y(A), is 2.469 +- 0.034 against 2.425 +- 0.011, the $(_NUBAR), 1.8 % above it",
        ComplementReading("data", PairSum(0.0182, 0.0148, 2.425, "21981006", false)),
    ),
    "41502007" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, AIP \
         Conf. Proc. 769, 1003 (2005, doi:10.1063/1.1945175), was not consulted. In the 0.296 eV \
         resonance, over 9 pairs (A, A_0 - A) of its 4-u grid, A_0 = 240, nu(A) - nu(A_0 - A) \
         changes sign along the sawtooth and reaches 2.74, chi2 per pair 14 against zero; the pair \
         sum weighted with the yield of 21981007, the 239-Pu fallback, the entry having no Y(A), \
         is 2.82 +- 0.10 against the thermal 2.878 +- 0.013, the $(_NUBAR), 2.0 % below it",
        ComplementReading("data", PairSum(-0.0201, 0.0367, 2.878, "21981007", false)),
    ),
    "41712005" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, Yad. \
         Fiz. 48, 1635 (1988), 'Multiplicity distributions of neutrons from individual \
         fragments', was not consulted. It holds two mass groups against TKE, 108 to 126 and 126 \
         to 145, A_0 = 252, and so no pair; read at the mean TKE of 41712003, it differs from the \
         per-fragment nu(A) of 41712002 by 0.57 rms and from its pair sum by 2.06",
        ComplementReading("data"),
    ),
    "14652004" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, \
         Phys. Rev. 133, B603 (1964, doi:10.1103/PhysRev.133.B603), was not consulted. The entry \
         deduces it from the difference of double-energy and double-velocity mass distributions. \
         Over 16 pairs (A, A_0 - A), A_0 = 252, nu(A) - nu(A_0 - A) reaches 2.96 and changes sign \
         once along the sawtooth, negative at the 9 lightest masses and positive at the 7 \
         heaviest. No uncertainty is tabulated; noise about zero would order 16 signs into two \
         runs with a probability of 1.7e-4. The pair sum weighted with the yield of 23268003, the \
         252-Cf fallback, the entry's own Y(A) being post-neutron, is 3.738 against 3.764 +- \
         0.016, the $(_NUBAR), 0.7 % below it, with no uncertainty to weigh it by",
        ComplementReading("data", PairSum(-0.0069, NaN, 3.764, "23268003", false)),
    ),
    # Per fragment, with a pair sum off the scale of nubar.
    "22650004" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the article, \
         Tsuchiya 2000 (doi:10.1080/18811248.2000.9714976), was not consulted, and its abstract \
         calls nu(m*) a sawtooth. Over 42 pairs (A, A_0 - A), A_0 = 240, nu(A) - nu(A_0 - A) \
         changes sign along the sawtooth and reaches 4.19, a median 5 times its uncertainty, chi2 \
         per pair 105 against zero. Its scale is not that of nubar: the pair sum weighted with \
         the yield of 22650002, the same measurement, is 2.989 +- 0.011 against 2.878 +- 0.013, \
         the $(_NUBAR), 3.9 % and 6.3 standard deviations above it, and 2.914 +- 0.010 with the \
         yield of 21981007. The subentry heads DATA and DATA-ERR PC/FIS, a miscoding: the values, \
         0.70 to 5.36, are neutrons per fission, and are written as tabulated, not divided by 100 \
         as the csv rendering has them",
        ComplementReading("data", PairSum(0.0387, 0.0061, 2.878, "22650002", true)),
    ),
    "41502006" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, AIP \
         Conf. Proc. 769, 1003 (2005, doi:10.1063/1.1945175), was not consulted. Over 9 pairs \
         (A, A_0 - A) of its 4-u grid, A_0 = 240, nu(A) - nu(A_0 - A) changes sign along the \
         sawtooth and reaches 3.41, a median 7 times its uncertainty, chi2 per pair 74 against \
         zero. Its scale is not that of nubar: the pair sum weighted with the yield of 21981007, \
         the 239-Pu fallback, the entry having no Y(A), is 2.570 +- 0.036 against 2.878 +- 0.013, \
         the $(_NUBAR), 10.7 % and 8.1 standard deviations below it, while 41502007 of the same \
         measurement in the 0.296 eV resonance gives 2.82 +- 0.10",
        ComplementReading("data", PairSum(-0.1071, 0.0133, 2.878, "21981007", false)),
    ),
    # Per fission, as coded.
    "22660006" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded. nu(A) = nu(A_0 - A) at all 42 pairs (A, A_0 - A), A_0 = \
         234, and nu(A) is the pair sum of the per-fragment 22660005 of the same entry at all 85 \
         masses; the pair sum weighted with the yield of 21981005, the 233-U fallback, the entry \
         having no Y(A), is 5.029 +- 0.006, 1.1 % above twice 2.487 +- 0.011, the $(_NUBAR)",
        ComplementReading("data", PairSum(0.0110, 0.0046, 2.487, "21981005", false)),
    ),
    "23213012" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the light-fragment mass. It is the pair sum \
         nu_FRG(A) + nu_FRG(A_0 - A) of the per-fragment 23213014 of the same entry, A_0 = 252, to \
         0.038 rms over 23 masses, and differs from nu_FRG(A) by 1.99 rms",
        ComplementReading("data"),
    ),
    "41720003" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It differs from the \
         per-fragment nu(A) of 41720002 of the same entry, A_0 = 252, by 2.51 rms, reaching 5.0 at \
         A = 130.6 where one heavy fragment emits 0.8, and from its pair sum by 0.83 rms, the \
         difference lying near symmetry; weighted with the yield of 23268003 it is 3.70 against \
         3.764 +- 0.016, the $(_NUBAR)",
        ComplementReading("data"),
    ),
    "23012007" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It is the pair sum \
         nu_FRG(A) + nu_FRG(A_0 - A) of the per-fragment 23012008 of the same entry, A_0 = 240, to \
         0.012 rms over 29 masses, and differs from nu_FRG(A) by 1.63 rms",
        ComplementReading("data"),
    ),
    "41397003" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It is the pair sum \
         nu_FRG(A) + nu_FRG(A_0 - A) of the per-fragment 41397002 of the same entry, A_0 = 240, to \
         0.016 rms over 26 masses, and differs from nu_FRG(A) by 1.76 rms",
        ComplementReading("data"),
    ),
    "41694004" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. Against the per-fragment \
         41694003 of the same entry, A_0 = 240, chi2 per mass is 1.3 as the pair sum nu_FRG(A) + \
         nu_FRG(A_0 - A) and 33 as nu_FRG(A), over 30 masses",
        ComplementReading("data"),
    ),
    "41720005" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It differs from the \
         per-fragment nu(A) of 41720004 of the same entry, A_0 = 240, by 2.50 rms, reaching 4.2 at \
         A = 130.3 where one heavy fragment emits 0.4, and from its pair sum by 0.86 rms, the \
         difference lying near symmetry; weighted with the yield of 21981007 it is 3.09 against \
         2.878 +- 0.013, the $(_NUBAR)",
        ComplementReading("data"),
    ),
    "41397006" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It is the pair sum \
         nu_FRG(A) + nu_FRG(A_0 - A) of the per-fragment 41397004 of the same entry, A_0 = 234, to \
         0.033 rms over 25 masses, chi2 per mass 0.02, against 131 as nu_FRG(A)",
        ComplementReading("data"),
    ),
    "21095003" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded; the REACTION text reads 'prompt NU from both fragments as \
         a function of the mass of the heavy fragment'. It is the pair sum of the per-fragment \
         21095002 and 21095004 of the same entry, A_0 = 236, to 0.018 rms over 11 masses, against \
         1.00 rms as nu_FRG(A)",
        ComplementReading("data"),
    ),
    "21095005" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded; the REACTION text reads 'prompt NU per fragment pair as a \
         function of the heavy fragment mass'. It is the pair sum of the per-fragment 21095002 and \
         21095004 of the same entry, A_0 = 236, to within rounding over 11 masses, against 1.66 \
         rms as nu_FRG(A)",
        ComplementReading("data"),
    ),
    "22464005" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It is the pair sum of \
         the per-fragment 22464004 of the same entry, A_0 = 236, to within rounding over 29 \
         masses, against 1.48 rms as nu_FRG(A)",
        ComplementReading("data"),
    ),
    "41397007" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It is the pair sum \
         nu_FRG(A) + nu_FRG(A_0 - A) of the per-fragment 41397005 of the same entry, A_0 = 236, to \
         0.13 rms over 30 masses, chi2 per mass 0.18, against 65 as nu_FRG(A)",
        ComplementReading("data"),
    ),
    "41516013" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. It is the pair sum \
         nu_FRG(A) + nu_FRG(A_0 - A) of the per-fragment 41516012 of the same entry, A_0 = 236, to \
         0.022 rms over 49 masses, chi2 per mass 0.13, against 771 as nu_FRG(A)",
        ComplementReading("data"),
    ),
    "23268007" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded; the REACTION text reads 'total average prompt-fission \
         neutron multiplicity as a function of TKE and mass', against the light-fragment mass. At \
         equal TKE it is the pair sum of the per-fragment 23268008 of the same measurement, A_0 = \
         252, with chi2 per cell 0.02 over 1092 cells, against 217 as nu_FRG(A, TKE); Figs. 13 and \
         14 of Goeoek 2014 (doi:10.1103/PhysRevC.90.064611) plot it as 'the average total neutron \
         multiplicity of the pair of fragments'",
        ComplementReading("data+paper"),
    ),
    "22660009" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded; the REACTION text reads 'total neutron multiplicity \
         versus fragment mass for specific 5 MeV TKE bins', against the heavy-fragment mass. At \
         equal TKE it is the pair sum of the per-fragment 22660008 of the same entry, A_0 = 234, \
         to within rounding over 150 cells, against 2.04 rms as nu_FRG(A, TKE)",
        ComplementReading("data"),
    ),
    "22464009" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the heavy-fragment mass. At equal TKE it is the \
         pair sum of the per-fragment 22464007 of the same entry, A_0 = 236, to within rounding \
         over 134 cells, against 1.80 rms as nu_FRG(A, TKE)",
        ComplementReading("data"),
    ),
    "14838002" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded, against the light-fragment mass 92 to 122, A_0 = 252, \
         with no per-fragment dataset in its entry. Against the per-fragment nu(A, TKE) of \
         23268008 (Goeoek 2014) at equal TKE, chi2 per cell is 29 as the pair sum and 851 as one \
         fragment over 180 cells; read at the mean TKE of 23268004, it differs from the pair sum \
         of the per-fragment 23268005 by 0.17 rms and from nu(A) by 1.92",
        ComplementReading("data"),
    ),
    # Undecided.
    "23118007" => Curation(
        nothing,
        "curated: not read; the test does not decide it. The REACTION text calls it the 'total' \
         multiplicity, as it does the per-fragment 23118006 of the same entry. It holds mass bins \
         115-116 to 125-129 alone, A_0 = 252, so no complementary pair lies within it; read at the \
         mean TKE of 23268004 it lies 0.59 above the per-fragment nu(A) of 23118006 and 0.71 below \
         its pair sum, and against the per-fragment nu(A, TKE) of 23268008 chi2 per cell is 84 as \
         one fragment and 40 as the pair sum. Its figure, Fig. 7 of Zeynalov 2011 \
         (doi:10.3938/jkps.59.1396), is captioned 'PFN multiplicity as a function of TKE for \
         selected.' and does not say which",
    ),
    # No multiplicity against mass.
    "14387005" => Curation(
        nothing,
        "curated: tabulated against the mass ratio (MASS-RATIO), not a fragment mass; the \
         complement test does not apply",
    ),
    "41674002" => Curation(
        nothing,
        "curated: tabulated against the mass ratio (MASS-RATIO), not a fragment mass; the \
         complement test does not apply",
    ),
    "41674003" => Curation(
        nothing,
        "curated: tabulated against the mass ratio (MASS-RATIO), not a fragment mass; the \
         complement test does not apply",
    ),
    "41673002" => Curation(
        nothing,
        "curated: tabulated against the mass ratio (MASS-RATIO), not a fragment mass; the \
         complement test does not apply",
    ),
)

# Entry 41425 (Vorobiev 2001) gives its pre-neutron mass yields as unfolded from the neutron
# multiplicity matrices, in 4-pi (015) and 2x2-pi (016) geometry, and places them on Fig. 11a
# '(NUt=0)' of its methods paper, which the entry does not explain.
_vorobiev_yield(geometry, mean_heavy_mass, figures) = "curated: unfolded for $(geometry) \
     geometry, this yield is not the inclusive pre-neutron mass yield. It lies about 3 u off \
     every inclusive measurement: its peaks lie at A = 106 and 146, where the nine pre-neutron \
     Y(A) accepted for 252-Cf over both halves peak at 107 to 108 and 143 to 145, and its mean \
     heavy mass is $(mean_heavy_mass) against 142.9 to 143.6 for those nine (143.4 for Goeoek \
     2014, 23268003). The mass scale of the entry is not at fault: the nu(A) of 41425014, of the same \
     measurement, has its sawtooth minimum at A = 130, as the other measurements do. Nor does a \
     selection of events without neutrons explain it, since such events favour heavy masses near \
     the closed shells at A_H = 132 and would lower the mean heavy mass, not raise it. The \
     subentry places the data on $(figures) of Dushin 2004 (doi:10.1016/j.nima.2003.09.029) and \
     does not say what NUt=0 denotes; the article could not be consulted"

"""
Datasets whose ordinate is read from the subentry text, keyed by dataset identifier; see
[`Curation`](@ref).

| Dataset | Reaction code | Holds |
| :--- | :--- | :--- |
| `14101003` | `98-CF-252(0,F)MASS,,KE,LF+HF` | pre-neutron TKE, from a double-velocity measurement |
| `22780003` | `98-CF-252(0,F)MASS,PRE,KE,FF` | pre-neutron TKE, not the energy of one fragment |
| `41109007` | `92-U-235(N,F)MASS,PRE,KE,LF+HF,MXW` | none: a mean over cold-fragmentation events |
| `23268002` | `98-CF-252(0,F)MASS,PRE,FY,,MSC` | Y(A, TKE), in counts |
| `22413013` | `94-PU-240(0,F)MASS,PRE,FY/DE,,RAW` | Y(A, TKE), in raw counts |
| `40420062` | `98-CF-252(0,F)MASS,PRE,FY/DE,LF+HF,RAW` | none: a joint histogram against provisional masses |
| `41425015`, `41425016` | `98-CF-252(0,F)MASS,PRE,FY` | none: a yield 3 u off the inclusive one, from Fig. 11a (NUt=0) |

The criterion for a blank branch field is kinematic. A double-velocity measurement yields
pre-neutron masses and energies directly, since isotropic neutron emission leaves the mean
fragment velocity unchanged; a double-energy measurement yields provisional masses until they are
corrected with ν(A), and is admitted only where its entry states that correction.

The multiplicities against mass coded without `FRG` are read by the complement test and listed
apart, in [`MULTIPLICITY_READINGS`](@ref), which this table includes.

A dataset listed with an ordinate is admitted under that ordinate only, and only if the abscissa
rule and [`BASE_FORBID`](@ref) admit its code; under any other ordinate it is rejected with the
reason. A dataset listed with an abscissa as well is read in full, and admitted under that
abscissa and ordinate alone. A dataset listed without an ordinate is rejected under every one.
"""
const CURATED_DATASETS = merge(
    Dict{String, Curation}(
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
        "23268002" => Curation(
            ["mass", "total_kinetic_energy"],
            "yield",
            "curated: the joint pre-neutron yield Y(A, TKE), coded MASS,PRE,FY,,MSC without a TKE \
         marker. Its REACTION text reads 'Fission fragment yield as a function of pre-neutron \
         mass and TKE (counts)', and its DATA table holds 30 000 cells of counts, TKE 100.5 to \
         299.5 MeV in steps of 1 MeV against MASS 51 to 200 (Goeoek 2014, \
         doi:10.1103/PhysRevC.90.064611, Fig. 6a). The csv rendering drops the TKE column and \
         gives the unit as PART/FIS; the subentry gives ARB-UNITS",
            Dict(
                "tke_grid_inference" => "the TKE values are the centres of 1-MeV bins, an \
                inference the data support but EXFOR does not state: taken as centres, the \
                count-weighted mean TKE of the matrix reproduces that of 23268004 to +0.05 MeV \
                over the masses of at least 1000 counts, and taken as lower or upper edges it \
                misses by +0.55 or -0.45 MeV",
                "mass_marginal" => "23268003, the pre-neutron mass yield of the same measurement \
                in PC/FIS, is this matrix summed over TKE and normalised to 200 %, to a \
                relative 4e-6; 23268004 holds its mean TKE and the standard deviation of TKE \
                against mass",
            ),
        ),
        "22413013" => Curation(
            ["mass", "total_kinetic_energy"],
            "yield",
            "curated: the joint pre-neutron yield Y(A, TKE) of 240-Pu(sf) in raw event counts \
         (Dematte 1997, doi:10.1016/S0375-9474(97)00032-8), coded MASS,PRE,FY/DE,,RAW: 2911 \
         cells, E 140 to 210 MeV in 1-MeV steps against heavy masses 120 to 160. EN-SEC codes \
         the energy (E,FF), but at 140 to 210 MeV against these masses it is the total kinetic \
         energy, as in 21995034 of the same group; the masses are from the double-energy method \
         with 'corrections ... for prompt neutron emission' (22413001, METHOD, CORRECTION). RAW \
         marks the counts themselves, which carry no normalisation; the heading NO-DIM is read \
         as arbitrary units",
            Dict{String, String}(),
            "ARB-UNITS",
        ),
        "41425015" => Curation(
            nothing,
            _vorobiev_yield("4-pi", "146.7", "Fig. 10 and Fig. 11a '(NUt=0)'"),
        ),
        "41425016" =>
            Curation(nothing, _vorobiev_yield("2x2-pi", "146.2", "Fig. 11a '(NUt=0)'")),
        "40420062" => Curation(
            nothing,
            "curated: a joint histogram of event counts in 1.5-u mass and 2.5-MeV TKE bins, coded \
         PRE, whose masses its entry does not establish as pre-neutron: entry 40420 names \
         entry 40232 for the 'FY and TKE for this experiment', and 40232 states that \
         'corrections on emission of neutrons from fission fragments were not introduced'",
        ),
    ),
    MULTIPLICITY_READINGS,
)

"""
    curation_rejection(curation, abscissa, ordinate, code) -> Union{String,Nothing}

The reason a curated dataset with reaction code `code` does not answer the query for `abscissa`
and `ordinate`, or `nothing` when it does.

The curated ordinate stands in for the ordinate rule of [`tag_rule`](@ref); the abscissa rule
and [`BASE_FORBID`](@ref) are applied to the code as for any other dataset, unless the curation
names the abscissa too, in which case it stands in for the whole rule.
"""
function curation_rejection(
    curation::Curation,
    abscissa::AbstractVector{<:AbstractString},
    ordinate::AbstractString,
    code::AbstractString,
)
    curation.ordinate == ordinate || return curation.reason
    if curation.abscissa !== nothing
        return curation.abscissa == String[abscissa...] ? nothing : curation.reason
    end
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
How the members of a [`CorrelationGroup`](@ref) are related, which is what a consumer needs to
know to use them as the one measurement they are:

- `republication`: one result published twice, the earlier marked superseded by the later; take
  one, by default the later, [`SUPERSEDED_DATASETS`](@ref) saying which that is.
- `alternative_analysis`: one set of events reduced twice; take one.
- `repeated_run`: the quantity measured again in the same experiment, in another run or cycle or
  at another flight path; combine the members as one.
- `complementary_range`: parts of one spectrum, each over its own range; join them under one
  normalisation.
"""
const CORRELATION_RELATIONS =
    ("republication", "alternative_analysis", "repeated_run", "complementary_range")

"""
    CorrelationGroup(members, relation, reason)

Datasets of one experiment: accepted separately, each on its own file, and one measurement for
any combination of them.

# Fields
- `members::Vector{String}`: the dataset identifiers; of a `republication`, the superseded one
  first.
- `relation::String`: how they are related, one of [`CORRELATION_RELATIONS`](@ref).
- `reason::String`: why they are one experiment.
"""
struct CorrelationGroup
    members::Vector{String}
    relation::String
    reason::String
    function CorrelationGroup(members, relation, reason)
        relation in CORRELATION_RELATIONS || throw(
            ArgumentError(
                "relation $(repr(relation)) of the group of $(first(members)) is \
                 none of $(join(CORRELATION_RELATIONS, ", "))",
            ),
        )
        return new(members, relation, reason)
    end
end

"""
Groups of datasets that repeat one experiment, give it in parts, or publish it twice; see
[`CorrelationGroup`](@ref). Each accepted
member carries the others as `correlated_with` in the run record, with the relation of the group
as `correlation_relation`, so that no weighting downstream counts one experiment once per member.
"""
const CORRELATION_GROUPS = [
    CorrelationGroup(
        ["400170091", "400170092", "400170093", "400170094", "400170095", "400170096"],
        "repeated_run",
        "six thermal-neutron runs of one experiment (Dyachenko 1969, report YFI-8, p. 7; \
         INDC(CCP)-008), each taken alternately with one fast-neutron run at 120 to 600 keV in \
         the same apparatus; they agree within 0.2 MeV over the heavy-fragment peak and are \
         one measurement for any combination, not six",
    ),
    CorrelationGroup(
        ["41516017", "41597002"],
        "republication",
        "one measurement of the 235-U to 252-Cf spectrum ratio at 0.0363 eV, published twice: \
         41516017 (Vorobyev 2010, 252-Cf over 235-U) is marked superseded by 41597002 \
         (Vorobyev 2013, 235-U over 252-Cf) in its STATUS (SPSDD); the two are one \
         measurement for any combination, and the later analysis is the authors' own choice",
    ),
    CorrelationGroup(
        ["30046011", "307720151", "307720152", "307720153"],
        "repeated_run",
        "four runs of one measurement of the 252-Cf(sf) neutron number distribution in the \
         liquid scintillator tank of Boldeman, all in Table III of Boldeman and Hines 1985 \
         (doi:10.13182/NSE85-A17133): 30046011 is the run of Boldeman and Dalton, 20E+6 \
         fissions at a discriminator bias of 480 keV, and 30772015 gives the 'recent data for \
         three other bias values', 8.7E+6 fissions at 620 keV, 8.4E+6 at 720 keV and 6.8E+6 \
         at 1950 keV (p. 115). The runs are separate sets of events in one apparatus, each \
         normalised to a nubar of 3.757; they are one measurement for any combination",
    ),
    CorrelationGroup(
        ["30046008", "30772010"],
        "republication",
        "one measurement of the 235-U(nth,f) neutron number distribution, published twice: \
         30046008 (Boldeman 1967, AAEC/E-172) is marked superseded by 30772010 (Boldeman \
         1985, the reanalysis) in its STATUS (SPSDD)",
    ),
    CorrelationGroup(
        ["30046009", "30772011"],
        "republication",
        "one measurement of the 239-Pu(nth,f) neutron number distribution, published twice: \
         30046009 (Boldeman 1967, AAEC/E-172) is marked superseded by 30772011 (Boldeman \
         1985, the reanalysis) in its STATUS (SPSDD)",
    ),
    CorrelationGroup(
        ["30046007", "30772009"],
        "republication",
        "one measurement of the 233-U(nth,f) neutron number distribution, published twice: \
         30046007 (Boldeman 1967, AAEC/E-172) is marked superseded by 30772009 (Boldeman \
         1985, the reanalysis) in its STATUS (SPSDD)",
    ),
    CorrelationGroup(
        ["40930004", "40930010", "40930011", "40930012"],
        "complementary_range",
        "four parts of one measurement of the 233-U(nth,f) spectrum (Starostov 1985, Fig. 4 \
         bottom of INDC(CCP)-252, p. 16): the first cycle with the anthracene crystal \
         (40930004, 0.10 to 1.7 MeV), the stilbene crystal (40930010, 1.6 to 4.5 MeV) and \
         the plastic scintillator (40930011, 3.8 to 9.4 MeV), and the second cycle \
         (40930012, 0.02 to 3.3 MeV), which repeats the lower range and extends it \
         downwards; each subentry names the other three in its STATUS (COREL), and they are \
         one measurement for any combination, not four",
    ),
    CorrelationGroup(
        ["40930006", "40930013", "40930014", "40930015"],
        "complementary_range",
        "four parts of one measurement of the 235-U(nth,f) spectrum (Starostov 1985, Fig. 4 \
         top of INDC(CCP)-252, p. 16): the first cycle with the anthracene crystal \
         (40930006, 0.10 to 1.8 MeV), the stilbene crystal (40930013, 0.92 to 7.4 MeV) and \
         the plastic scintillator (40930014, 4.4 to 10.6 MeV), and the second cycle \
         (40930015, 0.02 to 2.7 MeV), which repeats the lower range and extends it \
         downwards; each subentry names the other three in its STATUS (COREL), and they are \
         one measurement for any combination, not four",
    ),
    CorrelationGroup(
        ["40930008", "40930016", "40930017", "40930018"],
        "complementary_range",
        "four parts of one measurement of the 239-Pu(nth,f) spectrum (Starostov 1985, Fig. 3 \
         bottom of INDC(CCP)-252, p. 16): the first cycle with the anthracene crystal \
         (40930008, 0.14 to 2.2 MeV), the stilbene crystal (40930016, 1.8 to 6.7 MeV) and \
         the plastic scintillator (40930017, 2.9 to 11.3 MeV), and the second cycle \
         (40930018, 0.02 to 4.4 MeV), which repeats the lower range and extends it \
         downwards; each subentry names the other three in its STATUS (COREL), and they are \
         one measurement for any combination, not four",
    ),
    CorrelationGroup(
        ["40418006", "40418008"],
        "republication",
        "one measurement of the ratio of the 252-Cf(sf) spectrum to a Maxwellian of 1.42 MeV \
         (Blinov 1973), published twice: 40418006, 98 points from 0.012 to 6.7 MeV digitised \
         from Fig. 4 of the Antwerp 1982 proceedings, is marked superseded in its STATUS \
         (SPSDD) by 40418008, the 79 energy groups from 0.012 to 11.4 MeV of Table 5 of \
         INDC(CCP)-0238, whose STATUS says 'This data supersede data of Subent 006'. \
         40418006 carries nothing its successor lacks but a finer grid, read off a figure \
         whose symbols overlap (COMMENT)",
    ),
    CorrelationGroup(
        ["40875003", "41158003"],
        "republication",
        "one measurement of the 252-Cf(sf) spectrum below 1.22 MeV as a ratio to a \
         Maxwellian, published twice: 40875003 (Dyachenko 1989) is marked superseded in its \
         STATUS (SPSDD, 'Final publication') by 41158003 (Lajtai 1990, Table 2 of Nucl. \
         Instrum. Methods A 293, 555), whose STATUS says 'This Subent superseded Subent \
         40875.003'. The two hold the same 70 energies from 0.025 to 1.22 MeV; 68 of the 70 \
         values are revised in 41158003, 1.10 to 1.075 at 0.045 MeV, and 40875003 states an \
         uncertainty on every row where 41158003 states none",
    ),
    CorrelationGroup(
        ["40644003", "40644002"],
        "republication",
        "one measurement of the 252-Cf(sf) spectrum (Starostov 1979), published twice: \
         40644003, Table 1 of the Paris 1976 proceedings, in arbitrary units, is marked \
         preliminary, outdated and superseded in its STATUS (PRELM; OUTDT,40644002; \
         SPSDD,40644002, 'Superseded by spectrum normalized to 1. according to authors' \
         comment') by 40644002, Table 1 of NIIAR-1(360), 1979, normalised to the number of \
         neutrons. 40644003 holds 99 points from 0.01 MeV against the 79 from 0.0143 MeV of \
         its successor, and no scale",
    ),
    CorrelationGroup(
        ["40875002", "41158002"],
        "republication",
        "one measurement of the 252-Cf(sf) spectrum below 1.22 MeV, published twice: \
         40875002 (Dyachenko 1989), in neutrons per fission, MeV and steradian, is marked \
         superseded in its STATUS (SPSDD, 'Final publication') by 41158002 (Lajtai 1990, \
         Table 2 of Nucl. Instrum. Methods A 293, 555), whose STATUS says 'This Subent \
         superseds Subent 40875.002'. The two hold the same 70 energies from 0.025 to 1.22 \
         MeV; 41158002 is in arbitrary units, and the ratio of its values to those of \
         40875002 varies by 20 % over the table, so the shape is revised and 40875002 alone \
         carries an absolute scale",
    ),
    CorrelationGroup(
        ["41694002", "41720002"],
        "alternative_analysis",
        "two reductions of one measurement of nu(A) of 252-Cf(sf), by the same authors at \
         one institute: 41720002 (Basova 1979, At. Energ. 46, 240, submitted 13 March 1978) \
         and 41694002 (Zamyatnin 1979, Yad. Fiz. 29, 595, submitted 19 May 1978). The STATUS \
         of 41720002 calls 41694002 an 'Alternative result' (COREL). Both entries quote 7.84E+6 \
         fissions and 2.83E+5 fragment-neutron coincidences with the neutron counter at 0 \
         degrees, which points to one set of events reduced twice; against it they state the \
         measurement differently: 41720, mass resolution 3.5 u, time resolution about 1 ns, \
         an Al2O3 backing of 30 microgram/cm2; 41694, 4 u, 4 ns, 60 microgram/cm2, and \
         corrections for the angular resolution and for the neutron efficiency against \
         energy that 41720 does not name. The two tables differ by 0.34 neutrons rms over \
         their 80 shared masses, so one of the two is taken, never both",
    ),
    CorrelationGroup(
        ["41694003", "41720004"],
        "alternative_analysis",
        "two reductions of one measurement of nu(A) of 239-Pu(nth,f), in the publications of \
         41720002 and 41694002: 41720004 (Basova 1979) and 41694003 (Zamyatnin 1979). The \
         STATUS of 41720004 calls 41694003 an 'Alternative result' (COREL), and both describe \
         the sample in the same words, 'deposited electrically on a Au-covered organic film'. \
         The counts quoted are close and not equal: 1.28E+6 fissions in 41720 against \
         1253081 with the neutron counter at 0 degrees in 41694, and 2.9E+5 neutrons, as the \
         entry has it, against 28778. The stated resolutions differ as for 252-Cf, 3.5 u and \
         about 1 ns against 4 u and 4 ns. The two tables differ by 0.36 neutrons rms over \
         their 73 shared masses, 41720004 lying 4 % lower on average, so one of the two is \
         taken, never both",
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

"""
Entries whose fragment masses the entry itself establishes as provisional — derived from the two
fragment energies without correcting them for neutron emission — keyed by the five-character
entry number, with the evidence.

A dataset of such an entry is rejected under every abscissa that is a pre-neutron mass, whatever
its reaction code says: an observable defined against pre-neutron mass takes only masses that
are pre-neutron, from a ν(A) or ν(A, TKE) correction or from double-velocity kinematics. Every
subentry sharing the entry's mass determination inherits the defect, and on the steep side of
the sawtooth, near A ≈ 130, a shift of about 1 u moves ν(A) visibly. An entry that is silent on
the correction stays admitted.
"""
const PROVISIONAL_MASS_ENTRIES = Dict{String, String}(
    "40232" => "provisional masses: entry 40232 (Zakharova 1973) states that 'corrections on \
                emission of neutrons from fission fragments were not introduced' (40232001, \
                CORRECTION), its masses following from the two fragment energies by \
                conservation of mass and momentum (40232001, ANALYSIS)",
    "40420" => "provisional masses: entry 40420 (Zakharova 1979) names entry 40232 for the 'FY \
                and TKE for this experiment' (40420001, REL-REF), and 40232 states that \
                'corrections on emission of neutrons from fission fragments were not \
                introduced' (40232001, CORRECTION)",
)

"""
    provisional_mass(identifier) -> Union{String,Nothing}

The evidence of [`PROVISIONAL_MASS_ENTRIES`](@ref) for the entry of `identifier`, or `nothing`.
"""
provisional_mass(identifier::AbstractString) =
    get(PROVISIONAL_MASS_ENTRIES, first(identifier, 5), nothing)

"""
    Slice(system, holds, energies, masses, source)

A dataset holding a slice of the joint distribution Y(A, TKE) rather than the distribution: a
yield against mass at a few fixed energies, or TKE distributions for a few masses. It is not
retrieved as Y(A, TKE), since a few slices are not the distribution over the fragmentation
range; the run record of `Y_vs_A_TKE` lists it as available, with its masses and energies, for
cross-checks such as the width of the TKE distribution at those masses.

# Fields
- `system::String`: the fissioning system, as [`system_label`](@ref) writes it.
- `holds::String`: what the slices are.
- `energies::String`, `masses::String`: the energies and masses as the subentry tabulates them.
- `source::String`: the publication and figure.
"""
struct Slice
    system::String
    holds::String
    energies::String
    masses::String
    source::String
end

# Converting the energy of one fragment to the total takes pre-neutron momentum conservation,
# TKE = E_k A_0 / (A_0 - A), and a density in E_k to one in TKE the factor (A_0 - A) / A_0.
const _ONE_FRAGMENT = "yield against mass at fixed kinetic energies of one fragment, pre-neutron; converting \
     to TKE takes TKE = E_k A_0/(A_0 - A), and a density the factor (A_0 - A)/A_0"

"""
Datasets that hold slices of the joint distribution Y(A, TKE), keyed by dataset identifier; see
[`Slice`](@ref).
"""
const SLICE_DATASETS = Dict{String, Slice}(
    "41696002" => Slice(
        "U235_nth",
        _ONE_FRAGMENT * "; event counts",
        "E of the heavy fragment 60.7, 68.2, 79.0 MeV",
        "heavy masses 125.48 to 153.59, 76 digitised values",
        "Baranov 1969, Fig. 1 of YFI-9, p. 20",
    ),
    "40479002" => Slice(
        "U235_nth",
        _ONE_FRAGMENT * "; event counts",
        "E of the light fragment 106.0, 107.3, 108.6, 109.9, 111.2 MeV",
        "heavy masses 126 to 154.5 in 1.5-u steps, 20 values",
        "Zamyatnin 1978, Yad. Fiz. 27, 60",
    ),
    "40479005" => Slice(
        "Pu239_nth",
        _ONE_FRAGMENT * "; event counts",
        "E of the light fragment 105.4, 107.7, 110.0, 112.2, 114.4 MeV",
        "heavy masses 130.5 to 160.5 in 1.5-u steps, 21 values",
        "Zamyatnin 1978, Yad. Fiz. 27, 60",
    ),
    "40479007" => Slice(
        "Cf252_sf",
        _ONE_FRAGMENT * "; event counts",
        "E of the light fragment 125.2, 126.7, 128.3, 129.8, 132.0 MeV",
        "heavy masses 129 to 172.5 in 1.5-u steps, 30 values",
        "Zamyatnin 1978, Yad. Fiz. 27, 60, Fig. 4",
    ),
    "41695006" => Slice(
        "U235_nth",
        "yield against mass at fixed TKE; density per MeV, u and fission",
        "TKE 155.8, 167.2, 176.2, 187.3 MeV",
        "heavy masses 125.08 to 155.69, 78 digitised values",
        "Artem'ev 1970, Yad. Fiz. 11, 290, Fig. 3",
    ),
    "14208004" => Slice(
        "U235_nth",
        "yield against mass in one TKE window; event counts",
        "TKE 145 to 150 MeV (COMMON E-MIN, E-MAX)",
        "masses 67 to 158, 50 values",
        "Derengowski 1970, Phys. Rev. C 2, 1554, Fig. 9",
    ),
    "14208006" => Slice(
        "U235_nth",
        "yield against mass in one TKE window; event counts",
        "TKE 165 to 170 MeV (COMMON E-MIN, E-MAX)",
        "masses 74 to 154, 53 values",
        "Derengowski 1970, Phys. Rev. C 2, 1554, Fig. 9",
    ),
    "14208008" => Slice(
        "U235_nth",
        "yield against mass in one TKE window; event counts",
        "TKE 185 to 190 MeV (COMMON E-MIN, E-MAX)",
        "masses 92 to 138, 28 values",
        "Derengowski 1970, Phys. Rev. C 2, 1554, Fig. 9",
    ),
    "40200006" => Slice(
        "U235_nth",
        "yield against mass in nine TKE windows of 2.5 MeV; event counts",
        "TKE windows from 127.5, 130.0, 132.5, 135.0, 137.5, 167.5, 190.0, 195.0, 197.5 MeV",
        "masses 71.5 to 166 in 1.5-u steps, 64 values",
        "Zakharova 1972, Sov. J. Nucl. Phys. 16, 364, Figs. 8 and 9",
    ),
    "40200005" => Slice(
        "U235_nth",
        "TKE distributions for eight mass bins of about 1.5 u; event counts",
        "TKE 100 to 230 MeV in 2.5-MeV steps",
        "mass bins between 116.5 and 121, 140.5 and 142, 160 and 165",
        "Zakharova 1972, Sov. J. Nucl. Phys. 16, 364, Fig. 6",
    ),
    "21995034" => Slice(
        "Pu239_nth",
        "TKE distribution summed over a mass window; percent per fission and MeV. EN-SEC \
         codes the energy (E,FF), but it runs over the total kinetic energy",
        "TKE 130.79 to 228.71 MeV, 97 digitised values",
        "masses 120 to 130 and 135 to 174 (COMMON MASS-MIN, MASS-MAX)",
        "Wagemans 1984, doi:10.1103/PhysRevC.30.218, Fig. 4b",
    ),
    "21995031" => Slice(
        "Pu240_sf",
        "TKE distribution summed over a mass window; percent per fission and MeV. EN-SEC \
         codes the energy (E,FF), but it runs over the total kinetic energy",
        "TKE 131.82 MeV upwards, 89 digitised values",
        "masses 120 to 130 and 135 to 174 (COMMON MASS-MIN, MASS-MAX)",
        "Wagemans 1984, doi:10.1103/PhysRevC.30.218, Fig. 4a",
    ),
    "21995032" => Slice(
        "Pu240_sf",
        "TKE distribution summed over a mass window; percent per fission and MeV",
        "TKE 143.90 MeV upwards, 70 digitised values",
        "masses 130 to 135 (COMMON MASS-MIN, MASS-MAX)",
        "Wagemans 1984, doi:10.1103/PhysRevC.30.218, Fig. 4a",
    ),
    "21995035" => Slice(
        "Pu239_nth",
        "TKE distribution summed over a mass window; percent per fission and MeV",
        "TKE 139.0 to 221.82 MeV, 80 digitised values",
        "masses 130 to 135 (COMMON MASS-MIN, MASS-MAX)",
        "Wagemans 1984, doi:10.1103/PhysRevC.30.218, Fig. 4b",
    ),
)

"""
    slice_rejection(identifier, abscissa, ordinate) -> Union{String,Nothing}

The reason a dataset of [`SLICE_DATASETS`](@ref) is not the joint yield asked for, or `nothing`
when `identifier` is no slice or the observable is not Y(A, TKE).
"""
function slice_rejection(
    identifier::AbstractString,
    abscissa::AbstractVector{<:AbstractString},
    ordinate::AbstractString,
)
    slice = get(SLICE_DATASETS, identifier, nothing)
    slice === nothing && return nothing
    (String[abscissa...] == ["mass", "total_kinetic_energy"] && ordinate == "yield") ||
        return nothing
    return "a slice of the joint distribution, not the distribution: $(slice.holds); \
            $(slice.energies); $(slice.masses) ($(slice.source)); listed under `slices`"
end

"""The frames a mean neutron energy is recorded in, as `ordinate_frame` of the run record."""
const ORDINATE_FRAME_VALUES = ("centre_of_mass", "laboratory", "unstated")

"""
What a frame reading rests on, as `ordinate_frame_basis` of the run record: the heading of the
datum, the text of the subentry, or the publication the subentry cites.
"""
const FRAME_BASES = ("heading", "subentry", "publication")

"""
    FrameReading(frame, [basis,] evidence)

The frame of the datum of one dataset, with what establishes it.

# Fields
- `frame::String`: one of [`ORDINATE_FRAME_VALUES`](@ref).
- `basis::String`: one of [`FRAME_BASES`](@ref); `"subentry"` when not given. An unstated frame
  carries the basis that was consulted last and left it open.
- `evidence::String`: the heading, the words of the subentry, or the sentence or equation of
  the publication, with its DOI, that the frame is read from; for an unstated frame, what the
  sources do say.

# Throws
- `ArgumentError` for a frame outside [`ORDINATE_FRAME_VALUES`](@ref) or a basis outside
  [`FRAME_BASES`](@ref).
"""
struct FrameReading
    frame::String
    basis::String
    evidence::String
    function FrameReading(
        frame::AbstractString,
        basis::AbstractString,
        evidence::AbstractString,
    )
        frame in ORDINATE_FRAME_VALUES || throw(
            ArgumentError("frame \"$(frame)\" is not one of $(ORDINATE_FRAME_VALUES)"),
        )
        basis in FRAME_BASES ||
            throw(ArgumentError("basis \"$(basis)\" is not one of $(FRAME_BASES)"))
        return new(String(frame), String(basis), String(evidence))
    end
end

FrameReading(frame::AbstractString, evidence::AbstractString) =
    FrameReading(frame, "subentry", evidence)

"""
The frame of mean neutron energies whose subentry heads them `DATA`, keyed by dataset
identifier; see [`FrameReading`](@ref) and [`ordinate_frame`](@ref). The text of the subentry
decides where it names the frame; where it does not, the publication the subentry cites does,
quoted with its DOI, and a dataset whose publication leaves the frame open, or which is absent
from this table, is recorded as unstated.
"""
const ORDINATE_FRAMES = Dict{String, FrameReading}(
    "41502009" => FrameReading(
        "centre_of_mass",
        "the REACTION text reads 'Average prompt neutron energy as dependence from preneutron \
         fragment mass in fragment center of mass system'",
    ),
    "41502010" => FrameReading(
        "centre_of_mass",
        "the REACTION text reads 'Average prompt neutron energy as dependence from preneutron \
         fragment mass in fragment center of mass system'",
    ),
    "23175012" => FrameReading(
        "centre_of_mass",
        "publication",
        "the REACTION text, 'Average fission neutron kinetic energy as function of mass', \
         names no frame. The article does (doi:10.1016/0375-9474(88)90508-8): 'The neutron \
         energy eta in the center-of-mass system of the fragment was evaluated event by \
         event' (section 3.2.3, p. 322), from V_CM^2 = V_F^2 + V_LAB^2 - 2 V_F V_LAB \
         cos(theta_LAB) (Eq. 1), and 'Fig. 17a displays the average energy eta as function \
         of A' (p. 323), the figure the subentry digitises",
    ),
    "14369005" => FrameReading(
        "centre_of_mass",
        "publication",
        "the REACTION text, 'Energy of neutrons emitted with the fragment specified', names \
         no frame. The figure the subentry digitises does: Fig. 5 of Milton and Fraser, \
         Physics and Chemistry of Fission (Salzburg 1965), IAEA STI/PUB/101, vol. 2, p. 47, \
         is captioned 'As in Fig. 4 but for n + U233. The symbol eta is used for E_CM', \
         Fig. 4 giving the 'average centre-of-mass moment <V^2> = <E_CM>/0.5228', and the \
         tables of the paper define E_CM as 'the average energy of the neutrons arising from \
         the fragments in the fragment system' (p. 51). The review the subentry cites first, \
         Annu. Rev. Nucl. Sci. 16, 379 (doi:10.1146/annurev.ns.16.120166.002115), was not \
         obtained",
    ),
    "41689005" => FrameReading(
        "centre_of_mass",
        "publication",
        "the REACTION record carries no text. The authors' paper of the same title and data \
         at the Kiev conference of 1975 (Neitronnaya Fizika, part 5, p. 92, Moscow 1976, \
         INDC(CCP)-99) captions the figure of these points, its Fig. 4, 'Mean energy of the \
         neutrons in the c.m.s. as a function of fragment mass' ('Srednyaya energiya \
         neitronov v s.ts.i. v zavisimosti ot massy oskolka'), the c.m.s. being 'the frame \
         of the moving fragment' (p. 97), and plots the component isotropic in the \
         laboratory apart; its formula for the mean (p. 100) weights that component in, \
         and the authors put about 10 % on the mean for the unknown division of it between \
         the fragments (p. 107). The article the subentry cites, Yad. Fiz. 25, 723 (1977), \
         has no DOI and was not obtained",
    ),
    "22660004" => FrameReading(
        "centre_of_mass",
        "publication",
        "the REACTION text, 'Average Neutron Energy as a function of fragment mass and total \
         kinetic energy of fragments', names no frame. The figure the subentry tabulates \
         does: Fig. 5 of Nishio 1998 (doi:10.1080/18811248.1998.9733919, p. 635) is \
         captioned 'Average neutron energy in the center-of-mass system as a function of \
         total kinetic energy', the neutron energy having been 'transformed to the c.m. \
         system of the respective fragment ... using the fragment velocity and the neutron \
         emission angle' (p. 634)",
    ),
)

"""
    ordinate_frame(identifier, headings) -> FrameReading

The frame of the datum of a dataset of [`CENTRE_OF_MASS_ORDINATES`](@ref) whose DATA table
carries `headings`: the centre of mass where the datum is headed
[`CENTRE_OF_MASS_DATUM`](@ref), else the reading of [`ORDINATE_FRAMES`](@ref), else unstated.
"""
function ordinate_frame(
    identifier::AbstractString,
    headings::AbstractVector{<:AbstractString},
)
    CENTRE_OF_MASS_DATUM in headings && return FrameReading(
        "centre_of_mass",
        "heading",
        "the subentry heads the value $(CENTRE_OF_MASS_DATUM)",
    )
    return get(
        ORDINATE_FRAMES,
        String(identifier),
        FrameReading(
            "unstated",
            "the subentry heads the value DATA, and no reading of its text for the frame is \
             recorded",
        ),
    )
end

"""
How a tabulated mean neutron energy was formed, as `mean_formed_from` of the run record: the
first moment of the measured centre-of-mass spectrum, the first moment of a form fitted to it,
that of the measured spectrum completed beyond its range by a fitted form, or not stated by the
publication consulted.
"""
const MEAN_SOURCES =
    ("measured_spectrum", "fitted_spectrum", "completed_spectrum", "unstated")

"""
    MeanFormation(from, form, threshold, threshold_frame, evidence)

How the mean neutron energy of one dataset was formed, as its publication states it.

# Fields
- `from::String`: one of [`MEAN_SOURCES`](@ref).
- `form::String`: the fitted form the mean is the first moment of, or the form a measured
  spectrum was completed with and where; empty where none.
- `threshold::Union{Nothing,Float64}`: the low-energy limit of the neutrons that enter the
  mean, in MeV, where the publication states one: the threshold of the neutron detector, or the
  lower limit of the spectrum averaged.
- `threshold_frame::String`: the frame the threshold is stated in, `"laboratory"` for a detector
  threshold or `"centre_of_mass"` for a limit of the spectrum; empty without a threshold.
- `evidence::String`: the sentence or equation, with the DOI.

# Throws
- `ArgumentError` for a source outside [`MEAN_SOURCES`](@ref).
"""
struct MeanFormation
    from::String
    form::String
    threshold::Union{Nothing, Float64}
    threshold_frame::String
    evidence::String
    function MeanFormation(from, form, threshold, threshold_frame, evidence)
        from in MEAN_SOURCES ||
            throw(ArgumentError("mean source \"$(from)\" is not one of $(MEAN_SOURCES)"))
        return new(from, form, threshold, threshold_frame, evidence)
    end
end

"""
    mean_formation(identifier) -> MeanFormation

The reading of [`MEAN_FORMATIONS`](@ref) for a dataset, or an unstated one where no publication
has been read for it.
"""
mean_formation(identifier::AbstractString) = get(
    MEAN_FORMATIONS,
    String(identifier),
    MeanFormation(
        "unstated",
        "",
        nothing,
        "",
        "no reading of the publication for how the mean was formed is recorded",
    ),
)

"""
    mean_formation_record(identifier) -> Dict{String,Any}

The entries [`mean_formation`](@ref) adds to the run record of a mean neutron energy:
`mean_formed_from`, `mean_evidence`, and where they apply `mean_fitted_form`,
`mean_threshold_mev` and `mean_threshold_frame`.
"""
function mean_formation_record(identifier::AbstractString)
    formation = mean_formation(identifier)
    record = Dict{String, Any}(
        "mean_formed_from" => formation.from,
        "mean_evidence" => formation.evidence,
    )
    isempty(formation.form) || (record["mean_fitted_form"] = formation.form)
    if formation.threshold !== nothing
        record["mean_threshold_mev"] = formation.threshold
        record["mean_threshold_frame"] = formation.threshold_frame
    end
    return record
end

const _BOWMAN_MEAN = MeanFormation(
    "measured_spectrum",
    "",
    0.52,
    "laboratory",
    "Bowman 1963 (doi:10.1103/PhysRev.129.2133): the multiplicity and the mean energy 'may be \
     regarded as the zeroth and second moments of the velocity spectrum of the emitted \
     neutrons' (p. 2134), formed by sums 'carried out, event by event, over all events' of \
     the counters at 11.25 and 168.75 degrees (Appendix A, p. 2145), with no fitted form. \
     'At no time are velocities less than 1 cm/nsec used' (Appendix B, p. 2146), 0.52 MeV \
     in the laboratory; the fraction of the centre-of-mass spectrum missed is put at \
     0.16 %, and the mean is not corrected for it",
)

const _BATENKOV_MEAN = MeanFormation(
    "unstated",
    "",
    0.2,
    "laboratory",
    "Batenkov 2004 (doi:10.1063/1.1945175) names 'the mean neutron multiplicity <nu> and mean \
     energy in the fragment center of mass system <epsilon>' (p. 1004) and shows 'the mass \
     dependence of the mean neutron energy, <epsilon(m*)>' in Fig. 7 (p. 1006) without saying \
     how the mean was formed; the results are called preliminary. The Maxwell shape entry \
     41502 mentions is assumed for the ratios of the total laboratory spectra to that of \
     252-Cf (p. 1005), not for the mean. 'The experimental neutron registration threshold \
     was about 200 keV' (p. 1004), and the detection efficiency is 'the ratio of the measured \
     252Cf spectrum to a reference standard spectrum', that of Mannhart, from a run on the \
     same set-up (p. 1004)",
)

const _CASCADE_FORM = "const eta^lambda exp(-eta/T)"

"""
How the mean neutron energy of each dataset was formed, keyed by dataset identifier and read
from its publication; see [`MeanFormation`](@ref). A threshold is recorded only from a
publication read, in the frame it is stated in: what the EXFOR entry alone says of one is quoted
in the evidence, entry 22660 giving 0.2 MeV where its article prints 0.3 MeV.
"""
const MEAN_FORMATIONS = Dict{String, MeanFormation}(
    "14065003" => _BOWMAN_MEAN,
    "14065010" => _BOWMAN_MEAN,
    "23175012" => MeanFormation(
        "fitted_spectrum",
        _CASCADE_FORM,
        0.3,
        "laboratory",
        "the tabulated mean equals (lambda + 1) T of the form fitted to the centre-of-mass \
         spectrum, with the T and lambda of the MISC columns, to 0.4 % rms and 1.1 % at most \
         over the 79 masses: the first moment of that form. The article \
         (doi:10.1016/0375-9474(88)90508-8) does not say how the mean was formed: 'The \
         neutron spectrum belonging to each mass A was evaluated and T(A) and lambda(A) were \
         determined using eq. (8). Fig. 17a displays the average energy eta as function of \
         A' (p. 323); a maximum-likelihood fit of that form has the mean of the measured \
         spectrum as its first moment, so the two readings may coincide. 'The applied \
         neutron detector threshold of 0.3 MeV did therefore insure that all wanted neutrons \
         were taken into account' (p. 315), only neutrons emitted forward in the centre of \
         mass being used",
    ),
    "23268011" => MeanFormation(
        "unstated",
        "",
        0.7,
        "laboratory",
        "Goeoek 2014 (doi:10.1103/PhysRevC.90.064611) does not say how the mean of Fig. 18a \
         was formed: the spectra 'were evaluated by using Eq. (14); the result is displayed \
         in Fig. 18, together with the average neutron energy in the center-of-mass frame' \
         (pp. 064611-11, 12). For the spectrum of all fragments the average quoted, 1.45 MeV, is \
         not the first moment (lambda + 1) T_eff = 1.52 MeV of its fit, T_eff = 1.07 and \
         lambda = 0.42. 'A pulse-height threshold corresponding to 0.7 MeV proton-recoil \
         energy (about 100 keVee) was applied' (p. 064611-4), and only neutrons with \
         v_L >= v_F / cos(theta_L), emitted forward in the centre of mass, are used \
         (Eq. 10)",
    ),
    "41689005" => MeanFormation(
        "completed_spectrum",
        "sqrt(eta) exp(-eta/T) above 1.5 MeV",
        0.4,
        "laboratory",
        "the authors' paper of the same title and data at the Kiev conference of 1975 \
         (Neitronnaya Fizika, part 5, p. 92, Moscow 1976): the limited statistics 'did not \
         allow spectra in the c.m.s. to be obtained' above 1.5 MeV, so 'the spectra were \
         completed artificially on the assumption that the energy distribution of the \
         neutrons in the c.m.s. is described by the Maxwell formula', its parameter T \
         'determined by least squares on the measured part of the spectrum' (p. 98, in \
         translation); the estimator of the mean itself is not spelled out. The detector \
         threshold is given as a neutron energy of about 400 keV (p. 95). The article, \
         Yad. Fiz. 25, 723 (1977), was not obtained",
    ),
    "22464003" => MeanFormation(
        "unstated",
        "",
        0.2,
        "laboratory",
        "Nishio 1998 (doi:10.1016/S0375-9474(98)00008-6) fits the centre-of-mass spectra \
         with const sqrt(eta) exp(-eta/T_eff) and says only that 'the mean values of the \
         neutron energy, <eta>, are plotted as a function of fragment mass in the upper part \
         of Fig. 4' (p. 545), not how they were formed. 'The neutron threshold level of the \
         detector was set at 0.2 MeV' (p. 542)",
    ),
    "41502008" => _BATENKOV_MEAN,
    "41502009" => _BATENKOV_MEAN,
    "23444006" => MeanFormation(
        "unstated",
        "",
        nothing,
        "",
        "Goeoek 2018 (doi:10.1103/PhysRevC.98.044615) gives 'the average c.m. neutron energy \
         as a function of the fission fragment mass' in Fig. 11 (p. 044615-8) without \
         saying how it was formed; 'the neutron energy eta in the c.m. system has been \
         evaluated on an event-by-event basis' (p. 044615-6). Pulse-height thresholds \
         depending on the time of flight are applied, with no value stated, and neutrons \
         emitted backward in the centre of mass are left out",
    ),
    "22650008" => MeanFormation(
        "measured_spectrum",
        "",
        0.5,
        "centre_of_mass",
        "Tsuchiya 2000 (doi:10.1080/18811248.2000.9714976): for a Maxwellian 'the average \
         neutron energy <eta> is given by 3 T_eff / 2. However we do not use this value but \
         the average value of all experimental points above 0.5 MeV, because the measured \
         neutron spectrum data exceed the Maxwellian above 3 MeV' (p. 944), the points being \
         those of the spectrum in the centre-of-mass system. 'The neutron threshold level of \
         the detector was set at 0.2 MeV' (p. 942)",
    ),
    "14369005" => MeanFormation(
        "measured_spectrum",
        "",
        nothing,
        "",
        "Milton and Fraser, Physics and Chemistry of Fission (Salzburg 1965), IAEA \
         STI/PUB/101, vol. 2, p. 39: 'the four velocity moments ... in both the laboratory \
         and centre-of-mass co-ordinate systems are then calculated', each event 'sorted, \
         with its proper weight' (p. 44), and the mean energy is E_CM = 0.5228 <V^2> from \
         the data of the counter at 10 degrees (Fig. 4, p. 46), with no fitted form. The \
         efficiency of the neutron detector 'goes to zero at about 200 keV' and 0.52 to \
         13.1 MeV are 'limits of the useful energy range' of the 235-U runs (pp. 41, 42); \
         the conditions 'were considerably different during the U233 runs' (p. 55) and \
         their limits are not given. The results are called provisional (p. 44)",
    ),
    "22660003" => MeanFormation(
        "measured_spectrum",
        "",
        0.3,
        "laboratory",
        "Nishio 1998 (doi:10.1080/18811248.1998.9733919): the centre-of-mass spectra exceed \
         the fitted Maxwellian above 3 MeV, and 'the mean values of the neutron energy, \
         eta, calculated from the experimental data are plotted as a function of fragment \
         mass in Fig. 4' (p. 634). 'The neutron bias level was set at 0.3 MeV' (p. 632), \
         where entry 22660 gives 0.2 MeV, and only events with V_n > V_FF1 / cos(theta), \
         emitted forward in the centre of mass, enter the spectrum (p. 634)",
    ),
    "22660004" => MeanFormation(
        "unstated",
        "",
        0.3,
        "laboratory",
        "Nishio 1998 (doi:10.1080/18811248.1998.9733919) shows 'the dependence of average \
         neutron energy on TKE for the specified fragment' in Fig. 5, with a mass gate of \
         4 u (p. 636), under the symbol of the means of Fig. 4, which are 'calculated from \
         the experimental data' (p. 634), without saying so of Fig. 5. 'The neutron bias \
         level was set at 0.3 MeV' (p. 632), where entry 22660 gives 0.2 MeV",
    ),
)

"""
The form fitted to the centre-of-mass spectrum of the datasets whose fit parameters a
configuration may name ([`PARAMETER_ORDINATES`](@ref)), keyed by dataset identifier, as the
form and the equation of the publication it is from. Written to the run record of a parameter
as `fit_form` and `fit_evidence`.
"""
const SPECTRUM_FITS = Dict{String, Tuple{String, String}}(
    "23175012" => (
        _CASCADE_FORM,
        "Eq. (8) of Nucl. Phys. A 490, 307 (doi:10.1016/0375-9474(88)90508-8, p. 323), the \
         cascade evaporation spectrum of Le Couteur and Lang, whose 'parameters lambda, T \
         ... were then treated by us as free parameters to be determined from the \
         experimental eta-distributions', and 'T(A) and lambda(A) were determined using \
         eq. (8)'. The subentry calls the same form, const AKE^lambda exp(-AKE/T), a \
         Weisskopf spectrum; MISC1 holds T and MISC2 lambda, digitised from Fig. 17 b and c",
    ),
    "23268011" => (
        "const eta^lambda exp(-eta/T_eff)",
        "Eq. (14) of Goeoek 2014 (doi:10.1103/PhysRevC.90.064611, p. 064611-7), 'the \
         expression for cascade neutron emission', 'where eta is the center-of-mass neutron \
         energy while lambda and T_eff are fit parameters'; the spectra of each mass 'were \
         evaluated by using Eq. (14)', and MISC holds the temperature of Fig. 18b. The \
         lambda of Fig. 18c is not in the archive",
    ),
)

"""
Entries the archive marks preliminary, with the code PRELM under `STATUS` in their common
subentry, keyed by the five-character entry number, with the evidence: the code and what stands
beside it, and the words of the publication where it has been read. The code decides; a
publication adds its sentence and never gates. Every accepted dataset of such an entry carries
the qualifier [`preliminary_qualifier`](@ref) among its `qualifiers`, and the run record names
them in `preliminary_warning`; none is refused for it. See [`PRELIMINARY_SUBENTRIES`](@ref) for
the code in a subentry of its own.
"""
const PRELIMINARY_ENTRIES = Dict{String, String}(
    "41502" => "Batenkov 2004 (doi:10.1063/1.1945175) presents 'some preliminary results of \
                the average number and kinetic energies of prompt neutrons as a function \
                fragment mass' (abstract, p. 1003), and the entry carries STATUS PRELM",
    "41516" => "the entry carries STATUS (PRELM), 'Data are preliminary.'",
)

"""
Subentries that carry PRELM under their own `STATUS`, keyed by the eight-character subentry
number, with the code and what stands beside it. Every dataset of such a subentry is flagged
as those of [`PRELIMINARY_ENTRIES`](@ref) are.
"""
const PRELIMINARY_SUBENTRIES = Dict{String, String}(
    "40644003" => "its subentry carries STATUS (PRELM), beside (OUTDT,40644002) and \
                   (SPSDD,40644002)",
    "41516012" => "its subentry carries STATUS (PRELM), 'Data are presented on Fig.7 left of \
                   S,ISINN-17,60,2010, Fig.5 left of J,EPJ/CS,8,03004,2010.'",
    "41738004" => "its subentry carries STATUS (PRELM), beside (TABLE), 'Data from author \
                   Sh.Zeynalov. Data are presented on Fig.7 of Eur.Phys.J. Conf.Ser.,v.146,\
                   p.04022,2017'",
)

"""
    preliminary_qualifier(identifier) -> Union{String,Nothing}

The qualifier of a dataset whose entry is among [`PRELIMINARY_ENTRIES`](@ref) or whose subentry
is among [`PRELIMINARY_SUBENTRIES`](@ref), `preliminary:` followed by the evidence of the entry
and that of the subentry, or `nothing`.
"""
function preliminary_qualifier(identifier::AbstractString)
    evidence = String[]
    for (table, width) in ((PRELIMINARY_ENTRIES, 5), (PRELIMINARY_SUBENTRIES, 8))
        found = get(table, first(identifier, width), nothing)
        found === nothing || push!(evidence, found)
    end
    return isempty(evidence) ? nothing : "preliminary: " * join(evidence, "; ")
end

"""
Datasets whose subentry marks them superseded, under `STATUS` with the code `SPSDD`, keyed by
the dataset identifier, with the accession the code names as superseding them, `by`, and any
other code of the same `STATUS` that bears on the standing of the dataset, `beside`. Each is
written,
carries [`superseded_qualifier`](@ref) among its `qualifiers`, and is named in
`superseded_warning`; none is refused for it. A superseded dataset and the one that supersedes
it are one measurement and share one of the [`CORRELATION_GROUPS`](@ref), whose
`correlated_with` reads alike on both; the qualifier says which of the two the authors withdrew.
"""
const SUPERSEDED_DATASETS = Dict{String, @NamedTuple{by::String, beside::String}}(
    "30046007" => (by = "30772009", beside = ""),
    "30046008" => (by = "30772010", beside = ""),
    "30046009" => (by = "30772011", beside = ""),
    "40418006" => (by = "40418008", beside = ""),
    "40644003" => (by = "40644002", beside = "(PRELM) and (OUTDT,40644002)"),
    "40875002" => (by = "41158002", beside = ""),
    "40875003" => (by = "41158003", beside = ""),
    "41516017" => (by = "41597002", beside = ""),
)

"""
    superseded_qualifier(identifier) -> Union{String,Nothing}

The qualifier of a dataset among [`SUPERSEDED_DATASETS`](@ref), `superseded: by` followed by the
accession that supersedes it and the `STATUS` code of its subentry that says so, or `nothing`.
"""
function superseded_qualifier(identifier::AbstractString)
    superseded = get(SUPERSEDED_DATASETS, identifier, nothing)
    superseded === nothing && return nothing
    qualifier = "superseded: by $(superseded.by), as the STATUS of its subentry states \
                 (SPSDD,$(superseded.by))"
    return isempty(superseded.beside) ? qualifier :
           "$(qualifier), beside $(superseded.beside)"
end

"""
The qualifier written among the `qualifiers` of a dataset whose [`ordinate_frame`](@ref) is
unstated, so that a reader of the reaction-code flags meets it there.
"""
const FRAME_UNSTATED_QUALIFIER = "frame unstated: the subentry does not say that the neutron \
    energy is in the centre-of-mass frame of the fragment"

"""
The heading under which a subentry gives the temperature of the Maxwellian a spectrum is
divided by, `KT-NRM` (EXFOR Dictionary 24).
"""
const MAXWELLIAN_TEMPERATURE_HEADING = "KT-NRM"

"""
    MaxwellianTemperature(temperature, source)

The temperature of the Maxwellian a spectrum ratio was formed with.

# Fields
- `temperature::Float64`: in MeV.
- `source::String`: where the subentry gives it.
"""
struct MaxwellianTemperature
    temperature::Float64
    source::String
end

"""
Datasets whose `KT-NRM` holds the mean energy of the Maxwellian, 3T/2, and not its temperature,
keyed by dataset identifier, as `(mean_energy, evidence)` with the mean energy in MeV as the
archive gives it. The temperature recorded is two thirds of it. An archive value that no longer
equals `mean_energy` refuses the dataset until the reading is reviewed.
"""
const MAXWELLIAN_MEAN_ENERGIES = Dict{String, Tuple{Float64, String}}(
    "14278003" => (
        2.159,
        "the ANALYSIS text reads 'ratio of the experimental spectrum to a Maxwellian \
         distribution with the same average energy of 2.159 MeV', and KT-NRM holds that \
         2.159 MeV: the mean energy 3T/2, so that T = 1.439 MeV",
    ),
)

"""
    maxwellian_temperature(identifier, subentry, data)
        -> Union{MaxwellianTemperature,String}

The temperature of the Maxwellian the spectrum ratio of one dataset was formed with, or the
reason the subentry does not give one.

It is read from the column [`MAXWELLIAN_TEMPERATURE_HEADING`](@ref): of the COMMON section of
the subentry, else of the COMMON section of the entry, else of the DATA table `data`, the
retained lines, where it must hold one value. The unit must be an energy
[`energy_factor`](@ref) converts. A dataset of [`MAXWELLIAN_MEAN_ENERGIES`](@ref) holds the
mean energy there, and its temperature is two thirds of it.
"""
function maxwellian_temperature(
    identifier::AbstractString,
    subentry::Subentry,
    data::SubentryColumns,
)
    heading = MAXWELLIAN_TEMPERATURE_HEADING
    places = (
        (subentry.common, "the COMMON section of the subentry"),
        (subentry.entry_common, "the COMMON section of subentry 001"),
        (data, "the DATA table"),
    )
    for (columns, place) in places
        index = column(columns, heading)
        index === nothing && continue
        values = unique(skipmissing(columns.values[index]))
        length(values) == 1 ||
            return "$(heading) in $(place) holds $(length(values)) values \
            over the retained lines, so the ratio is not formed with one Maxwellian"
        unit = columns.units[index]
        factor = energy_factor(unit)
        factor === nothing &&
            return "$(heading) in $(place) is headed $(unit), which is not \
            an energy unit this package converts"
        value = only(values) * factor
        mean_energy = get(MAXWELLIAN_MEAN_ENERGIES, String(identifier), nothing)
        if mean_energy === nothing
            value > 0 ||
                return "$(heading) in $(place) is $(value) MeV, which is no temperature"
            return MaxwellianTemperature(value, "$(heading) in $(place)")
        end
        expected, evidence = mean_energy
        isapprox(value, expected; rtol = 1.0e-6) ||
            return "$(heading) in $(place) is $(value) MeV where the recorded reading of it \
                    as a mean energy expects $(expected) MeV; the archive may have corrected \
                    it, and the reading must be reviewed"
        return MaxwellianTemperature(
            round(2 * value / 3; sigdigits = 4),
            "two thirds of $(heading) in $(place): " * evidence,
        )
    end
    return "the subentry gives no temperature of the Maxwellian the ratio was formed with \
            ($(heading)), without which the ratio states no spectrum"
end

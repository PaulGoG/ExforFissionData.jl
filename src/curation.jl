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
    PairSum(deviation, uncertainty, yields, own_yields)

The scale of a prompt multiplicity tabulated against fragment mass on both sides of symmetry,
from its pair sum S = ν(A) + ν(A₀ − A) weighted with the light-fragment yield. It is recorded
beside the reading and never decides it.

# Fields
- `deviation::Float64`: S/(kν̄) − 1, with k = 1 for a multiplicity per fragment and 2 per fission.
- `uncertainty::Float64`: the standard deviation of `deviation`, from those of S and ν̄; `NaN`
  where the dataset states no uncertainty.
- `yields::String`: the dataset identifier of the Y(A) that S is weighted with.
- `own_yields::Bool`: whether that Y(A) is of the same experiment; otherwise it is the fallback
  for the system.
"""
struct PairSum
    deviation::Float64
    uncertainty::Float64
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
        ComplementReading("data+paper", PairSum(-0.0004, 0.0043, "23268003", true)),
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
        ComplementReading("data+paper", PairSum(0.0023, 0.0072, "23118002", true)),
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
        ComplementReading("data+paper", PairSum(-0.0198, 0.0498, "23175002", true)),
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
        ComplementReading("data+paper", PairSum(0.0, 0.0091, "21834002", true)),
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
        ComplementReading("data+paper", PairSum(0.0366, 0.0145, "21834003", true)),
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
        ComplementReading("data", PairSum(0.0480, 0.0192, "23268003", false)),
    ),
    "41502005" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, AIP \
         Conf. Proc. 769, 1003 (2005, doi:10.1063/1.1945175), was not consulted. Over 10 pairs \
         (A, A_0 - A) of its 4-u grid, A_0 = 236, nu(A) - nu(A_0 - A) changes sign along the \
         sawtooth and reaches 2.72, a median 7 times its uncertainty, chi2 per pair 105 against \
         zero; the pair sum weighted with the yield of 21981006, the 235-U fallback, the entry \
         having no Y(A), is 2.469 +- 0.034 against 2.425 +- 0.011, the $(_NUBAR), 1.8 % above it",
        ComplementReading("data", PairSum(0.0182, 0.0148, "21981006", false)),
    ),
    "41502007" => Curation(
        "multiplicity",
        "curated: per fragment, though coded without FRG, by the data alone; the publication, AIP \
         Conf. Proc. 769, 1003 (2005, doi:10.1063/1.1945175), was not consulted. In the 0.296 eV \
         resonance, over 9 pairs (A, A_0 - A) of its 4-u grid, A_0 = 240, nu(A) - nu(A_0 - A) \
         changes sign along the sawtooth and reaches 2.74, chi2 per pair 14 against zero; the pair \
         sum weighted with the yield of 21981007, the 239-Pu fallback, the entry having no Y(A), \
         is 2.82 +- 0.10 against the thermal 2.878 +- 0.013, the $(_NUBAR), 2.0 % below it",
        ComplementReading("data", PairSum(-0.0201, 0.0367, "21981007", false)),
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
        ComplementReading("data", PairSum(-0.0069, NaN, "23268003", false)),
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
         yield of 21981007",
        ComplementReading("data", PairSum(0.0387, 0.0061, "22650002", true)),
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
        ComplementReading("data", PairSum(-0.1071, 0.0133, "21981007", false)),
    ),
    # Per fission, as coded.
    "22660006" => Curation(
        "multiplicity_per_fission",
        "curated: per fission, as coded. nu(A) = nu(A_0 - A) at all 42 pairs (A, A_0 - A), A_0 = \
         234, and nu(A) is the pair sum of the per-fragment 22660005 of the same entry at all 85 \
         masses; the pair sum weighted with the yield of 21981005, the 233-U fallback, the entry \
         having no Y(A), is 5.029 +- 0.006, 1.1 % above twice 2.487 +- 0.011, the $(_NUBAR)",
        ComplementReading("data", PairSum(0.0110, 0.0046, "21981005", false)),
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

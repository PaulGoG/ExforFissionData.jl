```@meta
CurrentModule = ExforFissionData
```

# Conventions and selection

**Energies are restated in MeV** — both an energy abscissa and an ordinate that is itself an
energy. These are exact conversions of a value with the factor recorded in the run record, which
is a different thing from a normalisation.

**Values carry seven significant digits**, set by `significant_digits` under `[output]`.
Significant digits rather than decimal places, because the ordinates span many orders of
magnitude: an absolute prompt fission neutron spectrum is of order 10⁻⁷ PC/FIS/MEV, which seven
decimal places would reduce to one significant digit and eight would erase.

**No normalisation is applied to ordinates.** Normalisation conventions differ between consumers
and cannot be undone once applied, so the unit token of each dataset is recorded in the run record
instead. A query returning more than one unit token is flagged: such datasets must not be
renormalised together.

**No point is dropped on the basis of its value or uncertainty.** Quality cuts belong with the
project that can justify them. Values in the far-asymmetric mass tails are statistically poor and
are written unchanged, with their uncertainties.

**The uncertainty column is omitted** when no row of a dataset carries one, rather than written
as a column of zeros. **A missing uncertainty is `NaN`, never zero.** Where some rows of a
dataset carry an uncertainty and others leave it blank — `41397004` (Apalin 1965) has it on 22 of
its 52 lines — a row without one is written `NaN`, and so is a row interpolated next to such a
row, or combined only from such rows; a zero is written only where EXFOR states one, as the empty
cells of `23268002` do. The run record counts, per dataset, the lines stating a zero uncertainty
as `uncertainty_zero_rows` and those stating none as `uncertainty_absent_rows`. Where the csv rendering carries no uncertainty at all but the subentry does,
in `DATA-ERR`, `ERR-T` or `ERR-S` in that order, it is read from the subentry and put on the scale
of the csv ordinate; `uncertainty_source` in the run record says which (`23268002` gives `ERR-S`
on each of its 30 000 cells, and the rendering on none).

**One row per abscissa value.** Several things put more than one row on an abscissa value, and
they are not handled alike:

| Cause | Treatment |
| :--- | :--- |
| several incident energies | the configured window selects rows; a dataset still holding more than one energy inside it is rejected, naming them, rather than averaged |
| another independent variable of the subentry DATA table — a kinetic-energy gate, an angle | rejected where the variable varies: a mean over gates is not the observable asked for. One held at a single value is a condition of the measurement and passes |
| isomeric states | the archive's own total where it gives one, otherwise the resolved states summed with uncertainties in quadrature |
| anything left | inverse-variance weighted mean, uncertainty `1/√(Σ1/σ²)`, counted per dataset as `abscissae_combined` and named in a warning |

The abscissa and the test for other variables come from the **subentry DATA table**, not from the
`op=csv` rendering. The rendering reports a mass as an integer by truncation, 63.51 and 64.91 as
63 and 64, and drops the independent variables it does not recognise; it still supplies the
ordinate, its uncertainty, the unit and the incident energy. The two are aligned row by row, the
truncated product against the subentry's `MASS` and `ELEM` and the secondary energy against its
`E` or `TKE`, and a dataset on which they disagree is rejected.

Masses are written as integers and are never rounded to become so; `mass_treatment` in the run
record says which of three cases applied.

- **Integer masses** are written as the subentry gives them.
- **A bin with integer edges**, `MASS-MIN` to `MASS-MAX` such as 126–127, holds each integer mass
  from one edge to the other. The value of a mean — a kinetic energy, a multiplicity — holds for
  every mass of its bin and is written at each with its own uncertainty, which the repetition
  does not reduce; the widths are recorded as `mass_bin_widths_u`. Only bins of at most 2 u are
  placed: a wider bin averages over a part of the sawtooth where ν(A) changes by more than a
  neutron, and repeated at each mass it would put flat steps into the curve. A yield over several masses is
  their sum and holds for none of them, so it is not written (`10865003` gives the yield of
  masses 135 and 136 together). Bins that share or split an edge mass leave open which bin it
  belongs to and are not placed.
- **Non-integer masses** — a digitised curve, a half-integer grid — are interpolated linearly onto
  the integer masses within their range, separately at each value of any other abscissa quantity.
  The uncertainty is interpolated like the value, as for fully correlated neighbours, so an
  interpolated point is never more precise than the two it lies between; where either neighbour
  has none, the interpolated uncertainty is `NaN`. Nothing is interpolated
  across more than `mass_interpolation_span_u` = 3 u: measured tabulations sample the mass at
  up to 2.5 u, and a wider interval is a gap in the measurement, such as the unmeasured
  symmetric region between two branches. The integer masses in such gaps are counted as
  `mass_gaps_skipped`.

Energies from a `-MIN`, `-MAX` pair contribute the midpoint of the bin, recorded as
`abscissa_binned`.

Rows that still share an abscissa value are either genuine repetition — a chain yield measured
through several nuclides of one mass — or one measurement under different auxiliary conditions.
They are combined, and `combined_over` in the run record names the auxiliary columns of the
subentry, a flight path or a flag, that varied among them. The subentry stored beside the data is
the reference.

## Selection

Datasets are chosen by the codes of their EXFOR reaction code — for instance
`92-U-233(N,F)ELEM/MASS,CUM,FY`. The code is read into its subfields, product (SF4), branch
(SF5), parameter (SF6), particle (SF7), modifier (SF8) and data type (SF9), each split at its
`/` separators, and every test compares a whole code in a named subfield: `DE`, the energy
differential of SF6, is never read inside the data type `DERIV`, nor `KE` inside `KEP`, the most
probable value, or inside `TKE`. `AKE`, the older coding of the mean kinetic energy, is accepted
wherever `KE` is. A combination of several reactions — a ratio, sum or difference — is never the
quantity itself and is rejected, with one exception: under `spectrum_cf252_ratio`, the ratio of
the spectrum of the system and that of 252-Cf(sf) is the quantity, and is admitted where each of
its two reactions satisfies the rule of `spectrum` ([`spectrum_ratio`](@ref)). Which codes each observable requires and forbids is still
empirical, since the archive applies its own vocabulary inconsistently: the tables in
`src/reaction_codes.jl` encode observed failures of the upstream labelling. A rule that looks
redundant usually guards a real entry.

Where no code can tell two datasets apart, a dataset is read from its subentry text one at a time
(`src/curation.jl`), and the run record carries the evidence as `curation`. An observable against
pre-neutron mass takes only pre-neutron masses: an entry that states its masses were not
corrected for neutron emission has every dataset against such a mass rejected, with the
subentry that states it as the reason — entries 40232 and 40420 (Zakharova 1973 and 1979), whose
ν(A) and ν(A, TKE) share that mass determination. A blank branch field
is decided kinematically: a double-velocity measurement gives pre-neutron masses and energies
directly, since isotropic neutron emission leaves the mean fragment velocity unchanged, while a
double-energy measurement gives provisional masses until they are corrected with ν(A), and is
admitted only where its entry states that correction.

The checks easiest to get wrong:

- the `y:Value` column marks **upper limits** with a `Max(` prefix; those rows are bounds, not
  measurements;
- it also marks **arbitrary units** as `ARB-UNITS`, which carry no scale and cannot be combined
  with absolute data. The subentry's own unit decides where the two differ: `23268002` is counts
  in `ARB-UNITS` in its subentry and `PART/FIS` in the rendering;
- a **multiplicity headed `PC/FIS`** is the multiplicity under a miscoded unit, since a count of
  neutrons per fission is of order one and never a percentage. The rendering follows the token
  and divides the values by 100; they are written as the subentry tabulates them, with
  `unit_reported = "PC/FIS"` and the reading stated as `unit_miscoded`, and only where one factor
  relates the rendering to the subentry on every line. `22650004` (Tsuchiya 2000) is the one
  dataset this concerns among the shipped configurations;
- the incident-energy window is applied **per row**, not to the dataset as a whole. An EXFOR
  dataset frequently reports one product at several energies, and admitting all of them collapses
  an excitation function into a single number;
- what a dataset is tabulated against is read from its **subentry DATA table**, which is
  aligned with the csv rendering row by row — the truncated product against `MASS` and `ELEM`,
  the secondary energy against `E` or `TKE` — and a dataset on which the two disagree is
  rejected. For the mean neutron energy the value itself is compared with `DATA-CM`, to a
  relative 10⁻⁵;
- a heading of the subentry DATA table that the EXFOR format classes as an independent variable,
  other than the abscissa's own and the incident energy, **must not vary**. `23591005` (Straede,
  1987) is a mass yield at nine fragment kinetic energies, and projected onto mass it is nine
  yields per mass number. `23268002`, whose `TKE` column the csv rendering drops, is rejected from
  `Cf252_sf_Y_vs_A` on the same rule;
- a spectrum whose energies are in the centre-of-mass frame, `E-CM`, is not a laboratory
  spectrum and is rejected. The mean neutron energy is the one ordinate read from `DATA-CM`, and
  its frame is read from that heading, from the text of the subentry, or from the publication
  the subentry cites, and recorded per dataset as `ordinate_frame` with `ordinate_frame_basis`;
- a **mean neutron energy above 5 MeV** on any row is no mean neutron energy: `23164022`
  (Al-Adili 2016), coded `KE,N`, holds fragment kinetic energies of 43.6 to 101.9 MeV and is
  refused on that bound ([`MAXIMUM_NEUTRON_KINETIC_ENERGY`](@ref));
- a **ratio to a Maxwellian** must state the temperature it was formed with, in `KT-NRM`, and is
  refused without it; `14278003` (Poenitz 1982) holds the mean energy 3T/2 there, and T is
  recorded as two thirds of it;
- a **distribution P(ν)** is tabulated in its subentry against `PART-OUT`, which the csv
  rendering does not carry, so the rows of the two are aligned by order and the probabilities
  compared line by line. Its mean decides whether it is the distribution of the neutrons emitted
  or of those detected, whose mean is ν̄ times the detection efficiency: `10930004` (Halperin
  1980), with the mean 1.65, 0.44 ν̄, is refused ([`MEAN_MULTIPLICITY_BAND`](@ref));
- the quantity code `FY` files more than yields. `MASS,PAR,ZP` is the most probable charge against
  mass, which satisfies every mass rule, so `yield` requires the `FY` tag itself: six such
  datasets for 235-U would otherwise sit among the mass yields at values near 40;
- a yield against the pre-neutron mass must carry the pre-neutron branch `PRE`, and the chain
  yield `CHN` and the provisional yield `PRV` are refused beside it. A chain yield is a
  post-neutron product mass, and a provisional mass is one derived from the two fragment energies
  without correcting them for neutron emission; before the rule the `Y_vs_A` retrievals of the
  four systems carried 69 chain and 5 provisional yields beside 51 pre-neutron ones. A
  multiplicity against mass, `MASS,PR/FRG,NU`, carries no branch and is not affected.

Reaction-code qualifiers that bear on a value's scale — `MSC`, `REL`, `CHN`, `DERIV`, `FCT` — are
recorded per dataset without rejecting it where the observable admits them, and so are those naming the inducing neutron spectrum,
except that a spectrum no measurement of the channel can have been made in rejects the dataset;
see [Entrance channels](channels.md).

A dataset its subentry marks superseded (`STATUS`, code `SPSDD`) is written beside the dataset
that supersedes it, and neither is refused. The two are one measurement, a group of relation
`republication`, and name each other as `correlated_with`, which does not say which of them the
authors withdrew; the superseded one carries among its `qualifiers` an entry beginning
`superseded: by` followed by the accession of the other, and `superseded_warning` under
`[datasets]` lists the pairs. A consumer wanting one of the two takes the superseding dataset on
that entry.

Datasets of one experiment are written separately and grouped ([`CORRELATION_GROUPS`](@ref)):
each names the others as `correlated_with`, with the reason as `correlation` and the relation as
`correlation_relation`, and no weighting should count a group once per member. The relation is one
of [`CORRELATION_RELATIONS`](@ref), and says what a consumer does with the group:

- `republication`: one result published twice, the earlier marked superseded by the later; take
  one, by default the later, the one not flagged `superseded:`.
- `alternative_analysis`: one set of events reduced twice; take one.
- `repeated_run`: the quantity measured again in the same experiment, in another run or cycle or
  at another flight path; combine the members as one.
- `complementary_range`: parts of one spectrum, each over its own range; join them under one
  normalisation.

A group is formed from the text of the subentries, and of the publication where they do not
decide, case by case; the archive's `COREL` alone does not make one.

A dataset the archive marks preliminary is flagged by the code alone. `PRELM` under `STATUS` in the
common subentry of an entry flags every accepted dataset of the entry
([`PRELIMINARY_ENTRIES`](@ref)), and in a subentry that subentry
([`PRELIMINARY_SUBENTRIES`](@ref)). The qualifier begins `preliminary:` and gives the code and
what stands beside it, with the words of the publication where it has been read; a publication
never gates the flag. `preliminary_warning` under `[datasets]` lists the datasets, and none is
refused.

## Known miscoded entries

Selection follows the reaction code, so a dataset whose code disagrees with its own contents is
excluded correctly and unhelpfully unless it is read from its data.

### Multiplicity against mass without `FRG`

`MASS,PR/FRG,NU` is the multiplicity of one fragment, ν(A); `MASS,PR,NU`, without `FRG`, the
multiplicity of the fragment pair tabulated against one fragment's mass. The archive codes
per-fragment data the second way too, so every dataset coded `MASS,PR,NU` that a ν(A) or
ν(A, TKE) retrieval meets is read from its data by a complement test, A₀ being the mass of the
fissioning nucleus. The data alone decide the reading; its scale is recorded beside it and decides
nothing; a publication, where consulted, corroborates it.

**Reading.** A dataset has both halves when its pairs (A, A₀ − A) span at least 90 % of the
light-fragment yield. For such a dataset D = ν(A) − ν(A₀ − A), and S is the pair sum
ν(A) + ν(A₀ − A) weighted with the light-fragment yield:

- **Per fragment:** |S/ν̄ − 1| ≤ 0.25, and D = 0 is rejected: D changes sign along the sawtooth,
  with a χ² per pair beyond 1 + 3√(2/n) over the n pairs that state an uncertainty. A dataset
  that states none is tested on the signs of D instead: noise about zero would order them into
  so few runs with a probability below 0.27 %, the same three standard deviations.
- **Per fission:** |S/ν̄ − 2| ≤ 0.5, and D = 0 holds.

Each band is a quarter of the distance between the two readings, so the reading never hinges on
the scale. S is the pair multiplicity of each mass split and varies with it, for 252-Cf from about
3.2 to 4.6, so only its yield-weighted mean over pairs covering the yield is ν̄. ν̄ is the total
average neutron yield of the IAEA neutron data standards 2017
([doi:10.1016/j.nds.2018.02.002](https://doi.org/10.1016/j.nds.2018.02.002), Table 11), or of
ENDF/B-VIII.0 ([doi:10.1016/j.nds.2018.02.001](https://doi.org/10.1016/j.nds.2018.02.001)) at a
fast incident energy; its delayed part, below 0.7 %, the test does not resolve.

A dataset tabulated on one side of symmetry holds no pair, and is compared with a per-fragment
dataset of its own entry instead: per fragment it equals ν_FRG(A), per fission the pair sum
ν_FRG(A) + ν_FRG(A₀ − A), and one reading must fit at least twice as well as the other, by χ²
where uncertainties are stated, else by rms. Against mass and TKE, D is formed at equal TKE. The
pair sum at fixed TKE is not ν̄, so the dataset is read at the mean TKE of its entry, ν being close
to linear in TKE, and compared in the same way with a one-dimensional per-fragment ν(A), or cell
by cell with the joint per-fragment ν(A, TKE) of another experiment. Where several comparisons
apply they must agree. Anything else is undecided, and refused under both readings. A complement
is taken at a tabulated mass, or interpolated linearly across at most 4 u.

**Scale.** For a dataset with both halves the run record carries `pair_sum_deviation`,
S/(kν̄) − 1 with k = 1 per fragment and 2 per fission; `pair_sum_deviation_uncertainty`, from the
uncertainties of S and ν̄; and `pair_sum_yields`, the Y(A) that S is weighted with. That is the
experiment's own where its entry has a pre-neutron Y(A) (`pair_sum_yields_own = true`), else the
fallback for the system: `23268003` (Göök 2014) for 252-Cf, `21981005`, `21981006` and
`21981007` (Geltenbort 1985) for 233-U, 235-U and 239-Pu. `scale_consistent` is false where the
deviation exceeds three standard deviations, and absent where the dataset states no uncertainty.
A dataset whose scale is not that of ν̄ is accepted on its reading, its values uncorrected, and
named in `pair_sum_warning`.

**Basis.** `classification_basis` is `data` where the data alone decide and `data+paper` where
the publication, consulted, agrees. Every reading carries its test values as `curation` in the run
record, or as the reason it was refused (`MULTIPLICITY_READINGS` in `src/curation.jl`).

Read per fragment, and accepted where the configuration's incident-energy window admits them:

| Subentry | Complement test | S/ν̄ − 1, yields | Basis |
| :--- | :--- | :--- | :--- |
| `23268005` (Göök 2014) | 50 pairs; χ² per pair 2553 | −0.0004 ± 0.0043, own | `data+paper`: Fig. 10, [doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611) |
| `23118006` (Zeynalov 2011) | 46 pairs; χ² per pair 186 | +0.0023 ± 0.0072, own | `data+paper`: Fig. 5, [doi:10.3938/jkps.59.1396](https://doi.org/10.3938/jkps.59.1396) |
| `23175008` (Budtz-Jørgensen 1988) | 53 pairs; χ² per pair 37 | −0.020 ± 0.050, own | `data+paper`: Fig. 11 of INDC(NDS)-220, the same contribution as [doi:10.1016/0375-9474(88)90508-8](https://doi.org/10.1016/0375-9474(88)90508-8) |
| `23175010` (Budtz-Jørgensen 1988), ν(A, TKE) | D at equal TKE, χ² per pair 16; at the mean TKE 0.46 rms from `23175008`, 2.03 from its pair sum | — | `data+paper`: Fig. 13 of INDC(NDS)-220 |
| `21834009`, `21834010` (Müller 1981), 235-U at 0.5 and 5.55 MeV | 45 pairs each; χ² per pair 28 and 14 | +0.000 ± 0.009 and +0.037 ± 0.015, own at the same energy | `data+paper`: Table VIII of KfK-3220, [doi:10.5445/IR/270016605](https://doi.org/10.5445/IR/270016605) |
| `41689004` (Piksaykin 1977) | 9 pairs; χ² per pair 45 | +0.048 ± 0.019, fallback | `data` |
| `41502005` (Batenkov 2004), 235-U | 10 pairs; χ² per pair 105 | +0.018 ± 0.015, fallback | `data` |
| `41502007` (Batenkov 2004), 239-Pu at 0.296 eV | 9 pairs; χ² per pair 14 | −0.020 ± 0.037, fallback | `data` |
| `41712005` (Alkhazov 1988), ν(A, TKE) | two mass groups; at the mean TKE 0.57 rms from `41712002`, 2.06 from its pair sum | — | `data` |
| `14652004` (Britt 1964) | 16 pairs, no uncertainty; one change of sign, 1.7 × 10⁻⁴ as noise | −0.007, fallback; not weighed | `data` |
| `22650004` (Tsuchiya 2000) | 42 pairs; χ² per pair 105 | +0.039 ± 0.006, own; **not consistent** | `data` |
| `41502006` (Batenkov 2004) | 9 pairs; χ² per pair 74 | −0.107 ± 0.013, fallback; **not consistent** | `data` |

No shipped configuration writes `21834009` and `21834010`, at fast energies; `41502007`, in the
resonance, outside the thermal window of `Pu239_nth`; or `41712005`, whose 18-u mass groups are
not placed on the masses.

Refused under both readings:

| Subentry | Why |
| :--- | :--- |
| `23118007` (Zeynalov 2011), ν(A, TKE) | undecided: near-symmetric bins alone; at the mean TKE between the two readings, so the comparisons disagree |
| `14387005`, `41673002`, `41674002`, `41674003` | tabulated against the mass ratio, not a fragment mass |

The remaining seventeen are per fission, as coded, and stay with
`ordinate = "multiplicity_per_fission"`: `22660006`, where D = 0 at every pair and S/(2ν̄) − 1
is +0.011 ± 0.005 on the fallback yields, and sixteen on one side of symmetry that equal the pair
sum of a per-fragment dataset of their entry, the joint `23268007` (Göök 2014) among them, which
the paper's Figs. 13 and 14 plot as "the average total neutron multiplicity of the pair of
fragments", its basis `data+paper`. Beyond `A ≈ 180`, `23268005` reports values from
11 to 104 with uncertainties as large: the complement there is `A ≲ 70`, the yield vanishes and
the extraction diverges. They are written unchanged, since nothing is dropped on the basis of its
value.

### Other miscoded entries

One is known for `ordinate = "yield"`, and it is the rendering that misstates it. `23268002`
(Göök, 2014), `98-CF-252(0,F)MASS,PRE,FY,,MSC`, is the joint distribution Y(A, TKE): 30 000 rows
of counts on a 150 × 200 grid, which its subentry heads `TKE`, `MASS`, `DATA` and `ERR-S` in
`ARB-UNITS`. Its code names no TKE, and the `op=csv` rendering drops the TKE and ERR-S columns
and gives the unit as `PART/FIS`. It is read from its subentry (`src/curation.jl`): retrieved by
`Cf252_sf_Y_vs_A_TKE` in counts, under `relative/`, with its uncertainties, and rejected by
`Cf252_sf_Y_vs_A` as the joint distribution it is.

Two more are refused for `ordinate = "yield"` although their code is that of the pre-neutron
yield. `41425015` and `41425016` (Vorobiev 2001), `98-CF-252(0,F)MASS,PRE,FY`, are unfolded from
the neutron multiplicity matrices in 4π and 2×2π geometry, and both lie about 3 u off every
inclusive measurement: they peak at A = 106 and 146 where the nine other ²⁵²Cf yields covering
both halves peak at 107 to 108 and 143 to 145, and their mean heavy mass is 146.7 and 146.2
against 142.9 to 143.6. The ν(A) of the same measurement, `41425014`, has its sawtooth minimum at
A = 130 as the others do, so the mass scale of the entry is sound and `41425014` stays. The
subentries place the yields on Fig. 11a "(NUt=0)" of Dushin et al.
([doi:10.1016/j.nima.2003.09.029](https://doi.org/10.1016/j.nima.2003.09.029)) without saying
what that denotes. A selection of events without neutrons does not explain the shift: such events
favour heavy masses near A_H = 132 and would lower the mean heavy mass.

One more is known for `ordinate = "spectrum"`, and it is a mislabelled unit rather than a
mislabelled quantity. `40064031` (Kroshkin, 1970), `98-CF-252(0,F),PR,NU/DE,,REL`, heads its
energy column `MEV` over values running from 5.128 to 2132.8. The subentry contradicts itself:
its own `REACTION` text gives the range as "5 keV - 2 MeV", and its comment places the structure
it reports at 85 keV to 0.75 MeV. The column is keV. The dataset is retrieved and written as the
archive states it, since a unit token is not something this package overrules, but its abscissa is
a factor of 1000 too large and it is the one dataset in `Cf252_sf/spectrum_vs_E` reaching past
40 MeV — a sanity check on the abscissa range finds it immediately.

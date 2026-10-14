```@meta
CurrentModule = ExforFissionData
```

# Observables

A quantity has one name in a configuration and one symbol in a path, a file name and a column
header. The configuration spells it out, so a file a user edits explains itself; the path and the
header carry the symbol, which is the field's own nomenclature. The convention in full, including
the identifier and configuration rules, is on the [Naming](naming.md) page.

| Abscissa | Symbol | Meaning |
| :--- | :--- | :--- |
| `mass`, `product_mass` | `A`, `A_p` | pre- and post-neutron fragment mass |
| `charge` | `Z` | fragment charge |
| `neutron_energy` | `E` | secondary neutron energy |
| `total_kinetic_energy` | `TKE` | total kinetic energy |
| `neutron_number` | `nu` | number of neutrons emitted in a fission |
| (none) | — | a quantity per fission, for the prompt-γ ordinates alone |

| Ordinate | Symbol | Meaning |
| :--- | :--- | :--- |
| `yield` | `Y` | fission yield |
| `multiplicity`, `multiplicity_per_fission` | `nu`, `nu_bar` | prompt neutron multiplicity, per fragment and per fragment pair |
| `multiplicity_distribution` | `P` | probability of emitting ν neutrons in a fission |
| `fragment_kinetic_energy`, `product_kinetic_energy` | `E_K`, `E_K_p` | pre- and post-neutron fragment kinetic energy |
| `total_kinetic_energy`, `post_neutron_total_kinetic_energy` | `TKE`, `TKE_p` | pre- and post-neutron total kinetic energy |
| `total_kinetic_energy_dispersion` | `sigma_TKE` | standard deviation of the pre-neutron total kinetic energy at fixed mass |
| `neutron_kinetic_energy` | `eps` | mean centre-of-mass energy of the prompt neutrons of a fragment |
| `neutron_spectrum_temperature`, `neutron_spectrum_exponent` | `T_eff`, `lambda` | effective temperature and exponent of the form fitted to the centre-of-mass neutron spectrum |
| `spectrum`, `spectrum_maxwellian_ratio`, `spectrum_cf252_ratio` | — | prompt fission neutron spectrum: absolute, as a ratio to a Maxwellian, and as a ratio to that of 252-Cf(sf) |
| `gamma_multiplicity_per_fission`, `gamma_multiplicity` | `M_gamma_bar`, `M_gamma` | prompt γ multiplicity, per fission and per fragment |
| `gamma_energy_per_fission`, `gamma_energy` | `E_gamma_tot`, `E_gamma` | prompt γ energy, per fission and per fragment |
| `gamma_mean_energy` | `eps_gamma` | mean energy of a prompt γ photon |

An abscissa is a **list**, because it is a joint index: `["mass"]`, or
`["mass", "total_kinetic_energy"]` for ν(A, TKE). A joint abscissa is therefore no separate
vocabulary item, and the directory it writes to is the ordinate, `vs`, then the abscissa
symbols — `nu_vs_A_TKE`, `Y_vs_A`, `spectrum_maxwellian_ratio_vs_E`.

The eight abscissae the archive can be asked for are `["mass"]`, `["product_mass"]`, `["charge"]`,
`["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]`,
`["mass", "total_kinetic_energy"]` and `["neutron_number"]`, and the empty list `[]` of a quantity
per fission, which only the prompt-γ ordinates take and whose directory is the ordinate symbol
alone: `M_gamma_bar`, `E_gamma_tot`, `eps_gamma`.

Each ordinate belongs to one EXFOR quantity code — `yield` to `FY`, the multiplicities to `NU`,
the kinetic energies to `E`, the spectra to `MFQ`, the prompt-γ multiplicities to `FY` and the
prompt-γ energies to `E` — and the configuration does not name it: the
code is read from the ordinate. The quantity decides which datasets the archive offers at all, and
several ordinates impose no tags of their own, so a pairing that could be written down could be
written down wrong and would retrieve a different observable under the requested name.

Not every combination exists in the archive. ν(TKE), for instance, is reported as a pair quantity,
so `multiplicity_per_fission` against `["total_kinetic_energy"]` returns data where
`multiplicity` returns none.

## The width of the TKE distribution

σ_TKE(A), the standard deviation of the pre-neutron total kinetic energy at fixed pre-neutron
mass, has no code in EXFOR. Dictionaries 34 (modifiers) and 236 (quantities) of the current
dictionary transmission carry no quantity or modifier for a width, dispersion, variance,
standard deviation or FWHM of a kinetic-energy distribution, and the Formats Manual leaves such a
value to a `MISC` column explained in `MISC-COL` free text. The archive fills it inconsistently —
a standard deviation, a variance in MeV², a FWHM, a "dispersion", of the TKE or of one fragment's
energy — and once with no width at all.

The width is therefore read only from the columns a configuration names, one `[[width]]` table
per dataset with the column, what it holds and whose energy it is (see
[Configurations](configurations.md)); never from the free text, and never from the datum. A
named dataset is selected as the mean TKE of its entry is, and its width converted to σ of the
TKE: a variance by its square root, a FWHM by 2√(2 ln 2), a half width by √(2 ln 2), and the
width of the energy of a fragment of mass A by A₀/(A₀ − A), which pre-neutron momentum
conservation makes exact at fixed mass. The run record gives, per dataset, the column, the
conversion, the mass range, and the `MISC-COL` text of the subentry quoted.

Where a publication settles what a column holds against its label, the record says so:

- `23012005` and `23012006` (Nishio 1995, [doi:10.1080/18811248.1995.9731725](https://doi.org/10.1080/18811248.1995.9731725))
  are labelled FWHM, and hold half of it: the paper's Fig. 6 bars are the FWHM, and measured on
  the figure they are 2.00 to 2.10 times the columns. Converted, the two should agree exactly at
  fixed mass; they differ by 29 to 32 %, which the record states without reconciling it.
- The width column of `12709004` (Weber 1981, [doi:10.1103/PhysRevC.23.2100](https://doi.org/10.1103/PhysRevC.23.2100)),
  labelled a standard deviation, is refused even when named: it runs from 47 to 94 where Fig. 3c
  of the paper plots σ(TKE) from 15 to 10.5 MeV, following the plot as an uncalibrated, inverted
  digitisation.
- The widths of `22780003` (Hambsch 1997) at A = 180 and 181, 0 and 1.87 MeV, are not written:
  no measurement has them, and a consumer would take them at face value.
- The dispersion of 240-Pu(sf) in `22273023` (Schillebeeckx 1992, [doi:10.1016/0375-9474(92)90296-V](https://doi.org/10.1016/0375-9474(92)90296-V))
  is digitised from Fig. 8 of the paper, and scatters: A_H = 150, 156 and 158 lie 1.4 to 2.9 MeV
  above the mean of their neighbours. It is written unsmoothed, and the record gives the
  mass-integrated width it yields with the 239-Pu(n_th,f) Y(A) and mean TKE of Wagemans 1984
  against the 11.81 ± 0.01 MeV measured for 239-Pu(n_th,f) (`22273003`).

## The joint yield Y(A, TKE)

`yield` against `["mass", "total_kinetic_energy"]` is the joint pre-neutron distribution, one
row per (A, TKE) cell. It is recorded event by event and published as counts, so it is admitted
in arbitrary units and written under `relative/`, and the record states the TKE grid and the
normalisation as the subentry gives them. The archive holds one for these four systems,
`23268002` (Göök 2014, [doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611)),
whose code names no TKE and whose csv rendering drops the TKE column; it is read from its
subentry. The record adds two statements the data support: its TKE values are the centres of
1-MeV bins, since as centres the matrix reproduces the mean TKE of `23268004` to 0.05 MeV and as
edges misses by 0.5 MeV; and its mass marginal is `23268003`, to a relative 4 × 10⁻⁶.

For 240-Pu(sf) the archive holds the raw event counts of Demattè 1997 (`22413013`,
[doi:10.1016/S0375-9474(97)00032-8](https://doi.org/10.1016/S0375-9474(97)00032-8)), coded
`MASS,PRE,FY/DE,,RAW`: 1-MeV TKE steps from 140 to 210 MeV against heavy masses 120 to 160, from
double-energy measurement corrected for prompt neutron emission. The code gives the energy as a
fragment's (`EN-SEC (E,FF)`), but its range is that of the TKE; the subentry heads the counts
`NO-DIM`, which the csv rendering turns into `PC/FIS/MEV`. It is read from its subentry as
counts in arbitrary units.

The archive holds slices of the joint distribution besides — yields against mass at a few fixed
energies of one fragment or of both, and TKE distributions for a few masses. They are not the
distribution over the fragmentation range and are not retrieved as it; the record of each
`Y_vs_A_TKE` retrieval lists those of its system under `slices`, with their masses and energies.

## The mean neutron energy

`neutron_kinetic_energy` is the mean energy ⟨ε⟩ of the prompt neutrons of a fragment in the
centre-of-mass frame of that fragment, coded `MASS,PR,KE,N`. It is retrieved against `["mass"]`,
under `eps_vs_A/`, and against `["mass", "total_kinetic_energy"]`, under `eps_vs_A_TKE/`.

Most subentries head the value `DATA-CM` rather than `DATA`. For this ordinate alone that column
is the datum, read with its uncertainty columns, and the csv rendering is compared with it row by
row, to a relative 10⁻⁵ since the rendering writes six significant digits; see
[`CENTRE_OF_MASS_ORDINATES`](@ref). The frame is recorded per dataset as `ordinate_frame`, with
`ordinate_frame_basis` and `ordinate_frame_evidence` ([`ordinate_frame`](@ref)), and the basis
is one of three: `heading` where the subentry heads the value `DATA-CM`; `subentry` where its
text names the frame, as the `REACTION` text of `41502009` (Batenkov 2004) does; and
`publication` where the subentry is silent and the publication names the frame: the one the
subentry cites or, where that article was not obtained, the authors' paper of the same title and
data, quoted in the evidence with its DOI ([`ORDINATE_FRAMES`](@ref)). Four datasets headed
`DATA` are read from the publication, and all four are in the centre of mass:

- `23175012` (Budtz-Jørgensen 1988, 252-Cf), by its article
  ([doi:10.1016/0375-9474(88)90508-8](https://doi.org/10.1016/0375-9474(88)90508-8)): "The
  neutron energy η in the center-of-mass system of the fragment was evaluated event by event"
  (section 3.2.3, p. 322), and "Fig. 17a displays the average energy η as function of A"
  (p. 323).
- `41689005` (Piksaykin 1977, 252-Cf), by the authors' paper of the same title at the Kiev
  conference of 1975 (Neitronnaya Fizika, part 5, p. 92, Moscow 1976), whose Fig. 4 is captioned
  as the mean energy of the neutrons in the centre-of-mass system against fragment mass. Its mean
  weights in the component isotropic in the laboratory, and the authors put about 10 % on it.
  The article, Yad. Fiz. 25, 723, was not obtained.
- `14369005` (Fraser 1966, 233-U), by Fig. 5 of Milton and Fraser, Physics and Chemistry of
  Fission (Salzburg 1965), IAEA STI/PUB/101, vol. 2, p. 47, the figure the subentry digitises:
  "The symbol η is used for E_CM".
- `22660004` (Nishio 1998, 233-U, against A and TKE), by Fig. 5 of
  [doi:10.1080/18811248.1998.9733919](https://doi.org/10.1080/18811248.1998.9733919): "Average
  neutron energy in the center-of-mass system as a function of total kinetic energy".

A dataset whose publication leaves the frame open, or for which none has been read, is recorded
`unstated`, written, and flagged among its `qualifiers` by an entry beginning `frame unstated:`
and in `frame_warning` under `[datasets]`; none of the shipped configurations now writes one. A
value stated to be in the laboratory frame is refused, and no dataset of the shipped
configurations is.

Each record also says how the mean was formed, as its publication states it
([`MEAN_FORMATIONS`](@ref)). `mean_formed_from` is `measured_spectrum`, the first moment of the
measured centre-of-mass spectrum; `fitted_spectrum`, the first moment of a form fitted to it;
`completed_spectrum`, the measured spectrum completed beyond its range by a fitted form; or
`unstated`. `mean_fitted_form` gives the form where one enters, `mean_threshold_mev` and
`mean_threshold_frame` the low-energy limit of the neutrons that enter the mean and the frame it
is stated in, the detector threshold in the laboratory or the lower limit of the averaged
centre-of-mass spectrum, and `mean_evidence`
the sentence or equation, with the DOI. A threshold is recorded only from a publication read;
what an EXFOR entry alone says of one is quoted in `mean_evidence`. Where a publication leaves open
whether the range below the limit enters the mean, the dataset carries a qualifier beginning
`mean_threshold_unsettled:` and the limit is not a cut.

| Dataset | `mean_formed_from` | Threshold and its frame | Source |
| :--- | :--- | :--- | :--- |
| `14065003`, `14065010` (Bowman 1963) | `measured_spectrum`: the second moment of the centre-of-mass velocity spectrum, summed event by event, counters at 11.25° | 0.52 MeV, laboratory, a velocity cut of 1 cm/ns | [doi:10.1103/PhysRev.129.2133](https://doi.org/10.1103/PhysRev.129.2133) |
| `23175012` (Budtz-Jørgensen 1988) | `fitted_spectrum`, const η^λ exp(−η/T): the mean equals (λ + 1)T of the fitted form to 0.4 % rms over the 79 masses; the article does not say how the mean was formed | 0.3 MeV, laboratory | [doi:10.1016/0375-9474(88)90508-8](https://doi.org/10.1016/0375-9474(88)90508-8) |
| `23268011` (Göök 2014) | `unstated` | 0.7 MeV, laboratory, proton-recoil pulse height | [doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611) |
| `41689005` (Piksaykin 1977) | `completed_spectrum`: a Maxwellian √η exp(−η/T) above 1.5 MeV, T fitted to the measured part | 0.4 MeV, laboratory | Kiev 1975 paper |
| `22464003` (Nishio 1998, 235-U) | `unstated`: "the mean values of the neutron energy" are plotted without a word on how they were formed | 0.2 MeV, laboratory | [doi:10.1016/S0375-9474(98)00008-6](https://doi.org/10.1016/S0375-9474(98)00008-6) |
| `41502008`, `41502009` (Batenkov 2004) | `unstated`: the mean energy in the fragment centre-of-mass system is shown without a word on how it was formed; the Maxwell shape the entry mentions is assumed for the ratios of the total spectra to 252-Cf, not for the mean; the publication calls its results preliminary, which the `qualifiers` say | 0.2 MeV, laboratory | [doi:10.1063/1.1945175](https://doi.org/10.1063/1.1945175) |
| `23444006` (Göök 2018) | `unstated` | none stated as a value | [doi:10.1103/PhysRevC.98.044615](https://doi.org/10.1103/PhysRevC.98.044615) |
| `22650008` (Tsuchiya 2000) | `measured_spectrum`: not 3T_eff/2 of the Maxwellian "but the average value of all experimental points above 0.5 MeV"; the publication leaves open whether the range below 0.5 MeV enters the mean, which the `qualifiers` say in an entry beginning `mean_threshold_unsettled:`, and the limit is not to be applied as a cut | 0.5 MeV, centre of mass; detector threshold 0.2 MeV | [doi:10.1080/18811248.2000.9714976](https://doi.org/10.1080/18811248.2000.9714976) |
| `14369005` (Fraser 1966) | `measured_spectrum`: E_CM = 0.5228⟨V²⟩ from event-weighted velocity moments, counter at 10° | not given for the 233-U runs | Salzburg 1965 |
| `22660003` (Nishio 1998, 233-U) | `measured_spectrum`, "calculated from the experimental data" | 0.3 MeV, laboratory; the EXFOR entry says 0.2 | [doi:10.1080/18811248.1998.9733919](https://doi.org/10.1080/18811248.1998.9733919) |
| `22660004` (Nishio 1998, 233-U, A and TKE) | `unstated` for Fig. 5 | 0.3 MeV, laboratory | the same |

The rule does not forbid `PRE` in SF5. With `N` required in SF7 the code is none of the fragment
energies, whose rules forbid `N`, and `PRE` beside `PR` marks the pre-neutron mass of the
abscissa, as in `MASS,PRE/PR/FRG,NU`. `41689005` (Piksaykin 1977,
`98-CF-252(0,F)MASS,PRE/PR,KE,N`) is coded so: a mean neutron energy of 1.08 to 1.84 MeV against
pre-neutron masses 92 to 160 on a 4-u grid, 18 lines of which 9 carry a statistical uncertainty,
digitised from Fig. 2 of Yad. Fiz. 25, 723 (1977).

A fragment kinetic energy coded `KE,N` is something no reaction-code test can tell from a neutron
energy, and is told by its magnitude: a dataset holding more than
[`MAXIMUM_NEUTRON_KINETIC_ENERGY`](@ref), 5 MeV, on any row is refused, the reason giving the
number of rows above the bound and the largest value. An evaporation spectrum ε exp(−ε/T) has the
mean energy 2T (Weisskopf, [doi:10.1103/PhysRev.52.295](https://doi.org/10.1103/PhysRev.52.295)),
so 5 MeV asks for T = 2.5 MeV, where the temperatures fitted to the measured spectra stay below
1.4 MeV. The largest mean the archive holds for these systems is 3.68 ± 0.64 MeV, at A = 180 in
`23268011` (Göök 2014), and every other lies below 3.3 MeV; no fragment carries less than about
40 MeV. `23164022` (Al-Adili 2016, `92-U-235(N,F)MASS,PRE/PR,KE,N`) holds fragment kinetic
energies, 43.6 to 101.9 MeV on all 94 rows, and is refused on the bound.

Against `["total_kinetic_energy"]` alone the archive holds nothing for the five systems: the four
datasets coded `KE/TKE,N` all carry `MASS`, and no `eps_vs_TKE` configuration is shipped. The
joint ⟨ε⟩(A, TKE) is retrieved for 252-Cf and 233-U; 235-U, in either channel, and 239-Pu have no
`eps_vs_A_TKE` configuration.

## The parameters of the fitted spectrum

`neutron_spectrum_temperature` and `neutron_spectrum_exponent` are the effective temperature
T_eff and the exponent λ of the form const η^λ exp(−η/T_eff) fitted to the centre-of-mass spectrum
of the neutrons of a fragment of given mass. Against `["mass"]`, T_eff is written under
`T_eff_vs_A/` as `A T_eff T_eff_uncertainty` in MeV, and λ, a pure number, under `lambda_vs_A/`
as `A lambda lambda_uncertainty`. EXFOR has no code for either; they sit in `MISC` columns of the
mean neutron energy. Like the width of the TKE distribution they are therefore read only from the
columns a configuration names, one `[[fit_parameter]]` table per dataset with the keys `subentry`
and `column` (see [Configurations](configurations.md)), and the uncertainty is the column
`<column>-ERR` ([`PARAMETER_ORDINATES`](@ref)). The dataset is selected as the mean neutron
energy is, by the same tag rule, the 5 MeV bound and the frame. The record gives, per dataset,
`parameter_column`, `parameter_unit` and `parameter_is`, and the form fitted with the equation of
the publication as `fit_form` and `fit_evidence` ([`SPECTRUM_FITS`](@ref)).

`Cf252_sf_T_eff_vs_A` reads `MISC1` of `23175012` (Budtz-Jørgensen 1988), 79 masses with T_eff
from 0.77 to 1.39 MeV, and `MISC` of `23268011` (Göök 2014), 82 masses of its 109, from 0.72 to
1.40 MeV; `Cf252_sf_lambda_vs_A` reads `MISC2` of `23175012`, 79 masses with λ from 0.11 to 0.94.
Budtz-Jørgensen fits Eq. (8) of the article, the cascade evaporation spectrum of Le Couteur and
Lang, with λ and the temperature free; the subentry calls the same form a Weisskopf spectrum.
Göök 2014 fits Eq. (14) of
[doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611),
φ(η) ∝ η^λ exp(−η/T_eff), and its λ, Fig. 18c, is not in the archive. The archive holds no such
column for the other systems.

## Spectrum ratios

Under `spectrum` the archive holds four 252-Cf(sf) datasets as N(E)/√E, `RRE` among the
modifiers of their code: `23175004`, `40064027`, `40250003` and `41689002`. They are written as
tabulated, not converted, and carry a qualifier beginning `spectrum_form:`. It holds one
evaluation there, `V0101002` (Mannhart 1987), written and flagged with a qualifier beginning
`evaluation:`.

The archive gives the spectrum as a ratio in two forms, and each is an ordinate of its own.

`spectrum_maxwellian_ratio` is the spectrum divided by a Maxwellian √E exp(−E/T), coded with
`MXD`, which `spectrum` excludes. Every dataset must state the temperature it was formed with: the
column `KT-NRM` of the COMMON section of its subentry, else of subentry 001, else a constant column
of its DATA table, in an energy unit. It is recorded as `maxwellian_temperature_mev` with
`maxwellian_temperature_source` ([`maxwellian_temperature`](@ref)), and a dataset that gives none
is refused. `14278003` (Poenitz 1982, 252-Cf) holds in `KT-NRM` the mean energy of the
Maxwellian, 2.159 MeV, as its `ANALYSIS` text says, and the record gives T = 1.439 MeV, two
thirds of it. The ratio form is retrieved for 252-Cf(sf) and for thermal 235-U, 239-Pu and 233-U.
For each of the three thermal systems Starostov 1985 (entry 40930) gives the ratio in four
datasets, the first measurement cycle with an anthracene crystal, a stilbene crystal and a plastic
scintillator, and the second cycle. Their subentries name each other under `STATUS` with `COREL`;
they are written separately and marked `correlated_with`, one measurement for any combination.
Their relation is `complementary_range`, the second cycle repeating the lower range and extending
it downwards.

`spectrum_cf252_ratio` is the ratio of the prompt fission neutron spectrum of the system and that
of 252-Cf(sf), both at the same outgoing neutron energy, tabulated against `["neutron_energy"]`
only. Of the shape data it is the least dependent on the detector efficiency, which cancels. It
is the one observable read from a combination of reaction codes ([`spectrum_ratio`](@ref)): the
code must be the ratio of exactly two reactions, one the system's and one `98-CF-252(0,F)`, each
satisfying the rule of `spectrum` — so no `MXD`, no `MSC`, no angle-differential or partial
spectrum — with no variable headed for numerator or denominator alone (`-NM`, `-DN`). Sums,
differences, products, ratios of ratios and ratios between two other systems stay refused, under
this ordinate and every other, and the ordinate is refused for 252-Cf(sf) itself.

The archive gives both orientations. Values are written as tabulated, never inverted, and the
record gives per dataset `ratio_orientation`, `system_over_reference` or `reference_over_system`,
with `ratio_numerator` and `ratio_denominator`, and the qualifiers of both reactions;
`orientation_warning` under `[datasets]` says when a directory holds both. Datasets in arbitrary
units go under `relative/`, as for spectra. Ratios coded with `MSC` are refused: `10911002`,
`10911003` and `10911004` (Smith 1980) hold the logarithm of the ratio in arbitrary units at
525 keV, and `41502002`, `41502003` and `41502004` (Batenkov 2004) were plotted on a scale their
author states was probably logarithmic.

## The multiplicity distribution

`multiplicity_distribution` is the probability P(ν) of emitting ν neutrons in a fission,
tabulated against `["neutron_number"]` and written under `P_vs_nu/` as `nu P P_uncertainty`. The
two go together and with nothing else, and the loader refuses any other pairing. The quantity
code is `NU`, and the archive marks the distribution with the branch `NUM`: `,NUM,NU`,
`,PR/NUM,NU`, once `NPART,NUM,NU`. The subentry tabulates it against `PART-OUT`, the number of
outgoing particles, which the csv rendering does not carry, and the documentation of earlier
versions called it unwritable for that reason. The rows of the subentry and of the rendering are
aligned by order and the probabilities compared line by line.

The rule asks for `NUM` in SF5 and `NU` in SF6, and refuses a distribution for a fragment mass
or charge (`MASS`, `ELEM`) and one derived from a model (`DERIV`: `30544002`, a simulated
binomial distribution). An evaluation (`EVAL`: `V0045011` to `V0045013`, Holden 1988) is written
and flagged with a qualifier beginning `evaluation:`, with `evaluation_warning` under
`[datasets]`, like every other statement of the archive on the standing of a dataset. Arbitrary
units are refused: `14064003` holds counts, and `23598004` distributions for the fragment
charges 42 and 56.

The data decide what a distribution is. The archive codes the distribution of the neutrons
*detected* alike, and its mean is ν̄ times the detection efficiency, so a distribution whose mean
lies further than a quarter of ν̄ from ν̄ is refused ([`MEAN_MULTIPLICITY_BAND`](@ref)):
`10300005` (Balagna 1973, mean 2.48, 0.66 ν̄), `10930004` (Halperin 1980, 1.65, 0.44 ν̄) and
`14064002` (Hicks 1955, 1.43, 0.38 ν̄), all of 252-Cf. ν̄ is the total ν̄ of the IAEA neutron data
standards 2017 ([doi:10.1016/j.nds.2018.02.002](https://doi.org/10.1016/j.nds.2018.02.002);
[`NUBAR_STANDARDS`](@ref)): 3.764 ± 0.016 for 252-Cf, 2.425 ± 0.011 for 235-U, 2.878 ± 0.013 for
239-Pu and 2.487 ± 0.011 for 233-U. It includes the delayed neutrons, 0.2 to 0.7 % of it.

A table is written as tabulated, never renormalised. The record gives per dataset what it
implies, and applies none of it ([`distribution_moments`](@ref)): `distribution_sum` and
`distribution_normalised`, whether the sum lies within 0.01 of one; `mean_multiplicity`,
Σ ν P / Σ P, with `mean_multiplicity_uncertainty` where every line states an uncertainty, the
lines taken as uncorrelated; `mean_nubar` and `mean_nubar_uncertainty`; `mean_deviation`,
mean/ν̄ − 1, with `mean_deviation_uncertainty`; and `mean_consistent`, whether the deviation lies
within three standard deviations of zero. Every accepted mean is consistent with ν̄ within three
standard deviations where an uncertainty is stated.

| Configuration | Accepted, with the mean | Refused |
| :--- | :--- | :--- |
| `Cf252_sf_P_vs_nu` | `10605005` Stoughton 1973 (3.70; sum 0.99, not normalised), `10901006` Hoffman 1980 (3.73), `12337013` Diven 1956 (3.88), `12833005` Gwin 1984 (3.773), `13715014` Hicks 1956 (3.82), `21495003` Baron 1966 (3.78), `30046011` Boldeman 1967 (3.757), `307720151`, `307720152`, `307720153` Boldeman 1985 at three discriminator biases (3.757), `41425002` Vorobiev 2001 (3.756) | `10300005`, `10930004`, `14064002` by their mean |
| `U235_nth_P_vs_nu` | `12833007` Gwin 1984 (2.437), `30046008` Boldeman 1967 (2.416), `30772010` Boldeman 1985 (2.406), `32820002` Huang 1961 (2.44), `V0045012` Holden 1988 (2.413), an evaluation | `12337009` Diven 1956, at 80 keV; `30544002` |
| `Pu239_nth_P_vs_nu` | `12833008` (2.888), `30046009` (2.924; sum 1.010, not normalised), `30772011` (2.879), `V0045013` (2.875), an evaluation | `12337010`, at 80 keV |
| `U233_nth_P_vs_nu` | `12833006` (2.494), `30046007` (2.483), `30772009` (2.480), `V0045011` (2.477), an evaluation | `12337008`, at 80 keV |

`30046011` and the three datasets of `30772015` are one measurement and name each other as
`correlated_with`, of relation `repeated_run`: Table III of the publication
([doi:10.13182/NSE85-A17133](https://doi.org/10.13182/NSE85-A17133)) gives four runs, 20 × 10⁶
fissions at a bias of 480 keV in `30046011` and 8.7, 8.4 and 6.8 × 10⁶ at 620, 720 and 1950 keV
in `30772015`. The Boldeman 1967 dataset of each neutron-induced system is marked superseded by
the 1985 one in its subentry; both are written, and marked `correlated_with`. The 1967 dataset
says so among its `qualifiers`, in an entry beginning `superseded:` that names the 1985 one, and
`superseded_warning` lists them.

The archive holds more on the distribution than this, and none of it is retrieved: no P(ν) of the
light or the heavy fragment as a dataset, but one distribution per fragment charge, `23598004`,
for the Mo–Ba partition in arbitrary units; the variance of ν against mass as a `MISC` column of
`41425014` (Vorobiev 2001, 252-Cf), and against TKE for two mass groups in `41712005` (252-Cf);
and second moments and covariance matrices of P(ν) only as free text, `ADD-RES` and
`COVARIANCE`, in the Boldeman and Gwin entries.

## Post-neutron products

Three observables describe the fission products after prompt neutron emission, each against one
abscissa, and each is retrieved for the four systems: `<system>_Y_vs_A_p`,
`<system>_Y_vs_Z_A_p` and `<system>_E_K_p_vs_A_p`. As for every observable, the qualifiers `MXW`
and `SPA` are recorded under `nth` and not refused, while `FIS`, `EPI` and `FST` reject the
dataset.

### The post-neutron mass yield

`yield` against `["product_mass"]` is the mass yield of the products, `MASS,SEC,FY` or
`MASS,CHN,FY`, written under `Y_vs_A_p/` as `A_p Y Y_uncertainty`. The abscissa requires `MASS`
in SF4 and `SEC`, `IND` or `CHN` in SF5, and refuses `PRE`, `ELEM`, `TKE` and `DE`. A chain
yield, `CHN`, is the yield of a mass chain after beta decay, which conserves A, so it is the
post-neutron mass yield up to the delayed-neutron transfer between neighbouring chains, below a
per cent. It is written as one and flagged: its `qualifiers` carry an entry beginning
`CHN: chain yield:` with that reading, `scale_warning` under `[datasets]` names it, and the
record states the reading under `[conventions]` as `chain_yield`. The pre-neutron yield against
mass and the independent yield of a nuclide refuse `CHN`. A blank branch establishes nothing and
is refused, and the provisional yield `PRV` is not among the alternatives. `CUM`, the cumulative
yield, is refused for every observable, and the partial branch `PAR` as for the independent
yield below.

The csv rendering restates the unit of the subentry, `PC/FIS` as `PART/FIS` with the values
divided by 100, and the values written are the rendering's: a mass yield in `PART/FIS` sums to 2
over both fragments. The `normalisation` statement of the record follows the unit the file is
written in, and `unit_subentry` records the unit the subentry heads the datum with. Both hold for
every yield, the pre-neutron ones included.

Every yield carries `yield_sum`, the sum of the written yields of the dataset in the unit the
file is written in: for a mass yield in `PART/FIS`, 2 over both fragments and about 1 over one
side. It is recorded and never a cut, and the convention `yield_sum` under `[conventions]`
states it for every yield retrieval. A sum its coverage does not explain is to be read with the
publication: `31738002` (Koblik 2014, `MASS,SEC,FY,,SPA`) sums to 1.82 over the heavy group
alone, A_p 125 to 155, and is written as the archive gives it.

For 252-Cf the archive holds 18, 6 coded `SEC` and 12 `CHN`. The six are `13081002` (Schmitt
1965), `14259009` (Romano 2010), `14420002` (Meierbachtol 2015), `14652002` and `14652003` (Britt
1964) and `14790002` (Gastis 2022). For 235-U it holds 36, 7 `SEC` and 29 `CHN`; the seven are
`14208003` (Derengowski 1970), `14259005` (Romano 2010), `21752016` (Wagemans 1981), `21981012`
(Geltenbort 1985), `23594002` (Shiraishi 1968), `31738002` (Koblik 2014) and `32888002` (Liu
2022). For 239-Pu 26, 10 `SEC` and 16 `CHN`; the ten are `21981013` (Geltenbort 1985);
`222730131`, `222730132` and `22273014` (Schillebeeckx 1992), coded `DERIV`, recorded among their
`qualifiers` and named in `scale_warning`; `23342002` to `23342005` (Gupta 2017); `23583002`
(Boucheneb 1991); and `32879002` (Liu 2022). For 233-U 14, 3 `SEC` and 11 `CHN`; the three are
`21981011` (Geltenbort 1985), `23784002` (Chebboubi 2021) and `41496006` (Aleksandrov 1994). The
masses of `14420002`, `14652002`, `14652003` and `23594002` are interpolated onto the integers.

The chain-yield tables of note are, for 252-Cf, `14020002` (Kiker 1964, 68 masses), `33158006`
(Naik 2021, 62), `30691002` (Li Ze 1983, 44), `21531003` (Thierens 1976, 43), `21592002`
(Blachot 1975, 27) and `13283008` (Harbour 1971, 20); for 235-U,
`316850021` and `316850022` (Ajitanand 1978, 87 and 78 masses, A_p 70 to 170), `13359002`
(Diiorio 1977, 64), `33186006` (Naik 2023, 48), `21543013` (Asghar 1977, 44, heavy group),
`10865002` (Maeck 1978, 39), `21531002` (Thierens 1976, 37), `21054087` (Wohlfarth 1976, 32,
light group), `13270003` (Lisman 1970, 31) and `22985006` (Bail 2009, 30, heavy group); for
239-Pu, `33178006` (Naik 2022, 68), `21544008` (Asghar 1978, 46, heavy group), `22985005` (Bail
2009, 25, heavy group), `13482002`, `134800021` and `134800022` (Fickel 1959) and `13270008`
(Lisman 1970); and for 233-U, `132700021` and `132700022` (Lisman 1970, 41 and 40), `33187006`
(Naik 2023, 58), `21771012` (Asghar 1981, 38, heavy group), `10918004` (Wehring 1980, 32, light
group) and `13208002` to `13208004` (Bidinosti 1961). The rest are tables of one to 28 masses,
most of a dozen or fewer. Many chain yields carry `SPA` or `MXW`, recorded as for every
observable. Two chain yields stay out: `13067002` (Fraser 1963, 252-Cf, 89 masses), which the
archive renders with every value marked an upper limit (`Max`) and which is refused as a limit,
not a measurement; and `22130003` (Asghar 1981, 233-U), in arbitrary units.

### The independent yield

`yield` against `["charge", "product_mass"]` is the independent yield of a nuclide,
`ELEM/MASS,IND,FY`, written under `Y_vs_Z_A_p/` as `Z A_p Y Y_uncertainty`. The abscissa requires
`MASS` and `ELEM` in SF4 and `SEC` or `IND` in SF5, and refuses `PRE`, `KE`, `DE` and `CRN`.

`ELEM` is a code of the product subfield of the reaction code and never a heading of the DATA
table, which heads the atomic number of a nuclide `ELEMENT` (EXFOR Dictionary 24), its mass
number `MASS` and its isomeric state `ISOMER`. The csv rendering codes the product as 1000·Z + A,
`ProdZA`, and the isomer as `ProdM`, and the two tables are aligned row by row. Earlier versions
looked for an `ELEM` heading, and every independent yield failed that alignment.

A subentry of one element may hold `ELEMENT`, and at times `MASS` or `ISOMER`, as a constant of
its COMMON section or of the COMMON section of subentry 001 of the entry. With the charge in the
abscissa such a constant is placed beside the lines of the DATA table before the tables are
compared, and a rendering that then codes the product as a bare mass is accepted. The record lists
the constants used as `common_constants`, `ELEMENT = 51.0 [NO-DIM]` for instance. Twenty datasets
of 235-U, eight of 239-Pu, five of 233-U and one of 252-Cf are read so, among them `12740002`
(Rengan 1982), `20848003` (Fujiwara 1982), `21218004` (Kaiser 1978), `21641002` (Balestrini 1979),
`23709002` (Strom 1965), `30912002` (Engler 1983), `30953004` (Ehrenberg 1972), `30960002` (Shmid
1981) and `21706004` (Zwicky 1980).

A nuclide reported in several isomeric rows is written once. Where the archive gives its own
total, the row without an isomer mark, that row is written; otherwise the rows sharing one mark
are repeat measurements of that state and are combined as repeats, by the inverse-variance
weighted mean, and the states so resolved are summed with their uncertainties in quadrature.
`23709002` (Strom 1965) gives the ground-state yield of Sb-124 five times, four samples and their
average under `FLAG`, and `33158004` (Naik 2021) the isomeric yield of I-136 through two decay
lines; both are combined, not summed. Such combinations count in `abscissae_combined`, and
`combined_over` names the auxiliary columns that varied, `FLAG` and `DECAY-FLAG` there.

A nuclide given in one marked state alone is written as it stands and is the yield of that state,
not of the nuclide. Several rows without a mark are totals that cannot be told apart, and are
combined as repeats. The record names the nuclides of each dataset, by labels such as `Sb-130`, in
`isomer_summed_nuclides`, `isomer_single_state_nuclides` and `isomer_ambiguous_nuclides`, beside
the counts `isomer_totals_used`, `isomer_states_summed` and `isomer_groups_ambiguous`; it states
the convention as `isomers` under `[conventions]`, and `isomer_warning` under `[datasets]` lists
the datasets concerned.

Independent yields coded with the nuclide in the reaction code, `55-CS-136,IND,FY` and the like,
one nuclide per dataset and no `ELEMENT` or `MASS` table, are not retrieved: they carry neither
`MASS` nor `ELEM` in SF4.

Four codes file under `ELEM/MASS` what is not the independent yield. The ordinate `yield` refuses
`FRC` (Dictionary 34, fractional), the independent yield as a fraction of its chain yield, which
is a ratio and not the yield: under this abscissa 39 datasets of 235-U, 15 of 239-Pu, 11 of 233-U
and 5 of 252-Cf, `23558005` (Günther 1972) and `14088003` to `14088006` for instance. The
abscissa refuses `CRN` (Dictionary 31, "more than two fragments are specified"), the yields of
correlated fragment pairs, tabulated against `ELEM1/MASS1` and `ELEM2/MASS2`: 15 such datasets for
252-Cf, `13648002` to `13648006`, `13749002` and `14634002` among them. The two post-neutron yields
refuse the partial branch `PAR` (Dictionary 31): `21689014` to `21689018` (Lang 1980, Lohengrin)
each hold the yields at one product kinetic energy, a constant `E` of their COMMON section,
88.5 MeV in the first, and are slices of the energy-resolved distribution; the same entry gives
the independent yield as `21689019`, which is written. The pre-neutron yield against mass is not
concerned. `CUM`, the cumulative yield, is refused for every observable.

The archive holds 8 for 252-Cf, 48 for 235-U, 23 for 239-Pu and 17 for 233-U. The large tables
are, for 235-U, `10722003` (Strittmatter 1977, 100 nuclides, A_p 82 to 106), `21689019` (Lang
1980, 113 nuclides, 80 to 107), `221610021` (Rudstam 1990, 92 nuclides written, about a quarter
of them summed over isomeric states), `22151003` (Sida 1989, 70 to 84), `23586004` (Armbruster
1987, 70 to 80), `23558007` (Günther 1972, 130 to 140) and `13600002` (Tipnis 1998); for 239-Pu,
`23558006` (Günther 1972, 130 to 139) and `22985008` (Bail 2009, 58 nuclides); and for 233-U,
`10918003` (Wehring 1980, 100 nuclides) and `23794002` (Johansson 1997, 157 nuclides). The rest
are radiochemical tables of a few nuclides each.

### The post-neutron kinetic energy

`product_kinetic_energy` against `["product_mass"]` is the kinetic energy of a product of given
mass after neutron emission, `MASS,SEC,KE`, `AKE` accepted as `KE`. It is written under
`E_K_p_vs_A_p/` as `A_p E_K_p E_K_p_uncertainty` in MeV, restated from the `EV` of the rendering.
The ordinate composes with the product-mass abscissa: `KE` in SF6, `MASS` in SF4 and `SEC` or
`IND` in SF5, and no `LF+HF`, no `N`, no `PRE` and no `ELEM`; the chain branch `CHN`, which the
abscissa admits for a yield, names a yield and is refused here.

For 252-Cf the archive holds no `MASS,SEC,KE`: its post-neutron kinetic energies, `32928002` and
`32928003`, are `ELEM,SEC,AKE`, resolved in charge, and `Cf252_sf_E_K_p_vs_A_p` writes nothing.
For 235-U it holds nine: `21543017` (Asghar 1977), `21313014` (Asghar 1978), `21752017` (Wagemans
1981), `21981015` (Geltenbort 1985), `23551003` and `23551004` (Konecny 1970), the second combined
over `MISC1` to `MISC3`, which hold cooling times, `235580032` (Günther 1972), `31797003`
(Bakhromi 1982) and `41496005` (Aleksandrov 1994), interpolated from non-integer masses. For
239-Pu five: `21544009` (Asghar 1978), `21981016` (Geltenbort 1985), `235580022` (Günther 1972),
`23583003` (Boucheneb 1991) and `416930051` (Belyaev 1988). For 233-U two: `21981014`
(Geltenbort 1985) and `23784003` (Chebboubi 2021).

## Prompt γ rays

The archive codes prompt γ rays with the photon as the product, `0-G-0`, and returns them under
the quantities `FY` and `E`: the multiplicity per fission as `0-G-0,PR,FY` (the photons per
fission of LEXFOR, Multiplicity), the energies as `0-G-0,PR,KE`, and the values of one fragment
against its mass with `G` as the particle considered, `MASS,PRE/PR/FRG,FY,G`. The γ codes stay
refused for every other ordinate.

| Configuration | Holds | Header |
| :--- | :--- | :--- |
| `<system>_M_gamma_bar` | the prompt γ multiplicity per fission | `M_gamma_bar M_gamma_bar_uncertainty` |
| `<system>_E_gamma_tot` | the total prompt γ energy per fission, MeV | `E_gamma_tot E_gamma_tot_uncertainty` |
| `<system>_eps_gamma` | the mean energy of a prompt photon, MeV | `eps_gamma eps_gamma_uncertainty` |
| `Cf252_sf_M_gamma_vs_A`, `U235_nth_M_gamma_vs_A` | the multiplicity of one fragment against its pre-neutron mass | `A M_gamma M_gamma_uncertainty` |
| `Cf252_sf_E_gamma_vs_A` | the γ energy of one fragment against its pre-neutron mass | `A E_gamma E_gamma_uncertainty` |
| `Cf252_sf_E_gamma_tot_vs_A` | the total γ energy per fission against the light-fragment mass | `A E_gamma_tot E_gamma_tot_uncertainty` |
| `Cf252_sf_M_gamma_bar_vs_A`, `U235_nth_M_gamma_bar_vs_A` | the multiplicity per fission against the pre-neutron mass of one fragment | `A M_gamma_bar M_gamma_bar_uncertainty` |
| `U235_nth_eps_gamma_vs_A` | the mean photon energy against the heavy-fragment mass | `A eps_gamma eps_gamma_uncertainty` |
| `Cf252_sf_M_gamma_bar_vs_TKE` | the multiplicity per fission against TKE | `TKE M_gamma_bar M_gamma_bar_uncertainty` |
| `Cf252_sf_E_gamma_tot_vs_TKE` | the total γ energy per fission against TKE | `TKE E_gamma_tot E_gamma_tot_uncertainty` |
| `Cf252_sf_E_gamma_tot_vs_nu` | the total γ energy per fission against the number of neutrons the fission emitted | `nu E_gamma_tot E_gamma_tot_uncertainty` |

A quantity per fission is written one value to a file. A dataset giving several, two detectors of
one experiment in one table as Qi 2018 does, is refused with its values rather than combined into
one no publication states, and a dataset tabulated over bins of γ energy, as Verbinski 1973 is, is
refused as tabulated against them.

**What defines a value.** The total γ energy per fission differs between experiments by up to
about 1 MeV on its definition alone: the γ-energy range the photons were counted over, the time
window after fission, and the corrections made for what lies outside either. Each dataset records
them as read and is never cut on them. The range comes from the headings `E-MIN` and `E-MAX` of
the entry, in its DATA table or a COMMON section, where they state one; a range, a window, a time
resolution or a correction stated in the text of the entry, or in the publication it cites, is a
curated statement, verbatim, looked for in the text at every retrieval and recorded with the place
it stands. `gamma_definition_warning` names the datasets whose range or window nobody states, as
the 1972 report of Pleasonton (14214) states neither for any of its four systems. A set the
archive codes partial, `PR/PAR` over a stated range, is written beside the full-range sets and
named in `gamma_range_warning`: Makii 2019 counts 2.29 photons per fission over 1 to 6 MeV, a third
of the full multiplicity.

**Which energy.** The archive codes the total energy per fission and the mean photon energy alike,
`0-G-0,PR,KE`: 14214029 holds 0.85 MeV per photon and 143870062 9.0 MeV per fission under the same
code, and `MSC` marks the total in one entry and the mean in another. The magnitude decides, the
total lying between 3 and 15 MeV and the mean between 0.3 and 2.5 MeV, and the REACTION text is the
basis where it names the same quantity ("Total gammas energy.", "Average gamma energy per gamma");
a text naming the other refuses the dataset, and a reading on magnitude alone is named in
`quantity_reading_warning`. Mehta 1973 (entry 23213), whose codes leave the branch blank, and the
energy of one fragment of Krupa 2004 are read from their subentry text.

**Values outside the tables.** Oberstedt 2013 (235-U), Gatera 2017 (239-Pu) and Makii 2019 state the
total γ energy per fission with its uncertainty in the additional results of their entries and in
no DATA table. These are written as datasets named after the subentry that states them, once the
words are found in its text and both numbers stand in them; nothing is formed from the
multiplicity and the mean energy. `stated_value_warning` names them. A total stated in an
auxiliary column with no uncertainty beside it, as Smith 1956 and Sokol 1991 give theirs in MISC,
is no dataset; the value, its words and their place are kept in a reason among the rejections of
the observable it would answer, and so is the mean photon energy of Krupa 2004.

**By name.** Skarsvåg 1970 (23174004), the multiplicity per fission above 100 keV, is listed by the
archive under the quantity `MLT` alone. The multiplicity per fission admits it by name, records
`listed_under = "MLT"`, and takes nothing else from that quantity.

**A row as it stands.** Pleasonton's multiplicity of one fragment at A = 82, −0.36 ± 1.36, is
below zero and consistent with it; it is written as the archive gives it, since dropping it would
bias the row, and `row_notes` says so.

**What is refused.** K X-rays (Kapoor 1968 and 1969, Popeko 1975), discrete lines of individual
products, delayed γ rays, the γ field of a source measured without fission coincidence, and the
values of one fragment group in 14214, which are kept in the reason of their refusal with their
values. Uncorrected values (`RAW`) are refused beside their corrected ones.

**Thermal.** The archive lists datasets without an incident-energy window, so each record states
the incident energy that put a dataset in the window and the heading it comes from. The rendering
of entry 31729 gives the temperature of its cold beam, `KT-K` 100 K, as an incident energy of
100 eV; it is read as kT = 8.6 meV and the reading recorded.

| Configuration | Cf252_sf | U235_nth | Pu239_nth | U233_nth |
| :--- | ---: | ---: | ---: | ---: |
| `M_gamma_bar` | 15 | 11 | 5 | 1 |
| `E_gamma_tot` | 12 | 5 | 5 | 1 |
| `eps_gamma` | 9 | 10 | 5 | 1 |
| `M_gamma_vs_A` | 1 | 1 | | |
| `M_gamma_bar_vs_A` | 2 | 1 | | |
| `eps_gamma_vs_A` | | 1 | | |
| `E_gamma_vs_A`, `E_gamma_tot_vs_A`, `M_gamma_bar_vs_TKE`, `E_gamma_tot_vs_TKE`, `E_gamma_tot_vs_nu` | 1 each | | | |

## Not covered

The centre-of-mass spectrum Φ(ε) is not retrieved. The archive does not carry it as a quantity of
its own, so a measurement in the centre of mass is compiled under the same reaction code as a
laboratory-frame one. The subentry heads its energy column `E-CM`, and `23268009` (Göök, 2014), such a dataset, is
rejected by `Cf252_sf_spectrum_vs_E` on that heading rather than retrieved alongside laboratory
spectra. The refusal concerns spectra: the mean neutron energy is read from `DATA-CM` where its
subentry heads it so.

The prompt fission γ-ray spectrum (`0-G-0,PR,FY/DE`), the distribution of the γ multiplicity
(`0-G-0,NUM,FY`) and the γ values of one fragment group, light or heavy, are not retrieved; the
last are kept in the record of the dataset that gives them; see [Prompt γ rays](@ref).

P(ν) of the fission is retrieved, as `multiplicity_distribution`; P(ν) per fragment and the
variance of ν against mass or TKE are not.

Ratios of the spectra of two neutron-induced systems — the `(A(n,f),PR,NU/DE)/(B(n,f),PR,NU/DE)`
form the archive holds a good deal of — are a distinct observable and remain excluded. The ratio
to the spectrum of 252-Cf(sf) is not: that is `spectrum_cf252_ratio`, and the ratio to a
Maxwellian is `spectrum_maxwellian_ratio`.

## Relative data

A prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
so for 235-U(n,f) most of what the archive holds is in arbitrary units: of the 125 datasets
offered under `MFQ`, 42 answer the query in arbitrary units against 15 in absolute ones, and a
thermal window narrows both to 11 and 6. Those datasets are retrieved, and **written under
`relative/` rather than beside the absolute ones**:

```
data/U235_nth/spectrum_vs_E/
├── *.dat        # absolute, PC/FIS/MEV or 1/EV
├── relative/    # arbitrary units — a shape, with no scale
├── subentries/
└── retrieval.toml
```

The separation is the point. A relative dataset cannot be put on a common scale with anything,
not even another relative dataset: each has to be normalised on its own before it is compared
with anything, and none may be averaged with absolute data. A reader that takes a whole directory
therefore cannot pick one up by accident. The run record marks each accepted dataset
`relative = true` or `false` and names them all in one warning.

This applies to the spectrum ordinates and to the joint yield Y(A, TKE) alone. A joint yield is
recorded event by event and published as counts on a grid, and what it carries is the TKE
distribution at each mass, which a consumer normalises to a mass yield. For every other
observable arbitrary units are still fatal, because a relative value there is not interpretable —
a one-dimensional Y(A) in counts has no scale to be read off, a kinetic energy in arbitrary units
is not an energy, and a multiplicity is a count whose scale is the whole quantity.

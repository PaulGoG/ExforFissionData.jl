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

| Ordinate | Symbol | Meaning |
| :--- | :--- | :--- |
| `yield` | `Y` | fission yield |
| `multiplicity`, `multiplicity_per_fission` | `nu`, `nu_bar` | prompt neutron multiplicity, per fragment and per fragment pair |
| `multiplicity_distribution` | `P` | probability of emitting ν neutrons in a fission |
| `fragment_kinetic_energy`, `product_kinetic_energy` | `E_K`, `E_K_p` | pre- and post-neutron fragment kinetic energy |
| `total_kinetic_energy`, `post_neutron_total_kinetic_energy` | `TKE`, `TKE_p` | pre- and post-neutron total kinetic energy |
| `total_kinetic_energy_dispersion` | `sigma_TKE` | standard deviation of the pre-neutron total kinetic energy at fixed mass |
| `neutron_kinetic_energy` | `eps` | mean centre-of-mass energy of the prompt neutrons of a fragment |
| `neutron_spectrum_temperature`, `neutron_spectrum_exponent` | `T`, `lambda` | temperature and exponent of the form fitted to the centre-of-mass neutron spectrum |
| `spectrum`, `spectrum_maxwellian_ratio`, `spectrum_cf252_ratio` | — | prompt fission neutron spectrum: absolute, as a ratio to a Maxwellian, and as a ratio to that of 252-Cf(sf) |

An abscissa is a **list**, because it is a joint index: `["mass"]`, or
`["mass", "total_kinetic_energy"]` for ν(A, TKE). A joint abscissa is therefore no separate
vocabulary item, and the directory it writes to is the ordinate, `vs`, then the abscissa
symbols — `nu_vs_A_TKE`, `Y_vs_A`, `spectrum_maxwellian_ratio_vs_E`.

The eight abscissae the archive can be asked for are `["mass"]`, `["product_mass"]`, `["charge"]`,
`["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]`,
`["mass", "total_kinetic_energy"]` and `["neutron_number"]`.

Each ordinate belongs to one EXFOR quantity code — `yield` to `FY`, the multiplicities to `NU`,
the kinetic energies to `E`, the spectra to `MFQ` — and the configuration does not name it: the
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

`neutron_spectrum_temperature` and `neutron_spectrum_exponent` are the temperature T and the
exponent λ of the form const η^λ exp(−η/T) fitted to the centre-of-mass spectrum of the neutrons
of a fragment of given mass. Against `["mass"]`, T is written under `T_vs_A/` as
`A T T_uncertainty` in MeV, and λ, a pure number, under `lambda_vs_A/` as
`A lambda lambda_uncertainty`. EXFOR has no code for either; they sit in `MISC` columns of the
mean neutron energy. Like the width of the TKE distribution they are therefore read only from the
columns a configuration names, one `[[fit_parameter]]` table per dataset with the keys `subentry`
and `column` (see [Configurations](configurations.md)), and the uncertainty is the column
`<column>-ERR` ([`PARAMETER_ORDINATES`](@ref)). The dataset is selected as the mean neutron
energy is, by the same tag rule, the 5 MeV bound and the frame. The record gives, per dataset,
`parameter_column`, `parameter_unit` and `parameter_is`, and the form fitted with the equation of
the publication as `fit_form` and `fit_evidence` ([`SPECTRUM_FITS`](@ref)).

`Cf252_sf_T_vs_A` reads `MISC1` of `23175012` (Budtz-Jørgensen 1988), 79 masses with T from 0.77
to 1.39 MeV, and `MISC` of `23268011` (Göök 2014), 82 masses of its 109, from 0.72 to 1.40 MeV;
`Cf252_sf_lambda_vs_A` reads `MISC2` of `23175012`, 79 masses with λ from 0.11 to 0.94.
Budtz-Jørgensen fits Eq. (8) of the article, the cascade
evaporation spectrum of Le Couteur and Lang, with λ and T free; the subentry calls the same form
a Weisskopf spectrum. Göök 2014 fits Eq. (14) of
[doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611),
φ(η) ∝ η^λ exp(−η/T_eff), and its λ, Fig. 18c, is not in the archive. The archive holds no such
column for the other systems.

## Spectrum ratios

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
or charge (`MASS`, `ELEM`), an evaluation (`EVAL`: `V0045011` to `V0045013`, Holden 1988) and one
derived from a model (`DERIV`: `30544002`, a simulated binomial distribution). Arbitrary units
are refused: `14064003` holds counts, and `23598004` distributions for the fragment charges 42
and 56.

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
| `U235_nth_P_vs_nu` | `12833007` Gwin 1984 (2.437), `30046008` Boldeman 1967 (2.416), `30772010` Boldeman 1985 (2.406), `32820002` Huang 1961 (2.44) | `12337009` Diven 1956, at 80 keV; `30544002`; `V0045012` |
| `Pu239_nth_P_vs_nu` | `12833008` (2.888), `30046009` (2.924; sum 1.010, not normalised), `30772011` (2.879) | `12337010`, at 80 keV; `V0045013` |
| `U233_nth_P_vs_nu` | `12833006` (2.494), `30046007` (2.483), `30772009` (2.480) | `12337008`, at 80 keV; `V0045011` |

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

## Not covered

Fragment and prompt-neutron observables only. Prompt-γ quantities — ⟨Eγ⟩(A), ⟨Nγ⟩(A) and the
prompt fission γ-ray spectrum — are outside the observable set, as is the centre-of-mass spectrum
Φ(ε), which the archive does not carry as a quantity of its own — with the consequence that a
measurement in the centre of mass is compiled under the same reaction code as a laboratory-frame
one. The subentry heads its energy column `E-CM`, and `23268009` (Göök, 2014), such a dataset, is
rejected by `Cf252_sf_spectrum_vs_E` on that heading rather than retrieved alongside laboratory
spectra. The refusal concerns spectra: the mean neutron energy is read from `DATA-CM` where its
subentry heads it so.

For the prompt-γ quantities, exclusion is what the archive holds rather than a preference:

**Prompt-γ.** The quantity code is `MLT`, and it returns five datasets for 252-Cf and one for
235-U, none for 233-U or 239-Pu. Not one carries `MASS`: the largest is differential in secondary
γ energy, three are relative and miscellaneous, one is a single number, and the 235-U entry is
resonance-region. Under `MFQ` for 235-U(n,f), none of the 125 datasets carries `GAM` or a `,G`
branch, so the γ-ray spectrum is not there either.

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

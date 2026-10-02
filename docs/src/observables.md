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

| Ordinate | Symbol | Meaning |
| :--- | :--- | :--- |
| `yield` | `Y` | fission yield |
| `multiplicity`, `multiplicity_per_fission` | `nu`, `nu_bar` | prompt neutron multiplicity, per fragment and per fragment pair |
| `fragment_kinetic_energy`, `product_kinetic_energy` | `E_K`, `E_K_p` | pre- and post-neutron fragment kinetic energy |
| `total_kinetic_energy`, `post_neutron_total_kinetic_energy` | `TKE`, `TKE_p` | pre- and post-neutron total kinetic energy |
| `total_kinetic_energy_dispersion` | `sigma_TKE` | standard deviation of the pre-neutron total kinetic energy at fixed mass |
| `neutron_kinetic_energy` | `eps` | mean centre-of-mass energy of the prompt neutrons of a fragment |
| `spectrum`, `spectrum_maxwellian_ratio`, `spectrum_cf252_ratio` | — | prompt fission neutron spectrum: absolute, as a ratio to a Maxwellian, and as a ratio to that of 252-Cf(sf) |

An abscissa is a **list**, because it is a joint index: `["mass"]`, or
`["mass", "total_kinetic_energy"]` for ν(A, TKE). A joint abscissa is therefore no separate
vocabulary item, and the directory it writes to is the ordinate, `vs`, then the abscissa
symbols — `nu_vs_A_TKE`, `Y_vs_A`, `spectrum_maxwellian_ratio_vs_E`.

The seven abscissae the archive can be asked for are `["mass"]`, `["product_mass"]`, `["charge"]`,
`["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]` and
`["mass", "total_kinetic_energy"]`.

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
`ordinate_frame_evidence` ([`ordinate_frame`](@ref)): `centre_of_mass` where the subentry heads
the value `DATA-CM` or its text says so, as the `REACTION` text of `41502009` (Batenkov 2004)
does; `unstated` where the heading is `DATA` and the text names no frame. A dataset of unstated
frame is written and flagged, among its `qualifiers` by an entry beginning `frame unstated:` and
in `frame_warning` under `[datasets]`; `23175012` (Budtz-Jørgensen 1988), `41689005` (Piksaykin
1977), `14369005` (Fraser 1966) and `22660004` (Nishio 1998) are such datasets. A value stated to
be in the laboratory frame is refused, and no dataset of the shipped configurations is. The frame
is read from the subentry alone; what a publication adds is quoted in the evidence and does not
change the reading. For `23175012` the authors' contribution to INDC(NDS)-220 (Mito 1988, p. 199)
gives the same figure as the average neutron energy in the centre-of-mass system of the
fragment, which the subentry does not repeat.

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

## Not covered

Fragment and prompt-neutron observables only. Prompt-γ quantities — ⟨Eγ⟩(A), ⟨Nγ⟩(A) and the
prompt fission γ-ray spectrum — are outside the observable set, as are the neutron multiplicity
distribution P(ν) and the centre-of-mass spectrum Φ(ε), the last of which the archive does not
carry as a quantity of its own — with the consequence that a measurement in the centre of mass is
compiled under the same reaction code as a laboratory-frame one. The subentry heads its energy
column `E-CM`, and `23268009` (Göök, 2014), such a dataset, is rejected by
`Cf252_sf_spectrum_vs_E` on that heading rather than retrieved alongside laboratory spectra.
The refusal concerns spectra: the mean neutron energy is read from `DATA-CM` where its subentry
heads it so.

For the first two, exclusion is what the archive holds rather than a preference:

**Prompt-γ.** The quantity code is `MLT`, and it returns five datasets for 252-Cf and one for
235-U, none for 233-U or 239-Pu. Not one carries `MASS`: the largest is differential in secondary
γ energy, three are relative and miscellaneous, one is a single number, and the 235-U entry is
resonance-region. Under `MFQ` for 235-U(n,f), none of the 125 datasets carries `GAM` or a `,G`
branch, so the γ-ray spectrum is not there either.

**P(ν).** The distribution is coded `NUM` in the branch field — `,PR/NUM,NU` and `,NUM,NU` — and
is returned under `NU`, so the package already sees it and rejects it on tags. It cannot be
written: of the 33 such datasets across these four systems, 31 carry no abscissa column at all,
and the two exceptions carry one held constant over every row. In the `op=csv&plus=2` rendering
the neutron number exists only as the order of the rows. Retrieving it would mean asserting that
the nth row is ν = n−1 — an assumption about an entry's internal ordering that the rendering never
states, and which a file of one row per abscissa *value* would then present as data.

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

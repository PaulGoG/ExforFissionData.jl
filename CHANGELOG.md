# Changelog

Notable changes to ExforFissionData.jl. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The first author in a file name keeps only the characters `[A-Za-z0-9.-]`, so that no file name
  needs quoting: `40235003_P.P.D'yachenko_1969.dat` is now `40235003_P.P.Dyachenko_1969.dat`, and
  likewise `40235017` (235-U ⟨TKE⟩(A) and σ_TKE(A)) and `40472003` (Kotel'nikova 1975, 252-Cf
  spectrum). The run record keeps the author verbatim, and spellings EXFOR gives one person in
  different entries stay distinct.

## [0.2.2] - 2026-10-01

One rule change: whether a multiplicity coded without `FRG` is per fragment or per fission is
settled by its data, and its scale is recorded rather than required, so that five datasets
refused by 0.2.1 are written, two each for 252-Cf and 239-Pu and one for 235-U.

### Changed

- Prompt multiplicities against mass coded without `FRG` are classified by their data alone, and
  the scale of the reading is recorded rather than required. A dataset tabulated on both sides of
  symmetry is read per fragment when its pair sum S, weighted with the light-fragment yield, lies
  within 25 % of ν̄ and ν(A) = ν(A₀ − A) is rejected, and per fission when S lies within 25 % of
  2ν̄ and the equality holds. A consulted publication corroborates a reading but no longer
  decides it. Five datasets refused by 0.2.1 are accepted: `14652004` (Britt 1964) and
  `41689004` (Piksaykin 1977) for 252-Cf, `22650004` (Tsuchiya 2000) and `41502006` (Batenkov
  2005) for 239-Pu, and `41502005` (Batenkov 2005) for 235-U. Accepted ν(A) sets rise from 13 to
  15 for 252-Cf, from 5 to 7 for 239-Pu and from 10 to 11 for thermal 235-U; 233-U, 235-U in the
  resonance region and every ν(A, TKE) are unchanged. `41502007` and `41712005` are read per
  fragment too, but lie in the 0.296 eV resonance and in 18-u mass groups, and are not written.
  `23118007` (Zeynalov 2011) remains undecided, and the four sets against the mass ratio refused.
- The pair sums of `21834009` and `21834010` (Müller 1981) are weighted with the yields of the
  same measurement at the same incident energy, `21834002` and `21834003`, rather than the
  thermal yields of Geltenbort 1985.

### Added

- The run record of each multiplicity read by the complement test carries
  `classification_basis`, `data` or `data+paper`, and, for a dataset tabulated on both sides of
  symmetry, `pair_sum_deviation` with its uncertainty, the yields it was weighted with
  (`pair_sum_yields`, `pair_sum_yields_own`) and `scale_consistent`, false beyond three standard
  deviations and absent where no uncertainty is stated. `pair_sum_warning` names the accepted
  datasets whose scale is not that of ν̄, `22650004` at +3.9 ± 0.6 % and `41502006` at
  −10.7 ± 1.3 %; their values are written uncorrected.

## [0.2.1] - 2026-10-01

Two corrections to what 0.2.0 writes. A missing uncertainty is written `NaN` rather than 0, and
prompt multiplicities against mass coded without `FRG` are read from their data, so that 252-Cf
gains three per-fragment ν(A) sets and one ν(A, TKE) set.

### Fixed

- A missing uncertainty is written `NaN`, never 0. A row whose uncertainty the archive leaves
  blank, while other rows of its dataset carry one, was written with a zero, and so was a row
  interpolated next to it, indistinguishable from a stated zero; 2975 rows of 57 files change,
  among them 40 of the 69 of `41397004` (Apalin 1965) and 49 of the 60 of `140650021` (Bowman
  1963). A zero is written only where EXFOR states it, as on two lines of `23764004`. The run
  record counts the lines stating a zero uncertainty, `uncertainty_zero_rows`, and those stating
  none, `uncertainty_absent_rows`, and states the convention beside `absent_uncertainty`.
- Prompt multiplicities against fragment mass coded without `FRG` are read from their data by a
  complement test instead of being refused as pair data whatever they hold. A dataset is read per
  fragment when ν(A) − ν(A₀ − A) changes sign along the sawtooth and the pair sum weighted with
  the light-fragment yield agrees with ν̄ of the IAEA standards 2017
  ([doi:10.1016/j.nds.2018.02.002](https://doi.org/10.1016/j.nds.2018.02.002)), and its
  publication agrees; per fission when ν(A) = ν(A₀ − A) or, on one side of symmetry, when it
  equals the pair sum of a per-fragment dataset of its entry. Read per fragment and accepted:
  `23268005` (Göök 2014, [doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611)),
  `23118006` (Zeynalov 2011, [doi:10.3938/jkps.59.1396](https://doi.org/10.3938/jkps.59.1396)),
  `23175008` and, against mass and TKE, `23175010` (Budtz-Jørgensen 1988,
  [doi:10.1016/0375-9474(88)90508-8](https://doi.org/10.1016/0375-9474(88)90508-8)). Accepted
  ν(A) sets for 252-Cf rise from 10 to 13 and ν(A, TKE) sets from 7 to 8; 235-U, 239-Pu and 233-U
  are unchanged. Seventeen datasets are per fission, as coded, among them `23268007`, `22660006`
  and `41397006`. Refused under both readings, with the test values as the reason: `22650004`
  (Tsuchiya 2000) and `41502006` (Batenkov 2005), per fragment by their shape but with a pair
  sum 3.9 % above and 10.7 % below ν̄; `41502005`, `41502007`, `41689004` and `41712005`, whose
  publications could not be consulted; `14652004` (Britt 1964), which states no uncertainty;
  `23118007`, which the test does not decide; and four datasets against the mass ratio. The
  readings, with their test values, are in `src/curation.jl` and in each run record.

### Changed

- An entry whose masses are provisional is refused for that reason before its reaction code is
  tested, so its record names it: `404200022` and `40420003` no longer appear as missing `FRG`.
- The README figure is redrawn from the retrievals of this version.

## [0.2.0] - 2026-10-01

The fragment-yield input of a pre-neutron Y(A, TKE) — the mass yield, the mean total kinetic
energy and its width against mass, or the joint matrix — can be taken from EXFOR for 252-Cf(sf),
235-U(nth,f), 239-Pu(nth,f) and 233-U(nth,f), measurement by measurement, and from 240-Pu(sf)
where 239-Pu(nth,f) lacks it. Retrieved files change for existing observables: masses are no
longer rounded, and post-neutron and provisional data are no longer taken for pre-neutron data.
The changes below name every dataset whose status changed.

### Added

- The width of the TKE distribution against mass, σ_TKE(A): the ordinate
  `total_kinetic_energy_dispersion`, written as `A sigma_TKE sigma_TKE_uncertainty` in MeV under
  `sigma_TKE_vs_A/`. EXFOR has no code for it (Dictionaries 34 and 236 of TRANS 9134), so it is
  read only from the columns a configuration names in `[[width]]` tables — the column, whether
  it holds a standard deviation, a variance, a FWHM or a half width, and whether of the TKE or of
  one fragment's energy — and converted to the standard deviation of the pre-neutron TKE, the
  width of a fragment of mass A by A₀/(A₀ − A). The run record gives the conversion, the mass
  range and the `MISC-COL` text of each dataset. The columns of `23012005` and `23012006`
  (Nishio 1995, [doi:10.1080/18811248.1995.9731725](https://doi.org/10.1080/18811248.1995.9731725)),
  labelled FWHM, hold half of it, as the paper's figure shows, and disagree with each other by
  29 to 32 % once converted, which the record states; the widths of `22780003` at A = 180 and
  181, 0 and 1.87 MeV, are not written.
- The joint pre-neutron yield Y(A, TKE), `yield` against `["mass", "total_kinetic_energy"]`,
  written as `A TKE Y Y_uncertainty`, one row per cell; in counts, under `relative/`. The record
  states the TKE grid and the normalisation, and lists the slices of the distribution the archive
  holds for the system.
- Configurations `<system>_TKE_vs_A`, `<system>_sigma_TKE_vs_A` and `<system>_Y_vs_A_TKE`: the
  mean TKE for 252-Cf, 235-U and 239-Pu, and the width and the joint yield for all four systems.
- 240-Pu(sf), the compound nucleus of 239-Pu(n_th,f), for what the archive lacks there:
  `Pu240_sf_sigma_TKE_vs_A` reads the dispersion of `22273023` (Schillebeeckx 1992,
  [doi:10.1016/0375-9474(92)90296-V](https://doi.org/10.1016/0375-9474(92)90296-V)), digitised
  from a figure and written unsmoothed with its scatter stated; `Pu240_sf_Y_vs_A_TKE` reads the
  raw count matrix `22413013` (Demattè 1997,
  [doi:10.1016/S0375-9474(97)00032-8](https://doi.org/10.1016/S0375-9474(97)00032-8)) from its
  subentry, in arbitrary units. Thirty-four configurations in all.
- Curated readings of datasets no reaction code describes (`src/curation.jl`), each with its
  evidence in the run record: `14101003` (Whetstone 1963,
  [doi:10.1103/PhysRev.131.1232](https://doi.org/10.1103/PhysRev.131.1232)), a double-velocity
  TKE with the branch left blank; `22780003` (Hambsch 1997), a TKE coded as one fragment's
  energy; `23268002` (Göök 2014,
  [doi:10.1103/PhysRevC.90.064611](https://doi.org/10.1103/PhysRevC.90.064611)), a Y(A, TKE)
  coded without a TKE marker, with its bin-centre grid inferred from the data and its mass
  marginal `23268003` stated.
- Compilation defects left out and recorded for the IAEA Nuclear Data Section: `14101003` gives
  MASS 133 twice and 134 never; the width column of `12709004` (Weber 1981,
  [doi:10.1103/PhysRevC.23.2100](https://doi.org/10.1103/PhysRevC.23.2100)) is an uncalibrated,
  inverted digitisation of the paper's σ(TKE).
- Repeated runs of one experiment named as `correlated_with`: the six thermal series `400170091`
  to `400170096` (Dyachenko 1969).
- `mass_range`, `uncertainty_source`, `normalisation` for yields, and the TKE grid (`tke_*`) in
  the run record.
- CI runs the plotting test suite and uploads coverage.

### Changed

- **Masses are never rounded** (breaking). Integer masses are written as given; a mass bin of at
  most 2 u is written at each of its masses for a mean, and not at all for a yield, which is a
  sum over the bin; non-integer masses are interpolated linearly onto the integer masses within
  3 u. `mass_treatment` records which applied, in place of `mass_rounding_max`. Twenty-five
  datasets of the observables of 0.1.0 are written on the new grid; `22413004` (a yield at the
  most probable mass), `10865003` (a yield summed over masses 135 and 136) and `14065006` (Bowman
  1963, ν at eight masses 4 to 9 u apart) are no longer written.
- **Reaction codes are compared code by code in their subfields** (breaking), not by substring:
  `DE` is no longer found inside `DERIV`, `KE` inside `KEP`, `KEM` or `TKE`, `PR` inside `PRE`.
  `AKE` stays a synonym of `KE`; every combination of reactions is refused; rejection reasons name
  the code and its subfield. Five `DERIV` sets are now admitted and flagged; no dataset of the
  existing configurations changed status.
- An arbitrary scale the subentry gives is not overruled by the csv rendering, which misstates it
  for `23268002`; and an uncertainty the rendering drops is read from the subentry, which gives
  `14369002`, `14369003`, `14369004` (Fraser) and `30426002` (Lajtai) their uncertainties.
- The run record's `timestamp` is `timestamp_utc`, in UTC like every other date it carries.
- Retrieval retries only transport failures; any other exception propagates instead of being
  filed as a rejection.

### Fixed

- Y(A) is the pre-neutron yield: `PRE` is required, and chain yields (`CHN`) and provisional ones
  (`PRV`) are refused. Accepted Y(A) sets fall from 29 to 15 for 252-Cf, 53 to 22 for 235-U, 26
  to 8 for 239-Pu and 17 to 5 for 233-U: 69 chain yields and 5 provisional ones (`23802002`,
  `23815002`, `23815003`, `23815005`, `23588002`) leave, and `22413004` above.
- Entries whose masses are provisional are refused against pre-neutron mass: 40232 and 40420
  (Zakharova 1973, 1979), so `404200021` leaves `Cf252_sf_nu_vs_A` and `40420005`
  `Cf252_sf_nu_vs_A_TKE`.
- The mean TKE against mass refuses `MSC` and `KEP`: `33082004` (TKE of fragments with
  provisional masses) and `41109007` (a mean over cold-fragmentation events) are no longer
  accepted.
- The post-neutron TKE requires `SEC`; a blank branch no longer passes for post-neutron.
- A csv rendering cached while the archive returned only its header was served as an empty
  dataset for as long as the cache lived; such a rendering is now refetched. Three datasets had
  been reported empty this way: `22413013`, now accepted, and `227980081` and `23012009`, now
  refused on their codes, so no count above changes.
- A developed checkout kept its previous version in the user agent after the version changed,
  the precompiled image not depending on `Project.toml`.

### Removed

- The exported constants `QUANTITIES` and `REACTIONS`, which nothing used; the quantity and
  reaction codes are read from `ORDINATE_QUANTITY` and `CHANNEL_REACTION`.
- `mass_rounding_max` from the run record, masses being no longer rounded.

## [0.1.0] - 2026-09-23

### Added

- Retrieval of fission observables from the IAEA EXFOR archive, driven by a validated TOML
  configuration: seven abscissae, ten ordinates and four entrance channels.
- A run record, `retrieval.toml`, naming every dataset kept or excluded with the reason, dated by
  the listing and by each dataset.
- Reaction-code qualifiers bearing on a value's scale or on the inducing neutron spectrum,
  recorded per dataset.
- The abscissa and the other independent variables read from the subentry DATA table, with
  masses rounded to the nearest integer.
- Relative spectra, written under `relative/` apart from the absolute data.
- An on-disk response cache, with `offline`, `refresh` and `max_age_days` under `[retrieval]`.
- Bounded concurrency, per-request timeouts and exponential backoff.
- An identifying `User-Agent` header on every request.
- `AcceptedDataset` and `ReducedDataset` exported.
- Survey and coverage figures in `plotting/`, in an environment of their own.
- 21 configurations for 252-Cf(sf), 235-U(n,f) thermal and resonance, 233-U(n,f) and
  239-Pu(n,f).
- `check.jl`, the formatting and test gate.
- `CITATION.cff`.

### Changed

- One quantity vocabulary throughout: output is written to `data/<system>/<observable>/`,
  configurations name quantities in words, paths and headers carry their symbols, and an
  uncertainty column is `<quantity>_uncertainty`.
- The target is named by `target_Z` and `target_A`.
- `[query] reaction`, `quantity` and `spontaneous` are no longer in configurations or run
  records; the channel and the ordinate determine them.
- The incident-energy window lies inside the channel's interval and defaults to it; the
  `U235_nres` runs no longer duplicate the thermal datasets.
- A dataset tabulated against a variable the abscissa does not hold is rejected where that
  variable varies (`23591005`, `23268002`).
- `yield` requires the `FY` tag, which removes six `MASS,PAR,ZP` datasets for 235-U from the mass
  yields.
- Centre-of-mass spectra are rejected (`23764006`, `23764007`, `41516007`, `41516008`).
- The dataset listing is requested on every run that is not offline.
- `[output] significant_digits` replaces `digits` and rounds to significant digits.
- The manifests are no longer tracked.

### Fixed

- Small ordinate values written away by rounding to decimal places.
- The cache storing failed responses and serving them indefinitely.
- The subentry of a pointer dataset requested under its nine-character identifier.
- Isomer totals averaged together with their resolved states.
- The package revision taken from an enclosing repository.
- Arbitrary-units and upper-limit rows admitted as measurements.

### Corrections relative to the `legacy` branch

- The value-kind column was misread: the arbitrary-units test compared single characters against
  `"ARB"` and never fired, and `Max(` upper limits were written as measurements.
- The `(Z, A')` export passed a three-name header for four columns when a dataset quoted no
  uncertainties, and wrote a malformed file.
- The ordinate rescaling guessed a normalisation from the data range, threw on a missing ordinate
  and looped forever on a zero maximum; no normalisation is applied.
- The incident-energy window tested the first row and admitted every energy in the dataset,
  averaging excitation functions into single numbers.
- Duplicate abscissa values received one unweighted mean regardless of cause; incident energy,
  isomeric states and genuine repeats are treated separately.
- Light charge-coded products passed the bare-mass test: an α from ternary fission, `ProdZA`
  2004, fell below the 10⁴ threshold.
- Output order followed thread scheduling, so no two runs agreed.
- A cache temporary named from the process id alone could be chosen by two tasks at once.

[Unreleased]: https://github.com/PaulGoG/ExforFissionData.jl/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/PaulGoG/ExforFissionData.jl/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/PaulGoG/ExforFissionData.jl/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/PaulGoG/ExforFissionData.jl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/PaulGoG/ExforFissionData.jl/releases/tag/v0.1.0

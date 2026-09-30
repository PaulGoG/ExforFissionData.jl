# Changelog

Notable changes to ExforFissionData.jl. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The fragment-yield input of a pre-neutron Y(A, TKE) — the mass yield, the mean total kinetic
energy and its width against mass, or the joint matrix — can be taken from EXFOR for 252-Cf(sf),
235-U(nth,f), 239-Pu(nth,f) and 233-U(nth,f), measurement by measurement. Retrieved files change
for existing observables: masses are no longer rounded, and post-neutron and provisional data are
no longer taken for pre-neutron data. The changes below name every dataset whose status changed.

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

[Unreleased]: https://github.com/PaulGoG/ExforFissionData.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/PaulGoG/ExforFissionData.jl/releases/tag/v0.1.0

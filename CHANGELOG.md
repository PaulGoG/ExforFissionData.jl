# Changelog

Notable changes to ExforFissionData.jl. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- CI runs the plotting test suite and uploads coverage.

### Changed

- The run record's `timestamp` is `timestamp_utc`, in UTC like every other date it carries.
- Retrieval retries only transport failures; any other exception propagates instead of being
  filed as a rejection.

### Removed

- The exported constants `QUANTITIES` and `REACTIONS`, which nothing used; the quantity and
  reaction codes are read from `ORDINATE_QUANTITY` and `CHANNEL_REACTION`.

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

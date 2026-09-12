# Changelog

Notable changes to ExforFissionData.jl. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Retrieval of fission observables from the IAEA EXFOR archive, driven by a validated TOML
  configuration: seven abscissae (`A`, `Ap`, `Z`, `ZAp`, `E`, `TKE`, `ATKE`) against ten
  ordinates.
- A run record, `retrieval.toml`, naming every dataset considered — those written, with what the
  reduction did to each, and those excluded, with the reason. A dataset missing from the output
  is otherwise indistinguishable from one the archive does not hold.
- Reaction-code qualifiers bearing on a value's scale (`MSC`, `REL`, `CHN`, `DERIV`, `FCT`) and
  on the inducing neutron spectrum (`MXW`, `SPA`, `FST`, `EPI`, `THR`) recorded per dataset.
- A warning when one query returns datasets carrying more than one unit token, which must not be
  renormalised together.
- On-disk response caching, bounded concurrency, per-request timeouts and exponential backoff.
- Survey figures in `plotting/`, detached from the retrieval package and carrying their own
  environment.
- Validation of every abscissa and ordinate combination against the live archive for
  252-Cf(sf), 235-U(n,f), 233-U(n,f) and 239-Pu(n,f).
- A consistency check between the ordinate and the EXFOR quantity code. The quantity decides
  which datasets the archive offers, and several ordinates impose no tags of their own, so asking
  for `yield` under `NU` retrieved prompt multiplicities written as yields — fifteen such datasets
  for 252-Cf — and under `E` retrieved kinetic energies. The pairing is now refused.
- `check.jl`, applying the same formatting gate as CI and then the tests.
- Configurations for 233-U, 235-U and 239-Pu alongside 252-Cf.

### Fixed

Corrections relative to the script this package replaces, preserved on the `legacy` branch:

- The arbitrary-units rejection compared each character of the value-kind column against the
  string `"ARB"` and so never fired. Such rows carry no scale and are now excluded; they account
  for 20 of 1594 rows sampled across 126 datasets.
- Upper limits, which the same column marks with a `Max(` prefix, were written as measurements.
- The `(Z, A')` export passed a three-name header for a four-column frame when a dataset quoted
  no uncertainties, which CSV.jl does not reject: it wrote a malformed file with the fourth value
  on its own line.
- The ordinate rescaling multiplied by ten until the maximum fell in a fixed interval, guessing
  the normalisation from the data range. It threw on a missing ordinate and looped forever when
  the maximum was zero. No normalisation is applied now.
- The incident-energy window tested the first row and then admitted every energy in the dataset,
  which averaged excitation functions into single numbers.
- Duplicate abscissa values received one unweighted mean regardless of cause. Incident energy,
  isomeric states and genuine repeats are now distinguished and treated separately.
- Light charge-coded products passed the bare-mass test: `ProdZA` is `1000·Z + A`, so an α from
  ternary fission is 2004, below the 10⁴ threshold and four times too heavy to be a fragment.
- Output order followed thread scheduling, so no two runs agreed.
- A cache temporary named from the process id alone could be chosen by two tasks at once.

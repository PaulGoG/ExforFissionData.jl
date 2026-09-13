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
- Mass yield configurations for all four systems. Validated by mass conservation: summing the
  ordinate over a complete mass range gives 2.000 to three or four significant figures, and 1.00
  over a single peak.
- A note on two known miscoded 252-Cf multiplicity subentries, which the reaction code places
  among pair data while their values are per fragment.
- Joint `ν(A, TKE)` configurations for all four systems, and resonance-region variants for 235-U
  whose incident-energy window reaches the measurements made on a resonance beam.
- `CITATION.cff`, and activation scripts for the `docs/` and `test/` environments.
- **Relative spectra are retrieved**, into a `relative/` directory of their own. The arbitrary-
  units check rejected them, which contradicted this package's own stated policy: `REL` in the
  reaction code is documented as a qualifier that is *recorded* rather than used to reject, and
  every arbitrary-units spectrum carries it. Two rules disagreed about the same datasets and the
  stricter one won silently. Since a relative dataset cannot be put on a common scale with
  anything — not even another relative one — they are written apart from the absolute data rather
  than mixed with it, so a reader that takes a whole directory cannot pick one up by accident.
  Arbitrary units remain fatal for every other ordinate. For 235-U(n,f) this recovers 42 datasets
  against the 15 in absolute units.
- Configurations for the 235-U spectrum and its Maxwellian-ratio form.
- `[output] record_hostname`, off by default. The run record is written to be committed by
  whoever consumes the data, and the machine name was the one field in it that identified a
  person rather than a result; the rest of the platform fingerprint still attributes a run to
  its hardware.

### Fixed

- **The response cache stored failures and served them forever.** A transient empty body, and the
  application-level message the archive returns with HTTP 200 when it declines a request, were
  both written to the cache as though they were data. Since an entry is otherwise fetched at most
  once, one unlucky moment removed that dataset from every later run — silently, because the
  dataset then failed the column check and was reported as a change in the csv layout. Measured on
  a cache of 4516 responses: 19 entries were poisoned, and all 19 identifiers served correct data
  when asked again. Unusable responses are now retried, never cached, and an existing poisoned
  entry counts as a miss, so a cache written before this repairs itself on the next run.
- A body the archive never sent is no longer reported as a layout change. That message sends the
  reader to `src/schema.jl` to look for a problem that is not there.
- The run record named the configuration by the absolute path it was read from. Consumers commit
  these records, so that carried the directory layout of whoever ran the retrieval into other
  repositories; it now records the file name.
- `[compat]` pinned the `Dates` and `TOML` standard libraries to patch versions, which constrains
  nothing useful and can make a declared Julia floor unsatisfiable.

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

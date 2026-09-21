# Changelog

Notable changes to ExforFissionData.jl. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Retrieval of fission observables from the IAEA EXFOR archive, driven by a validated TOML
  configuration: seven abscissae against ten ordinates.
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
- Resonance-region configurations for 235-U, kept apart from the thermal ones by their entrance
  channel.
- Requests identify the client and its version in a `User-Agent` header. The archive is a shared
  public service and this package asks its users to treat it as one; arriving anonymously while
  saying so was inconsistent, and an identified client gives whoever runs the archive something
  to look up and somebody to contact.
- `AcceptedDataset` and `ReducedDataset` are exported. Reaching a written value goes through
  both, so they were part of the result rather than internals, and a user should not have to name
  an unexported type to read what a retrieval produced.
- `[output] record_hostname`, off by default. The run record is written to be committed by
  whoever consumes the data, and the machine name was the one field in it that identified a
  person rather than a result; the rest of the platform fingerprint still attributes a run to
  its hardware.
- `plotting/coverage.jl`, which records several retrievals of one observable accumulating on
  shared axes: each frame advances through the datasets the archive offered for a query, in the
  identifier order the pipeline processes them, so that what was kept is seen against what was
  considered. The animation of the four `ν(A)` retrievals is the figure in the README. Theme,
  palette and axis labels common to the plotting scripts moved to `plotting/style.jl`.
- Survey figures draw relative datasets in a panel of their own beneath the absolute ones,
  sharing the abscissa, and put a spectrum on a log ordinate. One pair of linear axes asserted a
  comparison the data does not support — arbitrary units against absolute ones — and collapsed
  every spectrum but the largest onto the abscissa. A spectrum panel is labelled with the unit
  tokens its datasets are written in rather than with an assumed one, since nothing is normalised
  on the way out: for 252-Cf that is `1/EV` and `PC/FIS/MEV` together.
- Spectrum configurations for 252-Cf, 233-U and 239-Pu, which the archive holds 156, 27 and 61
  datasets for against the 125 for 235-U. The 252-Cf spontaneous-fission spectrum is a reference
  standard and no incident-energy window narrows it; the retrieval writes 9 absolute datasets and
  27 relative ones.
- A third known miscoded entry, `40064031` (Kroshkin, 1970): its energy column is headed `MEV`
  over values in keV, which the subentry's own text contradicts. Written as the archive states
  it, and named in the README so that a consumer meets it in the documentation rather than in a
  fit.
- A survey of what the archive holds for the prompt-γ observables and for P(ν), recorded in the
  README where it explains why both stay outside the observable set: `MLT` returns six
  heterogeneous datasets across these four systems and none of them is mass-resolved, and every
  P(ν) dataset carries the neutron number as row order alone, which is not an abscissa this
  package is willing to invent.
- `[retrieval] refresh`, which refetches every response a run touches and replaces the cached
  copy. The archive revises entries and adds new ones, and a cached response notices neither.
- The run record carries `package_version`, which identifies an installed package where no commit
  can, and names every dataset in which rows sharing an abscissa value were combined.
- A documentation page for the configurations, key by key.

### Changed

- **A dataset tabulated against a variable the abscissa does not hold is rejected where that
  variable varies.** The rendering declares what a dataset is tabulated against in `indVars`, and
  that column went unread. `23591005`, a 235-U mass yield at nine fragment kinetic energies, was
  written as one yield per mass by a mean over the nine.
- **A dataset holding several incident energies inside the window is rejected**, naming them,
  where its rows used to be combined across energies.
- **`yield` requires the `FY` tag.** The quantity code `FY` also files the most probable charge
  against mass, and six `MASS,PAR,ZP` datasets for 235-U were written among the mass yields at
  values near 40. Of the 314 datasets the shipped configurations accepted, these rules remove
  seven, all from `U235_nth/Y_vs_A`, and admit nothing new.
- A configuration section or key the loader does not know is refused, as is an incident-energy
  window on `sf`. A misspelt `energy_max` used to leave the window open to every energy.
- A response failing the column contract raises `LayoutError`. One such dataset is still recorded
  as a rejection; every dataset failing it stops the run, which previously ended by reporting
  that nothing in the archive matched.
- The manifests are no longer tracked; the formatter is pinned by an equality bound in
  `formatter/Project.toml`, and the plotting and test environments carry `[compat]`.
- Figures are drawn on a 900 × 600 canvas with LaTeX axis labels, where they were sized for a
  single journal column.
- No documented invocation passes `--project`; every script activates its own environment.
- **One name per quantity, everywhere it appears.** The configuration vocabulary, the output
  layout, the file names and the column headers now draw on a single table of quantities, so a
  name learned in one place is the name everywhere.
  - Configurations spell a quantity out — `multiplicity`, `total_kinetic_energy`,
    `spectrum_maxwellian_ratio` — where they carried symbols and camelCase (`nu`, `TKE`,
    `spectrumRatioMXW`). Paths, file names and column headers carry the symbol the literature
    uses, `nu`, `TKE`, `Y`, `A_p`.
  - An abscissa is a **list** of quantities, because it is a joint index:
    `abscissa = ["mass", "total_kinetic_energy"]`. `ATKE` and `ZAp` were composite tokens naming
    a pair with no vocabulary of their own, and now they are not vocabulary items at all.
  - Retrievals are written to `data/<system>/<observable>/` — one directory per fissioning
    system, one subdirectory per observable, the measurements directly inside it. The old layout
    was `data/<target>_<reaction>_<ordinate><abscissa>/data/`, which named a path segment `data`
    inside a `data` root and concatenated four tokens with no relation stated between them.
  - A system is an element symbol, a mass number and an **entrance channel**: `Cf252_sf`,
    `U235_nth`, `U235_nres`. `0f` was an EXFOR reaction code rather than a name, and the
    resonance runs needed an output directory of their own — `data/resonance/` — precisely
    because the old label could not tell them from the thermal ones. The channel does that now.
  - The observable directory is the ordinate, `vs`, then the abscissa symbols: `nu_vs_A_TKE`,
    `Y_vs_A`, `spectrum_maxwellian_ratio_vs_E`. `vs` is what makes a name a statement rather than
    a list of symbols.
  - An uncertainty column is `<quantity>_uncertainty`, after the quantity it belongs to, where it
    was `err<quantity>` before. `errspectrumRatioMXW` was unreadable, and an error is not an
    uncertainty. The same holds of `ReducedDataset.table`, whose ordinate column is named for the
    quantity rather than `value`.
  - `AcceptedEntry` is `AcceptedDataset` and `Reduced` is `ReducedDataset`; `query_label` is
    replaced by `system_label` and `observable_label`, one for each directory it now names.
- **The target is named by charge and mass**, `target_Z` and `target_A`, which identify a nuclide
  unambiguously. The EXFOR nuclide symbol is formed from them, so the symbol and the numbers
  beside it cannot disagree. `element_symbol` is exported.
- **`[query] reaction` and `[query] quantity` are gone.** The reaction code follows from the
  entrance channel and the quantity code from the ordinate; both were keys that could only be
  redundant or wrong. The ordinate–quantity pairing in particular was validated and refused, which
  is one way of saying it should never have been written down twice.
- **The run record drops the same keys, and `[query] spontaneous` with them.** The rule that
  emptied the configuration applies to what the configuration is recorded as: spontaneity is the
  channel being `sf`, and a record cannot state it and the channel and have them agree only by
  luck. `[query] channel` is what remains, and it is the field a consumer keys on — `n,f` is the
  reaction code of a thermal run and of a resonance run alike, so nothing else in the record
  separates the two. The reaction code the archive actually returned is not derivable from
  anything and stays where it was, on each entry of `[[accepted]]`. Records written before this
  change carry the three keys; nothing reads them, and deleting those three lines migrates a
  record in place.
- Figure labels are typeset from the channel: `²³³U(nth,f)`, `²⁵²Cf(sf)`, with the channel spelled
  as the field spells it. They were formed from the reaction code, which gave every 235-U figure
  the same label whether it came from the thermal or the resonance window.
- A configuration is refused if its ordinate repeats a quantity of its abscissa, which would write
  two columns under one name.
- `[output] digits` is now `[output] significant_digits`, and rounds to significant digits. The
  old name meant decimal places, which is a statement about the scale of a quantity rather than
  about its precision.

### Fixed

- Isomer resolution averaged the archive's totals together with the states they are totals of
  when a nuclide carried more than one unmarked row. The unmarked rows alone are combined.
- The package revision was asked of whatever repository enclosed the package directory. For an
  installed package that is the depot's parent, a home directory under version control for
  instance, whose commit was then recorded as the package's.
- The documentation called an EXFOR entry immutable once published. Entries are revised, and the
  subentries this package stores record it in their own `HISTORY`.
- The documentation said rows sharing an abscissa value were "genuine repeats". Most are
  neighbouring points of a non-integer mass scale that the rendering truncates to integers, and
  `23268002` is a Y(A, TKE) grid whose TKE column the rendering drops.
- **Small ordinate values were written away.** Rounding to seven decimal places left an absolute
  prompt fission neutron spectrum of order 1e-7 PC/FIS/MEV with one significant digit, wrote its
  uncertainties as zero, and reduced a dataset of order 1e-8 to a column of zeros: of the six
  absolute 235-U(n,f) spectra the thermal window admits, one was destroyed outright and five lost
  three digits. Rounding now follows the significant digits of the value, so the written precision
  no longer depends on the unit the archive happens to quote a quantity in.

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

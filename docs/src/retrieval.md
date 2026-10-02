```@meta
CurrentModule = ExforFissionData
```

# Retrieval and the run record

Requests run under a bounded concurrency limit with a per-request timeout and exponential
backoff, and responses are cached on disk in a `Scratch.jl` space.

EXFOR revises entries — the `HISTORY` of a subentry records each alteration, and many of those
retrieved here carry one — and adds new ones. The listing of datasets is therefore requested on
every run, since a cached listing never discovers an added entry, while dataset responses are
served from the cache. `max_age_days` under `[retrieval]` expires cached dataset responses older
than that many days, and `refresh = true` refetches everything a run touches and replaces the
cached copies. A request the archive cannot serve falls back to the cached copy, with a warning
naming its date. `offline = true` never contacts the archive and serves the cache alone.

The run record carries the date of the listing, `listing_retrieved_utc`, and of every dataset,
`retrieved_utc`, with whether each came from the cache. Those dates are what a consumer cites as
the state of the archive the data reflects.

Datasets are processed and written in identifier order, so a re-run over an unchanged archive
reproduces its output exactly.

## The run record

`retrieval.toml` holds the query, the conventions applied, the package version and — where the
package runs from a working copy — its commit, the platform, and both dataset lists — accepted,
with what the reduction did to each, and rejected, with the reason. The rejection list is the
point: a dataset missing from the output is otherwise indistinguishable from one the archive does
not hold.

It is written to be committed alongside the data, so it deliberately says nothing about who ran
it: the configuration appears by file name rather than by the path it was read from, and the
machine name is omitted. The platform fingerprint still attributes a run to its hardware — CPU
model, core counts, memory, Julia version. Set `record_hostname = true` under `[output]` to name
the machine as well, which is useful when the records stay yours.

### Fields

| Section | Key | Content |
| :--- | :--- | :--- |
| `[run]` | `timestamp_utc` | when the record was written |
| | `package_version`, `package_revision` | the installed version, and the commit of a working copy (`-dirty` with uncommitted changes; `unavailable` for an installed package) |
| | `configuration` | the configuration file, by name |
| | `system`, `observable` | the two directory tokens |
| | `listing_retrieved_utc`, `listing_from_cache` | when the archive was asked which datasets exist, and whether that answer came from the cache |
| `[query]` | `target_Z`, `target_A`, `target_symbol`, `channel`, `abscissa`, `ordinate` | the query as configured, with the EXFOR nuclide symbol formed from `Z` and `A` |
| | `energy_min_mev`, `energy_max_mev` | the incident-energy window applied, `Inf` when open |
| `[conventions]` | `energies`, `ordinate_normalisation`, `absent_uncertainty`, `duplicate_abscissa`, `abscissa_resolution`, `archive_state` | the conventions above, stated in prose for a reader of the record alone |
| | `ordinate_frame`, whose text gives the three values of `ordinate_frame_basis`, `ordinate_bound` and `mean_formation` (mean neutron energy and its fit parameters), `fit_parameter` (fit parameters of the neutron spectrum), `distribution` (P(ν)), `maxwellian_temperature` (ratio to a Maxwellian), `ratio` (ratio to 252-Cf(sf)) | the conventions of those observables, present for those observables only |
| `[platform]` | `julia_version`, `julia_threads`, `cpu_model`, `cpu_threads`, `total_memory_gb` | the hardware and runtime; `hostname` too when `record_hostname = true` |
| `[datasets]` | `accepted`, `rejected`, `relative` | counts |
| | `retrieved_earliest_utc`, `retrieved_latest_utc` | the span of the dataset retrieval dates |
| | `units_present` | every unit token among the accepted datasets |
| | `units_warning`, `relative_warning`, `scale_warning`, `pair_sum_warning`, `combined_warning`, `correlated_warning`, `frame_warning`, `orientation_warning`, `preliminary_warning` | present only when they apply, each naming the datasets concerned |
| `[[accepted]]` | `identifier`, `author`, `year`, `file` | the dataset and the file it was written to, relative to the retrieval directory |
| | `reaction_code`, `qualifiers` | the code the archive returned and the qualifiers recorded from it; for a ratio to 252-Cf(sf) the qualifiers of both reactions; for a mean neutron energy of unstated frame an entry beginning `frame unstated:`; for a dataset whose publication calls its results preliminary one beginning `preliminary:` |
| | `ordinate_frame`, `ordinate_frame_basis`, `ordinate_frame_evidence` | for a mean neutron energy, and a fit parameter read from one: its frame, `centre_of_mass` or `unstated`; what the reading rests on, `heading` (the datum is headed `DATA-CM`), `subentry` (the text of the subentry) or `publication` (the publication, quoted with its DOI); and the heading, or the words of the subentry or of the publication, it is read from |
| | `mean_formed_from`, `mean_fitted_form`, `mean_threshold_mev`, `mean_threshold_frame`, `mean_evidence` | for a mean neutron energy, and a fit parameter read from one: how the mean was formed, `measured_spectrum`, `fitted_spectrum`, `completed_spectrum` or `unstated`; the fitted form where one enters; the low-energy threshold of the neutron detection and its frame, recorded only from a publication read; and the sentence or equation, with the DOI |
| | `parameter_column`, `parameter_unit`, `parameter_is`, `fit_form`, `fit_evidence` | for a fit parameter of the neutron spectrum: the column of `[[fit_parameter]]` and its unit, what the parameter is, the form fitted, and the equation of the publication |
| | `distribution_sum`, `distribution_normalised` | for P(ν): the sum of the probabilities, and whether it lies within 0.01 of one; recorded only, the table is not renormalised |
| | `mean_multiplicity`, `mean_multiplicity_uncertainty`, `mean_nubar`, `mean_nubar_uncertainty`, `mean_deviation`, `mean_deviation_uncertainty`, `mean_consistent` | for P(ν): the mean Σ ν P / Σ P, with its uncertainty where every line states one; the ν̄ of the IAEA neutron data standards 2017 it is compared with; mean/ν̄ − 1 with its uncertainty; and whether that lies within three standard deviations of zero |
| | `maxwellian_temperature_mev`, `maxwellian_temperature_source` | for a ratio to a Maxwellian: the temperature T of the Maxwellian √E exp(−E/T) it was formed with, and where the subentry gives it |
| | `ratio_orientation`, `ratio_numerator`, `ratio_denominator` | for a ratio to 252-Cf(sf): `system_over_reference` or `reference_over_system`, and the two reaction codes |
| | `unit`, `unit_reported`, `unit_written`, `ordinate_factor` | the unit token of the csv rendering; the token the values are reported in, the rendering's unless the subentry overrules it; the token the file is written in; and the factor between the reported and the written values |
| | `unit_miscoded` | for a multiplicity whose subentry heads it `PC/FIS`: that the token is a miscoding, and that the values are written as the subentry tabulates them |
| | `relative` | whether the dataset is in arbitrary units and lies under `relative/` |
| | `retrieved_utc`, `from_cache` | when the csv response was obtained and whether from the cache |
| | `rows_retrieved`, `rows_written` | rows the archive returned, rows the file holds |
| | `incident_energies_mev` | the incident energies of the rows written |
| | `isomer_totals_used`, `isomer_states_summed`, `isomer_groups_ambiguous` | how each nuclide's isomeric rows were resolved |
| | `abscissae_combined`, `combined_over`, `weights_imputed` | abscissa values that combined several rows, the auxiliary columns that varied among them, and rows whose weight was imputed for lack of an uncertainty |
| | `mass_treatment` | how the masses were placed on the integers: `integer`, `bins` or `interpolated`; `none` without a mass abscissa |
| | `mass_values_non_integer`, `mass_interpolation_span_u`, `mass_gaps_skipped`, `mass_values_coincident` | for interpolated masses: how many were non-integer, the widest interval interpolated across, the integer masses left out in wider gaps, and the masses tabulated more than once and combined first |
| | `mass_bin_widths_u`, `mass_bins_refused` | for mass bins: their widths in mass units, and the yield bins over several masses that were not written |
| | `abscissa_binned` | whether any abscissa quantity came from a `-MIN`, `-MAX` pair |
| | `tke_heading`, `tke_convention`, `tke_step_mev`, `tke_bin_widths_mev` | for a TKE abscissa: the heading it was read from, point values or bins written at their midpoints, the spacings of the written values, and the bin widths |
| | `normalisation` | for a yield, what its subentry unit says of the scale: percent per fission summing to 200 %, per fission, or arbitrary units such as counts |
| | `uncertainty_source` | `csv`, `subentry ERR-S` and the like where the rendering carries none and the subentry does, or `none` |
| | `uncertainty_zero_rows`, `uncertainty_absent_rows` | the lines stating a zero uncertainty, written as zero, and those stating none, written `NaN` wherever the column is written |
| | `curation`, `archive_defects` | for a dataset read from its subentry text, the evidence; and the compilation defects whose lines were left out |
| | `tke_grid_inference`, `mass_marginal` | further statements of a curated reading, such as the TKE grid and the mass marginal of 23268002 |
| | `classification_basis` | for a multiplicity against mass coded without `FRG`: `data` where the complement test alone decides its reading, `data+paper` where the publication, consulted, agrees |
| | `pair_sum_deviation`, `pair_sum_deviation_uncertainty` | for such a multiplicity tabulated on both sides of symmetry: S/(kν̄) − 1, the pair sum weighted with the light-fragment yield against ν̄ (k = 1 per fragment, 2 per fission), and its standard deviation, absent where the dataset states no uncertainty |
| | `pair_sum_nubar` | the ν̄ the pair sum is compared with, so that S = kν̄(1 + `pair_sum_deviation`) can be formed again from the written table |
| | `pair_sum_yields`, `pair_sum_yields_own` | the Y(A) the pair sum is weighted with, and whether it is of the same experiment rather than the fallback for the system |
| | `scale_consistent` | whether `pair_sum_deviation` lies within three standard deviations of zero; recorded only, never a reason to refuse, and absent where no uncertainty is stated |
| | `mass_range` | the smallest and largest mass written |
| | `width_column`, `width_unit`, `width_holds`, `width_of`, `width_is`, `width_conversion` | for σ_TKE: the column and its unit, what it holds and whose energy, what the written width is, and how it was converted |
| | `width_note`, `width_rows_excluded`, `misc_columns` | for σ_TKE: evidence beyond the configuration's reading, widths not written with the reason, and every `MISC-COL` definition of the subentry quoted |
| | `correlated_with`, `correlation` | the other runs of the same experiment, and why they are one |
| `[[slices]]` | `identifier`, `holds`, `energies`, `masses`, `source` | for Y(A, TKE) only: datasets holding slices of the joint distribution for the system, rejected as the distribution and listed for cross-checks at their masses |
| `[[rejected]]` | `identifier`, `reaction_code`, `reason` | the dataset, its code, and why it was excluded |

## Output layout

Retrieved data lands in `data/<system>/<observable>/` and is not version-controlled.

One directory per fissioning system, one subdirectory per observable, one file per measurement:

```
data/Cf252_sf/nu_vs_A/
├── retrieval.toml                        # the run record
├── 41425014_A.S.Vorobiev_2001.dat        # identifier, first author, year
└── subentries/
    └── 41425014_A.S.Vorobiev_2001.txt    # the original EXFOR subentry
```

The author in a file name keeps only the characters `[A-Za-z0-9.-]`, so that EXFOR's
`P.P.D'yachenko` is written `40235003_P.P.Dyachenko_1969.dat`. The run record keeps the author
verbatim, and spellings that EXFOR gives one person in different entries are not merged.

A dataset identifier with a ninth character, such as `400170021`, is a pointer into a subentry
shared by several datasets, and the text stored beside it is that whole subentry.

Data files are space-separated with a single header line — `A nu nu_uncertainty`, or `A nu` where
the archive quotes no uncertainty:

```
A nu nu_uncertainty
81 0.644 0.06826
82 0.905 0.08244
```

Every column is named for the quantity it holds, as the literature writes it, and an uncertainty
is the quantity's own name suffixed with `_uncertainty`. A reader is nonetheless expected to take
columns by **position**: the header says what is there, and renaming a quantity must not be able
to break anything that reads these files.

Nothing is overwritten. A retrieval landing on an existing directory writes beside it under a
suffixed name.

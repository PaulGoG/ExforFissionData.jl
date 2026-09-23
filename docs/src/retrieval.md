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
| `[platform]` | `julia_version`, `julia_threads`, `cpu_model`, `cpu_threads`, `total_memory_gb` | the hardware and runtime; `hostname` too when `record_hostname = true` |
| `[datasets]` | `accepted`, `rejected`, `relative` | counts |
| | `retrieved_earliest_utc`, `retrieved_latest_utc` | the span of the dataset retrieval dates |
| | `units_present` | every unit token among the accepted datasets |
| | `units_warning`, `relative_warning`, `scale_warning`, `combined_warning` | present only when they apply, each naming the datasets concerned |
| `[[accepted]]` | `identifier`, `author`, `year`, `file` | the dataset and the file it was written to, relative to the retrieval directory |
| | `reaction_code`, `qualifiers` | the code the archive returned and the qualifiers recorded from it |
| | `unit`, `unit_reported`, `unit_written`, `ordinate_factor` | the archive's unit token, the token the file is written in, and the factor between them |
| | `relative` | whether the dataset is in arbitrary units and lies under `relative/` |
| | `retrieved_utc`, `from_cache` | when the csv response was obtained and whether from the cache |
| | `rows_retrieved`, `rows_written` | rows the archive returned, rows the file holds |
| | `incident_energies_mev` | the incident energies of the rows written |
| | `isomer_totals_used`, `isomer_states_summed`, `isomer_groups_ambiguous` | how each nuclide's isomeric rows were resolved |
| | `abscissae_combined`, `combined_over`, `weights_imputed` | abscissa values that combined several rows, the auxiliary columns that varied among them, and rows whose weight was imputed for lack of an uncertainty |
| | `mass_values_non_integer`, `mass_rounding_max`, `abscissa_binned` | what rounding the subentry masses did, and whether the abscissa came from a bin pair |
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

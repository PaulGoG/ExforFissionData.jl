```@meta
CurrentModule = ExforFissionData
```

# ExforFissionData

Retrieval of experimental fission observables from the IAEA EXFOR archive, as tabulated data
files with a record of everything the query considered.

A query names a fissioning system — target charge, target mass and entrance channel — and the
observable wanted as an abscissa and an ordinate. The package finds the datasets that answer it,
reduces each to one row per abscissa value, and writes them beside a run record naming every
dataset it kept or excluded, with the reason.

![Prompt neutron multiplicity against fragment mass for four fissioning systems, dataset by dataset as each retrieval is worked through](assets/coverage.gif)

Prompt neutron multiplicity against fragment mass, one panel per fissioning system, as the
`*_nu_vs_A` configurations return it. Each frame advances through the datasets the archive offers
for that query in the order the pipeline processes them; a dataset enters the axes only where its
reaction code answers the query, and otherwise advances the tally alone. Thirty datasets kept of
824 considered — the remainder are other quantities filed under the same target and reaction, and
the run record names every one of them with the reason it was left out.

## Quick start

From a clone of the repository:

```bash
julia scripts/retrieve.jl config/Cf252_sf_nu_vs_A.toml             # retrieve one observable
julia plotting/survey.jl data/Cf252_sf/nu_vs_A --format png        # check what it returned
```

or from Julia:

```julia
using ExforFissionData
result = retrieve(load_configuration("config/Cf252_sf_nu_vs_A.toml"))
length(result.accepted), length(result.rejected)
```

## Pages

- [Observables](observables.md): the abscissae and ordinates, their quantity codes, what stays
  outside the observable set, and relative data.
- [Entrance channels](channels.md): the incident-energy intervals, the physics behind them, and
  the spectrum qualifiers a channel excludes.
- [Conventions and selection](conventions.md): units, precision, one row per abscissa value, the
  selection checks, and the known miscoded entries.
- [Retrieval and the run record](retrieval.md): the cache, the archive dates, the run record and
  the output layout.
- [Configurations](configurations.md): every key and every shipped configuration.
- [Naming](naming.md): the naming convention, in full.
- [API](api.md): the exported names.
- [Internals](internals.md): the names that are not exported.

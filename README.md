# ExforFissionData.jl

[![CI](https://github.com/PaulGoG/ExforFissionData.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/PaulGoG/ExforFissionData.jl/actions/workflows/CI.yml)
[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://PaulGoG.github.io/ExforFissionData.jl/stable/)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://PaulGoG.github.io/ExforFissionData.jl/dev/)
[![Julia](https://img.shields.io/badge/Julia-1.12%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![JET](https://img.shields.io/badge/tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)
[![Code style: JuliaFormatter](https://img.shields.io/badge/code%20style-JuliaFormatter-informational)](https://github.com/domluna/JuliaFormatter.jl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Retrieval of experimental fission observables from the IAEA EXFOR archive, as tabulated data
files with a record of everything the query considered.

```
ExforFissionData.jl/
├── activate.jl        # silent activation of the package environment
├── check.jl           # pre-commit gate: format, then test
├── config/            # 21 retrieval configurations, <system>_<observable>.toml
├── scripts/
│   └── retrieve.jl    # entry point
├── src/               # the package: selection, reduction, export, run record
├── plotting/          # survey figures; an environment of its own
├── test/  docs/  formatter/
└── Project.toml  CHANGELOG.md  CITATION.cff  LICENSE
```

The full tree is [further down](#full-file-tree).

## Requirements

Julia 1.12 or later through [juliaup](https://github.com/JuliaLang/juliaup). Retrieval needs
network access to `nds.iaea.org`, since every run requests the listing of datasets; a run with
`offline = true` under `[retrieval]` needs none and works from the cache alone. The test suite
runs on Linux and macOS in CI.

## Installation

This is **not a registered package** — `Pkg.add("ExforFissionData")` will not find it. Either
clone it and work in the repository, which is what the configurations and scripts assume,

```bash
git clone https://github.com/PaulGoG/ExforFissionData.jl
cd ExforFissionData.jl
julia -e 'include("activate.jl")'
```

or add it to another environment by URL,

```julia
using Pkg
Pkg.add(url = "https://github.com/PaulGoG/ExforFissionData.jl")
```

Documentation: <https://PaulGoG.github.io/ExforFissionData.jl/stable/>

## Entry points

```bash
julia scripts/retrieve.jl config/Cf252_sf_nu_vs_A.toml             # retrieve one observable
julia scripts/retrieve.jl config/U233_nth_Y_vs_A.toml ~/data       # elsewhere
julia plotting/survey.jl data/Cf252_sf/nu_vs_A --format png        # check what it returned
julia plotting/coverage.jl data/{Cf252_sf,U235_nth,U233_nth,Pu239_nth}/nu_vs_A   # the animation
julia -e 'include("activate.jl"); Pkg.test()'                      # test suite
julia plotting/runtests.jl                                         # figure-helper tests
julia check.jl                                                     # format, then test
julia check.jl --check                                             # fail on formatting diffs
julia docs/make.jl                                                 # build the documentation
julia -i activate.jl                                               # REPL in the environment
```

Every environment — the package, `test/`, `docs/`, `formatter/` and `plotting/` — carries an
`activate.jl` that activates and instantiates it silently, so a fresh clone needs no preparation.
`test/` and `docs/` take the package by path, so they always run against the local source;
`plotting/` and `formatter/` do not depend on it. No invocation needs `--project`: every script
activates the environment it belongs to as its first statement.

```julia
using ExforFissionData
result = retrieve(load_configuration("config/Cf252_sf_nu_vs_A.toml"))
length(result.accepted), length(result.rejected)
```

## Status

| Component | State |
| :--- | :--- |
| Column contract, tag grammar, selection | tested; every abscissa and ordinate exercised against the live archive for 252-Cf(sf), 235-U(n,f), 233-U(n,f) and 239-Pu(n,f) |
| Reduction: isomers, energy windows, other independent variables | tested on fixtures; the rejections checked against the live datasets that prompted them. The abscissa and the other variables are read from the subentry DATA table, aligned with the rendering row by row |
| Retrieval: cache, backoff, bounded concurrency | in use; result order independent of completion order, and the concurrency bound verified at limits 1, 3 and 4 |
| Export and run record | in use |
| `plotting/survey.jl`, `plotting/coverage.jl` | in use; figures inspected |
| Static QA | Aqua, JET and ExplicitImports in the suite; formatting gated against a JuliaFormatter pinned in `formatter/Project.toml` |

Not every abscissa and ordinate pairing exists in the archive. Prompt multiplicity against
`["total_kinetic_energy"]` is reported as a pair quantity, so it needs
`multiplicity_per_fission`; 252-Cf carries no mass-resolved post-neutron kinetic energy, and its
one `Y(A, TKE)` grid is rendered without its TKE column — see `23268002` under the
[known miscoded entries](https://PaulGoG.github.io/ExforFissionData.jl/stable/conventions/#Known-miscoded-entries).

## What it is for

A query names a fissioning system — target charge, target mass and entrance channel — and the
observable wanted as an abscissa and an ordinate. The package finds the datasets that answer it,
reduces each to one row per abscissa value, and writes them beside a run record naming every
dataset it kept or excluded, with the reason.

It is a data-preparation step rather than an analysis code: a consumer reads the files it writes
rather than calling it at run time. That is why the output layout is plain whitespace-separated
text with one header line, why nothing is normalised or filtered on the way out, and why the
reasoning behind every exclusion is written down. Two fission-model analyses of mine consume it
in exactly that way, and where the documentation says "consumers" it means those, or yours.

![Prompt neutron multiplicity against fragment mass for four fissioning systems, dataset by dataset as each retrieval is worked through](docs/src/assets/coverage.gif)

Prompt neutron multiplicity against fragment mass, one panel per fissioning system, as the
`*_nu_vs_A` configurations return it. Each frame advances through the datasets the archive offers
for that query in the order the pipeline processes them; a dataset enters the axes only where its
reaction code answers the query, and otherwise advances the tally alone. Thirty datasets kept of
824 considered — the remainder are other quantities filed under the same target and reaction, and
the run record names every one of them with the reason it was left out.

## Configurations

A configuration is named for what it retrieves: `<system>_<observable>.toml`, the same two tokens
that name the directories its data is written to.

| System | Y(A) | ν(A) | ν(A,TKE) | spectrum |
| :--- | :--- | :--- | :--- | :--- |
| ²⁵²Cf(sf) | `Cf252_sf_Y_vs_A` | `Cf252_sf_nu_vs_A` | `Cf252_sf_nu_vs_A_TKE` | `Cf252_sf_spectrum_vs_E` |
| ²³⁵U(n,f) | `U235_nth_Y_vs_A` | `U235_nth_nu_vs_A` | `U235_nth_nu_vs_A_TKE` | `U235_nth_spectrum_vs_E` |
| ²³³U(n,f) | `U233_nth_Y_vs_A` | `U233_nth_nu_vs_A` | `U233_nth_nu_vs_A_TKE` | `U233_nth_spectrum_vs_E` |
| ²³⁹Pu(n,f) | `Pu239_nth_Y_vs_A` | `Pu239_nth_nu_vs_A` | `Pu239_nth_nu_vs_A_TKE` | `Pu239_nth_spectrum_vs_E` |

A system is an element symbol, a mass number and an **entrance channel** — `sf` spontaneous, `nth`
thermal-neutron-induced, `nres` resonance-region, `nfast` fast. The channel decides the EXFOR
reaction code, so the configuration names the channel and never the code: the two can disagree
only if both are written down. The window that selects datasets is `energy_min` and
`energy_max`; it defaults to the channel's interval — `nth` up to 0.1 eV, `nres` 0.1 eV to
100 keV, `nfast` 100 keV to 20 MeV — and is refused outside it, so that a thermal directory
cannot hold a fast measurement. The physics behind the bounds is in
[the documentation](https://PaulGoG.github.io/ExforFissionData.jl/stable/channels/).

`U235_nres_nu_vs_A` and `U235_nres_nu_vs_A_TKE` span 0.1 eV to 1 keV, which is what the
resonance-beam measurements need — a thermal window excludes them on their incident energy alone,
and the resonance window holds them alone, the thermal datasets belonging to the `nth` runs.
They are a different system by name, `U235_nres` against `U235_nth`, so they land in a directory of
their own without any special provision.

`Cf252_sf_spectrum_maxwellian_ratio_vs_E` and `U235_nth_spectrum_maxwellian_ratio_vs_E` retrieve
the spectrum as a ratio to a Maxwellian. That is a separate observable rather than a second
rendering of `spectrum`: the archive codes the ratio with `MXD`, which the plain spectrum excludes.
The archive holds the ratio form for these two systems alone.

Spectra are the one observable the archive holds more of for 252-Cf than for 235-U — 156 datasets
against 125, the spontaneous-fission spectrum being a reference standard — and none of it is
narrowed by an incident-energy window.

Every configuration, key by key, is in [the documentation](https://PaulGoG.github.io/ExforFissionData.jl/stable/configurations/).

## Data ownership and archive load

The experimental data belongs to the [IAEA Nuclear Data Section](https://nds.iaea.org/exfor) and
to the groups that measured it. This package only automates queries against it; it neither
redistributes EXFOR data nor claims any rights over what it retrieves.

**Cite the original measurements.** Every retrieval writes the EXFOR accession
number of each dataset into both the file name and the run record, which is what makes those
citations recoverable. A reference for the archive itself is in `CITATION.cff`.

EXFOR is a shared public service. Dataset responses are cached on disk, so a re-run costs the
archive one listing request. Leave that caching enabled and keep the configured concurrency
modest.

## How to cite

The data comes from the measurements the run record names, and those are what a result built on
it cites, together with the archive (`CITATION.cff` carries the reference). If the retrieval
itself is referred to, cite the software:

```bibtex
@software{gogita2026exforfissiondata,
  author  = {Gogîță, Paul-Adrian},
  title   = {ExforFissionData.jl: retrieval of experimental fission observables from the IAEA EXFOR archive},
  version = {0.1.0},
  year    = {2026},
  url     = {https://github.com/PaulGoG/ExforFissionData.jl}
}
```

## What a retrieval writes

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

## Further reading

The reference lives in the documentation, one page per topic:

- [Observables](https://PaulGoG.github.io/ExforFissionData.jl/stable/observables/): the abscissae and ordinates, their quantity codes, relative data, and what stays outside the observable set.
- [Entrance channels](https://PaulGoG.github.io/ExforFissionData.jl/stable/channels/): the incident-energy intervals and the physics behind them.
- [Conventions and selection](https://PaulGoG.github.io/ExforFissionData.jl/stable/conventions/): units, precision, one row per abscissa value, the selection checks, and the known miscoded entries.
- [Retrieval and the run record](https://PaulGoG.github.io/ExforFissionData.jl/stable/retrieval/): the cache, the archive dates, and every field of `retrieval.toml`.
- [Configurations](https://PaulGoG.github.io/ExforFissionData.jl/stable/configurations/) and [Naming](https://PaulGoG.github.io/ExforFissionData.jl/stable/naming/).

## Full file tree

<details>
<summary>Every tracked directory and file</summary>

```
ExforFissionData.jl/
├── activate.jl                  # silent activation of the package environment
├── check.jl                     # pre-commit: format with formatter/, then test
├── CHANGELOG.md
├── CITATION.cff
├── LICENSE
├── Project.toml
├── README.md
├── .JuliaFormatter.toml         # formatter settings shared by check.jl and CI
├── .gitignore
├── config/                      # 21 configurations, <system>_<observable>.toml
├── docs/                        # Documenter site
│   ├── activate.jl
│   ├── Project.toml
│   ├── make.jl
│   └── src/
│       ├── index.md
│       ├── observables.md       #   abscissae, ordinates, relative data
│       ├── channels.md          #   entrance channels and their incident-energy intervals
│       ├── conventions.md       #   conventions, selection, known miscoded entries
│       ├── retrieval.md         #   the cache, the run record, the output layout
│       ├── configurations.md    #   every shipped configuration, key by key
│       ├── naming.md            #   the naming convention, in full
│       ├── api.md               #   the exported names
│       ├── internals.md         #   the names that are not exported
│       └── assets/coverage.gif  #   the figure above, as plotting/coverage.jl writes it
├── formatter/                   # pinned JuliaFormatter environment
│   ├── activate.jl
│   └── Project.toml             #   the pin, as an equality bound
├── plotting/                    # detached figures; not a dependency of retrieval
│   ├── activate.jl              #   silent activation of the plotting environment
│   ├── Project.toml
│   ├── style.jl                 #   theme, palette and labels shared by the scripts
│   ├── survey.jl                #   one figure per retrieval, as a check on what it returned
│   ├── coverage.jl              #   several retrievals accumulating, as an animation
│   └── runtests.jl              #   tests for the helpers in style.jl
├── scripts/
│   └── retrieve.jl              # entry point
├── src/
│   ├── ExforFissionData.jl      # module
│   ├── elements.jl              # chemical symbols, for naming a target by Z and A
│   ├── schema.jl                # the 39-column contract of the csv rendering
│   ├── subentry.jl              # the COMMON and DATA sections of a subentry
│   ├── reaction_codes.jl        # the tag grammar, as data
│   ├── client.jl                # retrieval: timeout, backoff, bounded concurrency, cache
│   ├── configuration.jl         # TOML loading and validation
│   ├── selection.jl             # what answers the query, and why the rest does not
│   ├── reduction.jl             # projection, isomers, duplicates
│   ├── results.jl               # what a retrieval returns
│   ├── export.jl                # data files and the run record
│   └── pipeline.jl              # orchestration
├── test/
│   ├── activate.jl
│   ├── Project.toml
│   ├── runtests.jl
│   ├── fixtures.jl              # synthetic responses in the layout of the csv rendering
│   └── subentry_tests.jl        # the subentry parser
└── .github/
    ├── dependabot.yml           # weekly updates for the julia and github-actions ecosystems
    └── workflows/
        ├── CI.yml
        └── format.yml           # formatting check against the pinned JuliaFormatter
```

</details>

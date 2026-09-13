# ExforFissionData.jl

[![CI](https://github.com/PaulGoG/ExforFissionData.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/PaulGoG/ExforFissionData.jl/actions/workflows/CI.yml)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://PaulGoG.github.io/ExforFissionData.jl/dev/)
[![Julia](https://img.shields.io/badge/Julia-1.12%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![JET](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)
[![Code style: JuliaFormatter](https://img.shields.io/badge/code%20style-JuliaFormatter-informational)](https://github.com/domluna/JuliaFormatter.jl)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Retrieval of experimental fission observables from the IAEA EXFOR archive, as tabulated data
files with a record of everything the query considered.

A query names a target, a reaction, an EXFOR quantity code, and the observable wanted as an
abscissa and an ordinate. The package finds the datasets that answer it, reduces each to one row
per abscissa value, and writes them beside a run record naming every dataset it kept or
excluded, with the reason.

It exists as a data-preparation step for separate fission-model analyses, which read the files it
writes rather than calling it at run time. That is why the output layout is plain whitespace-
separated text with one header line, why nothing is normalised or filtered on the way out, and why
the reasoning behind every exclusion is written down. Where the documentation says "consumers",
it means those downstream analyses — or yours.

```
ExforFissionData.jl/
├── activate.jl                  # silent activation of the package environment
├── check.jl                     # pre-commit: format with formatter/, then test
├── CHANGELOG.md
├── CITATION.cff
├── LICENSE
├── Project.toml  Manifest.toml
├── config/                      # 18 configurations, <target>_<reaction>_<ordinate>_<abscissa>
├── docs/                        # Documenter site
│   ├── make.jl
│   └── src/index.md
├── formatter/                   # pinned JuliaFormatter environment
│   └── activate.jl
├── plotting/                    # detached survey figures; not a dependency of retrieval
│   ├── activate.jl              #   silent activation of the plotting environment
│   ├── Project.toml
│   └── survey.jl                #   one figure per retrieval, as a check on what it returned
├── scripts/
│   └── retrieve.jl              # entry point
├── src/
│   ├── ExforFissionData.jl      # module
│   ├── schema.jl                # the 39-column contract of the csv rendering
│   ├── reaction_codes.jl        # the tag grammar, as data
│   ├── client.jl                # retrieval: timeout, backoff, bounded concurrency, cache
│   ├── configuration.jl         # TOML loading and validation
│   ├── selection.jl             # what answers the query, and why the rest does not
│   ├── reduction.jl             # projection, isomers, duplicates
│   ├── export.jl                # data files and the run record
│   └── pipeline.jl              # orchestration
├── test/
└── .github/workflows/CI.yml
```

Retrieved data lands in `data/<label>/` and is not version-controlled: EXFOR entries are
immutable once published, so a configuration and this package reproduce a retrieval exactly.

## Configurations

| System | Y(A) | ν(A) | ν(A,TKE) |
| :--- | :--- | :--- | :--- |
| ²⁵²Cf(sf) | `Cf252_0f_yield_A` | `Cf252_0f_nu_A` | `Cf252_0f_nu_ATKE` |
| ²³⁵U(n,f) | `U235_nf_yield_A` | `U235_nf_nu_A` | `U235_nf_nu_ATKE` |
| ²³³U(n,f) | `U233_nf_yield_A` | `U233_nf_nu_A` | `U233_nf_nu_ATKE` |
| ²³⁹Pu(n,f) | `Pu239_nf_yield_A` | `Pu239_nf_nu_A` | `Pu239_nf_nu_ATKE` |

The neutron-induced configurations admit thermal incident energies. `U235_nf_nu_A_res` and
`U235_nf_nu_ATKE_res` widen the window to 1 keV, which is what the resonance-beam measurements
need — a thermal window excludes them on their incident energy alone.

For the prompt fission neutron spectrum, `U235_nf_spectrum_E` and `U235_nf_spectrumRatioMXW_E`.
The two are separate observables, not two renderings of one: the archive codes the Maxwellian
ratio with `MXD`, which the plain spectrum excludes.

## Requirements

Julia 1.12 or later through [juliaup](https://github.com/JuliaLang/juliaup). Retrieval needs
network access to `nds.iaea.org`; a cached query does not.

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
Pkg.develop(url = "https://github.com/PaulGoG/ExforFissionData.jl")
```

Documentation: <https://PaulGoG.github.io/ExforFissionData.jl>

## The data, and using the archive politely

The experimental data belongs to the [IAEA Nuclear Data Section](https://nds.iaea.org/exfor) and
to the groups that measured it. This package only automates queries against it; it neither
redistributes EXFOR data nor claims any rights over what it retrieves.

**Cite the original measurements, not this tool.** Every retrieval writes the EXFOR accession
number of each dataset into both the file name and the run record, which is what makes those
citations recoverable. A reference for the archive itself is in `CITATION.cff`.

EXFOR is a shared public service. Responses are cached on disk and an entry is fetched at most
once, so a re-run costs the archive nothing — please leave that caching enabled, and keep the
configured concurrency modest.

## Entry points

```bash
julia --project scripts/retrieve.jl config/Cf252_0f_nu_A.toml     # retrieve one observable
julia --project scripts/retrieve.jl config/U233_nf_yield_A.toml ~/data   # elsewhere
julia plotting/survey.jl data/Cf252_0f_nuA --format png           # check what it returned
julia --project -e 'using Pkg; Pkg.test()'                        # test suite
julia check.jl                                                    # format, then test
julia check.jl --check                                            # fail on formatting differences
julia --project=docs docs/make.jl                                 # build the documentation
julia -e 'include("activate.jl")' -i                              # REPL in the environment
```

Every environment — the package, `test/`, `docs/`, `formatter/` and `plotting/` — carries an
`activate.jl` that activates and instantiates it silently, so a fresh clone needs no preparation.
The auxiliary ones take the package by path, so they always run against the local source.

```julia
using ExforFissionData
result = retrieve(load_configuration("config/Cf252_0f_nu_A.toml"))
length(result.accepted), length(result.rejected)
```

## What a retrieval writes

```
data/Cf252_0f_nuA/
├── retrieval.toml                        # the run record
├── data/
│   └── 41425014_A.S.Vorobiev_2001.dat    # identifier, first author, year
└── subentries/
    └── 41425014_A.S.Vorobiev_2001.txt    # the original EXFOR subentry
```

Data files are space-separated with a single header line — `A nu errnu`, or `A nu` where the
archive quotes no uncertainty:

```
A nu errnu
81 0.644 0.06826
82 0.905 0.08244
```

Nothing is overwritten. A retrieval landing on an existing directory writes beside it under a
suffixed name.

## Observables

| Abscissa | Meaning |
| :--- | :--- |
| `A`, `Ap` | pre- and post-neutron fragment mass |
| `Z` | fragment charge |
| `ZAp` | charge and post-neutron mass jointly |
| `E`, `TKE` | energy, total kinetic energy |
| `ATKE` | mass and total kinetic energy jointly |

| Ordinate | Meaning |
| :--- | :--- |
| `yield` | fission yield |
| `nu`, `nuPair` | prompt neutron multiplicity, per fragment and per fragment pair |
| `KE`, `KEp` | pre- and post-neutron fragment kinetic energy |
| `TKE`, `TKEp` | pre- and post-neutron total kinetic energy |
| `epsE` | centre-of-mass neutron energy |
| `spectrum`, `spectrumRatioMXW` | prompt fission neutron spectrum, absolute and as a ratio to a Maxwellian |

Each ordinate belongs to one EXFOR quantity code — `yield` to `FY`, `nu` and `nuPair` to `NU`,
the kinetic energies to `E`, the spectra to `MFQ` — and the configuration is refused if the two
disagree. The quantity decides which datasets the archive offers at all, so a mismatch retrieves
a different observable under the requested name rather than nothing.

### Not covered

Fragment and prompt-neutron observables only. Prompt-γ quantities — ⟨Eγ⟩(A), ⟨Nγ⟩(A) and the
prompt fission γ-ray spectrum — are outside the observable set, as are the neutron multiplicity
distribution P(ν) and the centre-of-mass spectrum Φ(ε), the last of which the archive does not
carry as a quantity of its own.

Spectra between two different fissioning systems — the `(A(n,f),PR,NU/DE)/(B(n,f),PR,NU/DE)`
ratio form the archive holds a good deal of — are a distinct observable and are excluded. A
spectrum expressed as a ratio to a Maxwellian is not: that is `spectrumRatioMXW`.

## Relative data

A prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
so for 235-U(n,f) most of what the archive holds is in arbitrary units. Those datasets are
retrieved, and **written under `relative/` rather than beside the absolute ones in `data/`**:

```
data/U235_nf_spectrumE/
├── data/        # absolute, PC/FIS/MEV or 1/EV
├── relative/    # arbitrary units — a shape, with no scale
├── subentries/
└── retrieval.toml
```

The separation is the point. A relative dataset cannot be put on a common scale with anything,
not even another relative dataset: each has to be normalised on its own before it is compared
with anything, and none may be averaged with absolute data. A reader that takes a whole directory
therefore cannot pick one up by accident. The run record marks each accepted dataset
`relative = true` or `false` and names them all in one warning.

This applies to the spectrum ordinates alone. For every other observable arbitrary units are
still fatal, because a relative value there is not interpretable — a kinetic energy in arbitrary
units is not an energy, and a multiplicity is a count whose scale is the whole quantity.

## Conventions

**Energies are MeV**, converted from the electronvolts the archive reports.

**No normalisation is applied to ordinates.** Normalisation conventions differ between the
projects that consume this data and cannot be undone once applied, so the unit token of each
dataset is recorded in the run record instead. A query returning more than one unit token is
flagged: such datasets must not be renormalised together.

**No point is dropped on the basis of its value or uncertainty.** Quality cuts belong with the
project that can justify them.

**The uncertainty column is omitted** when no row of a dataset carries one, rather than written
as a column of zeros.

**Duplicate abscissa values are resolved, never averaged blindly.** Three different things cause
them, and each is handled on its own terms:

| Cause | Treatment |
| :--- | :--- |
| several incident energies | selected by the configured window, as a row filter |
| isomeric states | the archive's own total where it gives one, otherwise the resolved states summed with uncertainties in quadrature |
| genuine repeats | inverse-variance weighted mean, uncertainty `1/√(Σ1/σ²)` |

What the reduction had to do is recorded per dataset in the run record, including groups it could
not disambiguate.

## Selection

Datasets are chosen by substring tests over the EXFOR reaction code — for instance
`92-U-233(N,F)ELEM/MASS,CUM,FY`. The archive applies its own vocabulary inconsistently, so the
tables in `src/reaction_codes.jl` are empirical: they encode observed failures of the upstream
labelling rather than a formal grammar. A rule that looks redundant is more likely to be guarding
against a real entry than to be dead weight.

Three checks are worth naming because they are easy to get wrong:

- the `y:Value` column marks **upper limits** with a `Max(` prefix; those rows are bounds, not
  measurements;
- it also marks **arbitrary units** as `ARB-UNITS`, which carry no scale and cannot be combined
  with absolute data;
- the incident-energy window is applied **per row**, not to the dataset as a whole. An EXFOR
  dataset frequently reports one product at several energies, and admitting all of them collapses
  an excitation function into a single number.

### Known miscoded entries

Selection follows the reaction code, so a dataset whose code disagrees with its own contents is
excluded correctly and unhelpfully. Two are known for `ordinate = "nu"`, both 252-Cf(sf):

| Subentry | Coded | Holds |
| :--- | :--- | :--- |
| `23268005` (Göök, 2014) | `MASS,PR,NU` | multiplicity per fragment, normalised to a total of 3.759 |
| `23118006` (Zeynalov, 2011) | `MASS,PR,NU` | multiplicity per fragment, though its own description says "total" |

Neither carries `FRG`, so `ordinate = "nu"` rejects both and `ordinate = "nuPair"` accepts them as
pair data, which they are not: for 252-Cf a pair multiplicity is about 3.76 everywhere, and
`23118006` reports 0.56 at A = 80. The tag rules are not loosened to admit them, since
`MASS,PR,NU` is the correct code for genuine pair data and admitting it would mix the two
quantities. Both appear in the rejection list of the run record with their reaction codes.

Only the one-dimensional projections are affected. The same Göök entry compiles the joint
distribution correctly as `23268008`, `MASS,PR/FRG,NU/TKE`, which `abscissa = "ATKE"` retrieves in
full — 2234 points of ν(A, TKE). A consumer that wants ν(A) from this measurement should take the
joint distribution and marginalise it rather than reach for the miscoded projection.

## Retrieval

Requests run under a bounded concurrency limit with a per-request timeout and exponential
backoff, and every response is cached on disk in a `Scratch.jl` space. An EXFOR entry is immutable
once published, so a dataset is fetched at most once and a re-run costs nothing.

Datasets are processed and written in identifier order, so a re-run over an unchanged archive
reproduces its output exactly.

## The run record

`retrieval.toml` holds the query, the conventions applied, the package revision, the platform,
and both dataset lists — accepted, with what the reduction did to each, and rejected, with the
reason. The rejection list is the point: a dataset missing from the output is otherwise
indistinguishable from one the archive does not hold.

It is written to be committed alongside the data, so it deliberately says nothing about who ran
it: the configuration appears by file name rather than by the path it was read from, and the
machine name is omitted. The platform fingerprint still attributes a run to its hardware — CPU
model, core counts, memory, Julia version. Set `record_hostname = true` under `[output]` to name
the machine as well, which is useful when the records stay yours.

## Status

| Component | State |
| :--- | :--- |
| Column contract, tag grammar, selection | tested; every abscissa and ordinate exercised against the live archive for 252-Cf(sf), 235-U(n,f), 233-U(n,f) and 239-Pu(n,f) |
| Reduction: isomers, duplicates, energy windows | tested on fixtures and on live datasets exhibiting all three causes |
| Retrieval: cache, backoff, bounded concurrency | in use; order independence and the concurrency bound tested under 1, 4 and 8 threads |
| Export and run record | in use |
| `plotting/survey.jl` | in use; figures inspected |
| Static QA | Aqua and JET in the suite; formatting gated against a pinned JuliaFormatter |

Not every abscissa and ordinate pairing exists in the archive. Prompt multiplicity against `TKE`
is reported as a pair quantity, so it needs `nuPair`; 252-Cf carries no mass-resolved
post-neutron kinetic energy, and no `Y(A, TKE)` under any quantity code.

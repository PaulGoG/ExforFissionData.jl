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
`offline = true` under `[retrieval]` needs none and works from the cache alone.

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

Documentation: <https://PaulGoG.github.io/ExforFissionData.jl>

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
The auxiliary ones take the package by path, so they always run against the local source. No
invocation needs `--project`: every script activates the environment it belongs to as its first
statement.

```julia
using ExforFissionData
result = retrieve(load_configuration("config/Cf252_sf_nu_vs_A.toml"))
length(result.accepted), length(result.rejected)
```

## Status

| Component | State |
| :--- | :--- |
| Column contract, tag grammar, selection | tested; every abscissa and ordinate exercised against the live archive for 252-Cf(sf), 235-U(n,f), 233-U(n,f) and 239-Pu(n,f) |
| Reduction: isomers, energy windows, other independent variables | tested on fixtures; the rejections checked against the live datasets that prompted them. Masses the rendering truncates, and variables it drops, are reported per dataset and not corrected |
| Retrieval: cache, backoff, bounded concurrency | in use; order independence and the concurrency bound tested under 1, 4 and 8 threads |
| Export and run record | in use |
| `plotting/survey.jl`, `plotting/coverage.jl` | in use; figures inspected |
| Static QA | Aqua, JET and ExplicitImports in the suite; formatting gated against a JuliaFormatter pinned in `formatter/Project.toml` |

Not every abscissa and ordinate pairing exists in the archive. Prompt multiplicity against
`["total_kinetic_energy"]` is reported as a pair quantity, so it needs
`multiplicity_per_fission`; 252-Cf carries no mass-resolved post-neutron kinetic energy, and its
one `Y(A, TKE)` grid is rendered without its TKE column — see `23268002` under the known
miscoded entries.

## What it is for

A query names a fissioning system — target charge, target mass and entrance channel — and the
observable wanted as an abscissa and an ordinate. The package finds the datasets that answer it,
reduces each to one row per abscissa value, and writes them beside a run record naming every
dataset it kept or excluded, with the reason.

It is a data-preparation step rather than an analysis code: a consumer reads the files it writes
rather than calling it at run time. That is why the output layout is plain whitespace-separated
text with one header line, why nothing is normalised or filtered on the way out, and why the
reasoning behind every exclusion is written down. Two fission-model analyses by the same author —
a fragment temperature-ratio study and a sequential-emission model — consume it in exactly that
way; neither is public yet, and both are to be released in repositories of their own under
[github.com/PaulGoG](https://github.com/PaulGoG). Where the documentation says "consumers", it
means those, or yours.

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

| System | Y(A) | ν(A) | ν(A,TKE) | N(E) |
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
[the documentation](https://PaulGoG.github.io/ExforFissionData.jl/dev/#Entrance-channels).

`U235_nres_nu_vs_A` and `U235_nres_nu_vs_A_TKE` span 0.1 eV to 1 keV, which is what the
resonance-beam measurements need — a thermal window excludes them on their incident energy alone.
They are a different system by name, `U235_nres` against `U235_nth`, so they land in a directory of
their own without any special provision.

`Cf252_sf_spectrum_maxwellian_ratio_vs_E` and `U235_nth_spectrum_maxwellian_ratio_vs_E` retrieve
the spectrum as a ratio to a Maxwellian. That is a separate observable rather than a second
rendering of `spectrum`: the archive codes the ratio with `MXD`, which the plain spectrum excludes.
The archive holds the ratio form for these two systems alone.

Spectra are the one observable the archive holds more of for 252-Cf than for 235-U — 156 datasets
against 125, the spontaneous-fission spectrum being a reference standard — and none of it is
narrowed by an incident-energy window.

Every configuration, key by key, is in [the documentation](https://PaulGoG.github.io/ExforFissionData.jl/dev/configurations/).

## The data, and using the archive politely

The experimental data belongs to the [IAEA Nuclear Data Section](https://nds.iaea.org/exfor) and
to the groups that measured it. This package only automates queries against it; it neither
redistributes EXFOR data nor claims any rights over what it retrieves.

**Cite the original measurements, not this tool.** Every retrieval writes the EXFOR accession
number of each dataset into both the file name and the run record, which is what makes those
citations recoverable. A reference for the archive itself is in `CITATION.cff`.

EXFOR is a shared public service. Dataset responses are cached on disk, so a re-run costs the
archive one listing request — please leave that caching enabled, and keep the configured
concurrency modest.

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

## Observables

A quantity has one name in a configuration and one symbol in a path, a file name and a column
header. The configuration spells it out, so a file a user edits explains itself; the path and the
header carry the symbol, which is the field's own nomenclature. The convention in full, including
the identifier and configuration rules, is in
[the documentation](https://PaulGoG.github.io/ExforFissionData.jl/dev/naming/).

| Abscissa | Symbol | Meaning |
| :--- | :--- | :--- |
| `mass`, `product_mass` | `A`, `A_p` | pre- and post-neutron fragment mass |
| `charge` | `Z` | fragment charge |
| `neutron_energy` | `E` | secondary neutron energy |
| `total_kinetic_energy` | `TKE` | total kinetic energy |

| Ordinate | Symbol | Meaning |
| :--- | :--- | :--- |
| `yield` | `Y` | fission yield |
| `multiplicity`, `multiplicity_per_fission` | `nu`, `nu_bar` | prompt neutron multiplicity, per fragment and per fragment pair |
| `fragment_kinetic_energy`, `product_kinetic_energy` | `E_K`, `E_K_p` | pre- and post-neutron fragment kinetic energy |
| `total_kinetic_energy`, `post_neutron_total_kinetic_energy` | `TKE`, `TKE_p` | pre- and post-neutron total kinetic energy |
| `neutron_kinetic_energy` | `eps` | centre-of-mass neutron energy |
| `spectrum`, `spectrum_maxwellian_ratio` | — | prompt fission neutron spectrum, absolute and as a ratio to a Maxwellian |

An abscissa is a **list**, because it is a joint index: `["mass"]`, or
`["mass", "total_kinetic_energy"]` for ν(A, TKE). A joint abscissa is therefore no separate
vocabulary item, and the directory it writes to is the ordinate, `vs`, then the abscissa
symbols — `nu_vs_A_TKE`, `Y_vs_A`, `spectrum_maxwellian_ratio_vs_E`.

The seven abscissae the archive can be asked for are `["mass"]`, `["product_mass"]`, `["charge"]`,
`["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]` and
`["mass", "total_kinetic_energy"]`.

Each ordinate belongs to one EXFOR quantity code — `yield` to `FY`, the multiplicities to `NU`,
the kinetic energies to `E`, the spectra to `MFQ` — and the configuration does not name it: the
code is read from the ordinate. The quantity decides which datasets the archive offers at all, and
several ordinates impose no tags of their own, so a pairing that could be written down could be
written down wrong and would retrieve a different observable under the requested name.

### Not covered

Fragment and prompt-neutron observables only. Prompt-γ quantities — ⟨Eγ⟩(A), ⟨Nγ⟩(A) and the
prompt fission γ-ray spectrum — are outside the observable set, as are the neutron multiplicity
distribution P(ν) and the centre-of-mass spectrum Φ(ε), the last of which the archive does not
carry as a quantity of its own — with the consequence that a measurement in the centre of mass is
compiled under the same code as a laboratory-frame one and separated from it only by free text.
`23268009` (Göök, 2014) is such a dataset, retrieved by `Cf252_sf_spectrum_vs_E` alongside
laboratory spectra. The frame is the consumer's to check, in the subentry stored beside the data.

For the first two, exclusion is what the archive holds rather than a preference:

**Prompt-γ.** The quantity code is `MLT`, and it returns five datasets for 252-Cf and one for
235-U, none for 233-U or 239-Pu. Not one carries `MASS`: the largest is differential in secondary
γ energy, three are relative and miscellaneous, one is a single number, and the 235-U entry is
resonance-region. Under `MFQ` for 235-U(n,f), none of the 125 datasets carries `GAM` or a `,G`
branch, so the γ-ray spectrum is not there either.

**P(ν).** The distribution is coded `NUM` in the branch field — `,PR/NUM,NU` and `,NUM,NU` — and
is returned under `NU`, so the package already sees it and rejects it on tags. It cannot be
written: of the 33 such datasets across these four systems, 31 carry no abscissa column at all,
and the two exceptions carry one held constant over every row. In the `op=csv&plus=2` rendering
the neutron number exists only as the order of the rows. Retrieving it would mean asserting that
the nth row is ν = n−1 — an assumption about an entry's internal ordering that the rendering never
states, and which a file of one row per abscissa *value* would then present as data.

Spectra between two different fissioning systems — the `(A(n,f),PR,NU/DE)/(B(n,f),PR,NU/DE)`
ratio form the archive holds a good deal of — are a distinct observable and are excluded. A
spectrum expressed as a ratio to a Maxwellian is not: that is `spectrum_maxwellian_ratio`.

## Relative data

A prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
so for 235-U(n,f) most of what the archive holds is in arbitrary units: of the 125 datasets
offered under `MFQ`, 42 answer the query in arbitrary units against 15 in absolute ones, and a
thermal window narrows both to 11 and 6. Those datasets are retrieved, and **written under
`relative/` rather than beside the absolute ones**:

```
data/U235_nth/spectrum_vs_E/
├── *.dat        # absolute, PC/FIS/MEV or 1/EV
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

**Values carry seven significant digits**, set by `significant_digits` under `[output]`.
Significant digits rather than decimal places, because the ordinates span many orders of
magnitude: an absolute prompt fission neutron spectrum is of order 10⁻⁷ PC/FIS/MEV, which seven
decimal places would reduce to one significant digit and eight would erase.

**No normalisation is applied to ordinates.** Normalisation conventions differ between consumers
and cannot be undone once applied, so the unit token of each dataset is recorded in the run record
instead. A query returning more than one unit token is
flagged: such datasets must not be renormalised together.

**No point is dropped on the basis of its value or uncertainty.** Quality cuts belong with the
project that can justify them.

**The uncertainty column is omitted** when no row of a dataset carries one, rather than written
as a column of zeros.

**One row per abscissa value.** Several things put more than one row on an abscissa value, and
they are not handled alike:

| Cause | Treatment |
| :--- | :--- |
| several incident energies | the configured window selects rows; a dataset still holding more than one energy inside it is rejected, naming them, rather than averaged |
| another independent variable — a kinetic-energy gate, an angle | rejected where the variable varies: a mean over gates is not the observable asked for. One held at a single value is a condition of the measurement and passes |
| isomeric states | the archive's own total where it gives one, otherwise the resolved states summed with uncertainties in quadrature |
| anything left | inverse-variance weighted mean, uncertainty `1/√(Σ1/σ²)`, counted per dataset as `abscissae_combined` and named in a warning |

The last row deserves suspicion. Some of what reaches it is genuine repetition — a chain yield
measured through several nuclides of one mass. Much of it is an artefact of the `op=csv`
rendering, which reports a mass as an integer: a dataset tabulated on a non-integer mass scale
arrives **truncated**, 63.51 and 64.91 as 63 and 64, and neighbouring points collapse onto one
mass number. The abscissa of such a dataset is low by half a mass unit on average, and its true
scale survives only in the subentry stored beside the data. The rendering also drops independent
variables it does not recognise, and a grid over one of them then arrives as unexplained repeats;
`23268002` below is the worst case. Neither can be told from the rendering, so every dataset in
which rows were combined is named in the run record, and the subentry is what settles it.

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
  an excitation function into a single number;
- the rendering declares what a dataset is tabulated against, in its `indVars` column, and a
  declared variable that the abscissa does not hold **must not vary**. `23591005` (Straede, 1987)
  is a mass yield at nine fragment kinetic energies, and projected onto mass it is nine yields
  per mass number;
- the quantity code `FY` files more than yields. `MASS,PAR,ZP` is the most probable charge against
  mass, which satisfies every mass rule, so `yield` requires the `FY` tag itself: six such
  datasets for 235-U would otherwise sit among the mass yields at values near 40;
- a spectrum qualifier that contradicts the channel rejects the dataset — `FST`, `FIS` and `EPI`
  under `nth`; `MXW`, `FST` and `FIS` under `nres`; `EPI` under `nfast` — because the archive
  files a spectrum-averaged measurement under a dummy energy. `326650021`, ²³⁵U independent
  yields from a fission-spectrum irradiation, is declared at 0.0253 eV and would pass a thermal
  window on its energy alone.

### Known miscoded entries

Selection follows the reaction code, so a dataset whose code disagrees with its own contents is
excluded correctly and unhelpfully. Two are known for `ordinate = "multiplicity"`, both 252-Cf(sf):

| Subentry | Coded | Holds |
| :--- | :--- | :--- |
| `23268005` (Göök, 2014) | `MASS,PR,NU` | multiplicity per fragment, normalised to a total of 3.759 |
| `23118006` (Zeynalov, 2011) | `MASS,PR,NU` | multiplicity per fragment, though its own description says "total" |

That both hold per-fragment data is established from the data, not inferred from the wording.
Complementary masses sum to the total, `ν(A) + ν(252−A) ≈ 3.76`, where a pair quantity would
already be 3.76 at every point and the sums twice that. Both trace the per-fragment sawtooth,
rising to ≈3.4 near `A = 120` and collapsing to ≈0.8 at `A = 132` where the `N = 82`, `Z = 50`
shells close — a pair multiplicity varies only weakly with mass and cannot do this. And within the
Göök entry, `23268005` agrees to within a few percent with `23268008` marginalised over TKE, which
*is* coded `MASS,PR/FRG,NU/TKE`; were it a pair quantity it would be twice as large.

Beyond `A ≈ 180`, `23268005` reports values from 11 to 104. Those are not multiplicities: the
complement there is `A ≲ 70`, the yield is vanishing and the extraction diverges. They are written
unchanged, since nothing is dropped on the basis of its value, but they are not data to fit.

Neither carries `FRG`, so `ordinate = "multiplicity"` rejects both and
`ordinate = "multiplicity_per_fission"` accepts them as
pair data, which they are not: for 252-Cf a pair multiplicity is about 3.76 everywhere, and
`23118006` reports 0.56 at A = 80. The tag rules are not loosened to admit them, since
`MASS,PR,NU` is the correct code for genuine pair data and admitting it would mix the two
quantities. Both appear in the rejection list of the run record with their reaction codes.

Only the one-dimensional projections are affected. The same Göök entry compiles the joint
distribution correctly as `23268008`, `MASS,PR/FRG,NU/TKE`, which
`abscissa = ["mass", "total_kinetic_energy"]` retrieves in
full — 2234 points of ν(A, TKE). A consumer that wants ν(A) from this measurement should take the
joint distribution and marginalise it rather than reach for the miscoded projection.

One is known for `ordinate = "yield"`, and it is the rendering that misstates it. `23268002`
(Göök, 2014), `98-CF-252(0,F)MASS,PRE,FY,,MSC`, is the joint distribution Y(A, TKE): 30 000 rows
of counts on a 150 × 200 grid, which its subentry heads `TKE`, `MASS`, `DATA` in `ARB-UNITS`. The
`op=csv` rendering drops the TKE column, declares mass the only independent variable, and gives
the unit as `PART/FIS`. Nothing in the response distinguishes it from a mass yield measured 200
times over, so it is retrieved by `Cf252_sf_Y_vs_A`, reduced to 150 rows by a weighted mean that
means nothing, and written. It carries `MSC` and is named in the run record's scale warning and
among the combined datasets; it is not a mass yield, and the subentry is where its content is.

One more is known for `ordinate = "spectrum"`, and it is a mislabelled unit rather than a
mislabelled quantity. `40064031` (Kroshkin, 1970), `98-CF-252(0,F),PR,NU/DE,,REL`, heads its
energy column `MEV` over values running from 5.128 to 2132.8. The subentry contradicts itself:
its own `REACTION` text gives the range as "5 keV - 2 MeV", and its comment places the structure
it reports at 85 keV to 0.75 MeV. The column is keV. The dataset is retrieved and written as the
archive states it, since a unit token is not something this package overrules, but its abscissa is
a factor of 1000 too large and it is the one dataset in `Cf252_sf/spectrum_vs_E` reaching past
40 MeV — a sanity check on the abscissa range finds it immediately.

## Retrieval

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
package runs from a working copy — its commit, the platform, and both dataset lists — accepted, with what the reduction did to each, and rejected, with the
reason. The rejection list is the point: a dataset missing from the output is otherwise
indistinguishable from one the archive does not hold.

It is written to be committed alongside the data, so it deliberately says nothing about who ran
it: the configuration appears by file name rather than by the path it was read from, and the
machine name is omitted. The platform fingerprint still attributes a run to its hardware — CPU
model, core counts, memory, Julia version. Set `record_hostname = true` under `[output]` to name
the machine as well, which is useful when the records stay yours.

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
├── config/                      # 21 configurations, <system>_<observable>.toml
├── docs/                        # Documenter site
│   ├── make.jl
│   └── src/
│       ├── index.md
│       ├── configurations.md    #   every shipped configuration, key by key
│       ├── naming.md            #   the naming convention, in full
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

</details>

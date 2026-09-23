```@meta
CurrentModule = ExforFissionData
```

# Naming

A quantity has exactly one name, and that name is used everywhere it appears: Julia identifier,
struct field, configuration key, directory name, file name, column header, figure label, prose.
The spelling changes register between contexts — `multiplicity` in a configuration, `nu` in a
path — but the *quantity* does not, and the mapping between the two registers is a table in
`src/reaction_codes.jl` rather than a convention anyone has to remember.

The corollary is the rule that decides the hard cases: **a name says what the thing is, not what
is convenient to type.** `Y_A_TKE` names three symbols and no relation between them; `Y_vs_A_TKE`
is a statement. `Data` as a suffix carries nothing. `err` names the wrong concept for an
uncertainty column — an error is not an uncertainty.

This page is the vocabulary as this package applies it: the source, the configurations, the output
layout and the figures. Anything reading the retrieved data meets the same names, because the
directory names, the file names and the column headers are written from the table below.

## Two registers

| Register | Spelling | Where |
| :--- | :--- | :--- |
| word | `total_kinetic_energy` | configuration keys and values, prose, and every Julia identifier here |
| symbol | `TKE` | directory names, file names, column headers, figure labels |

A configuration is edited by hand and has to explain itself, so it spells a quantity out. A path
and a header are read at a glance and are the field's own nomenclature, so they carry the symbol.
`nu_vs_A_TKE` says exactly what `multiplicity_vs_mass_total_kinetic_energy` says, and a directory
listing stays readable.

Every Julia identifier in this package is word-register. The package retrieves tabulated
measurements and reduces them; it evaluates nothing, so no identifier here stands for a symbol in
an equation and none is spelled as one.

## The quantities

| Word | Symbol | Quantity |
| :--- | :--- | :--- |
| `mass` | `A` | pre-neutron fragment mass |
| `product_mass` | `A_p` | post-neutron product mass |
| `charge` | `Z` | fragment charge |
| `neutron_energy` | `E` | secondary neutron energy |
| `total_kinetic_energy` | `TKE` | total kinetic energy, pre-neutron |
| `post_neutron_total_kinetic_energy` | `TKE_p` | total kinetic energy, post-neutron |
| `fragment_kinetic_energy` | `E_K` | fragment kinetic energy, pre-neutron |
| `product_kinetic_energy` | `E_K_p` | fragment kinetic energy, post-neutron |
| `neutron_kinetic_energy` | `eps` | centre-of-mass neutron energy ⟨ε⟩ |
| `yield` | `Y` | fission yield |
| `multiplicity` | `nu` | prompt multiplicity per fragment, ν(A) |
| `multiplicity_per_fission` | `nu_bar` | prompt multiplicity per fragment pair, ν̄ |
| `spectrum` | `spectrum` | prompt fission neutron spectrum |
| `spectrum_maxwellian_ratio` | `spectrum_maxwellian_ratio` | the spectrum as a ratio to a Maxwellian |

A quantity that is an abscissa in one query and an ordinate in another — the total kinetic energy
is both — keeps one word and one symbol. [`ABSCISSA_TOKEN`](@ref) and [`ORDINATE_TOKEN`](@ref)
hold the mapping; [`ABSCISSAE`](@ref) and [`ORDINATES`](@ref) hold the vocabularies.

### Uncertainty

One spelling, one position: **`<quantity>_uncertainty`**, immediately after the quantity it
belongs to. `A nu nu_uncertainty`, never `A nu errnu`, and never a bare `uncertainty` column that
leaves the reader to work out which quantity it belongs to.

## Julia identifiers

| Kind | Case | Example |
| :--- | :--- | :--- |
| module, type | `CamelCase` | `ReducedDataset`, `TagRule` |
| function, macro | `lowercase_snake_case` | `load_configuration`, `element_symbol` |
| variable, field, keyword | `lowercase_snake_case` | `abscissa_columns`, `significant_digits` |
| constant | `SCREAMING_SNAKE_CASE` | `MAXIMUM_FRAGMENT_MASS` |

The nuclide numbers keep their symbols: `target_Z` and `target_A`, as configuration keys and as
fields.

The exported API is ASCII-typeable: every public function can be called without a compose key.

An action is `verb_object` — `parse_dataset`, `fetch_response`, `select_dataset`,
`reduce_dataset`, `write_dataset`; a predicate is `is_` or `has_`; anything else is named for
what it returns. `load_` means read and validate.

Type names carry no `Data` suffix and no adjective standing in for a noun: a type holding one
reduced dataset is `ReducedDataset`, and one holding an accepted dataset is `AcceptedDataset`.
The result type of a package is `<Verb>Result`, one per package: here,
[`RetrievalResult`](@ref).

Abbreviations are permitted only where the field itself uses them — `TKE`, `TXE`, `EXFOR`,
`AME`, `PFNS`, `sf` — and never as `err`, `param`, `calc`, `val`, `idx`, `num`, `cfg`, `pts`.

## Configuration files

A configuration is named `<system>_<observable>.toml`, the two tokens that name the directories
its data is written to. Sections are `[query]`, `[retrieval]` and `[output]`, and **a key is never
prefixed with its section's name**.

A key's comment states three things and nothing else: what the key is, in one short line; the
enumerated choices where it is constrained; and the bounds and the unit. No physics narrative, no
run rationale. The loader enforces exactly what the comment declares, so a retrieval cannot start
from a configuration it cannot honour.

**A key that can only be redundant or wrong is not in the file.** The EXFOR reaction code follows
from the entrance channel and the quantity code from the ordinate, so neither is written down; the
target's EXFOR symbol follows from `target_Z` and `target_A`, so it is not written down either.

## The system identifier

One token for a fissioning system, used as a directory name, a configuration file name and a
figure label key:

```
<ElementSymbol><A>_<entrance channel>
```

with the channel spelled as the field spells it and not as EXFOR codes it: `Cf252_sf`,
`U235_nth`, `U235_nres`, and `nfast` for a fast-neutron channel. `0f` is an EXFOR reaction code,
not a name, and the run record already carries the reaction code the archive returned for each
dataset it accepted.

The channel is what distinguishes a thermal from a resonance run of one observable, and it gives
each run a directory of its own under the same rule. Nothing else in the record can draw that
line: `n,f` is the reaction code of a thermal run and of a resonance run alike, which is why the
channel, and not the code, is what a figure label is keyed on.

## Directories, files and headers

```
data/
└── <system>/                        Cf252_sf, U235_nth, …
    └── <ordinate>_vs_<abscissa>/    nu_vs_A, nu_vs_A_TKE, spectrum_maxwellian_ratio_vs_E
        ├── retrieval.toml           the run record
        ├── <identifier>_<Author>_<year>.dat
        ├── relative/                arbitrary units, apart from the absolute data
        └── subentries/
            └── <identifier>_<Author>_<year>.txt
```

One directory per system, one subdirectory per observable, one file per measurement, named by
the dataset's identifier: the first eight characters of an identifier are the subentry accession
number; a ninth character marks a pointer into it. The directory carries the quantity and the file
carries the provenance, which is what makes the identifier recoverable from a figure legend.

`vs` is what makes an observable name a statement rather than a list of symbols. An abscissa is a
**list** of quantities, because it is a joint index, so `["mass", "total_kinetic_energy"]` needs
no composite token of its own and the directory follows from the same rule as every other:
`nu_vs_A_TKE`.

Extensions state a format and nothing else: `.dat` whitespace-separated, `.csv` comma-separated,
`.toml` metadata. A file extension never carries a nuclide.

One header line, ASCII, abscissae first, then the ordinate, then its uncertainty:

```
A nu nu_uncertainty
A TKE nu nu_uncertainty
E spectrum spectrum_uncertainty
```

**No column is named `value`.** Naming the column for its quantity is what frees the reader from
having to know the file name to know what it is holding.

Readers take columns **by position**, not by header text. That is what makes a header rename a
no-op for code, and it must stay that way: nothing downstream may be coupled to the header text.

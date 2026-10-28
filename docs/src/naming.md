```@meta
CurrentModule = ExforFissionData
```

# Naming

A quantity has one name in each of two registers, a word and a symbol, and keeps it everywhere it
appears: Julia identifier, struct field, configuration key, directory name, file name, column
header, figure label, prose. `multiplicity` in a configuration is `nu` in a path; the mapping
between the two registers is a table in `src/reaction_codes.jl`.

The corollary is the rule that decides the hard cases: **a name says what the thing is, not what
is convenient to type.** `Y_A_TKE` names three symbols and no relation between them; `Y_vs_A_TKE`
is a statement. `Data` as a suffix carries nothing. `err` names the wrong concept for an
uncertainty column — an error is not an uncertainty.

The vocabulary below governs the source, the configurations, the output layout and the figures.
Directory names, file names and column headers are written from its table, so anything reading
the retrieved data meets the same names.

## Two registers

| Register | Spelling | Where |
| :--- | :--- | :--- |
| word | `total_kinetic_energy` | configuration keys and values, prose, and the exported Julia names, fields and keywords |
| symbol | `TKE` | directory names, file names, column headers, figure labels |

A configuration is edited by hand and has to explain itself, so it spells a quantity out. A path
and a header are read at a glance and are the field's own nomenclature, so they carry the symbol.
`nu_vs_A_TKE` says exactly what `multiplicity_vs_mass_total_kinetic_energy` says, and a directory
listing stays readable.

Exported names, struct fields and configuration keys are word-register. A local variable or
internal argument that stands for a symbol of an equation is spelled as that symbol, `A₀` or `σ`
for instance.

## The quantities

| Word | Symbol | Quantity |
| :--- | :--- | :--- |
| `mass` | `A` | pre-neutron fragment mass |
| `product_mass` | `A_p` | post-neutron product mass |
| `charge` | `Z` | fragment charge |
| `neutron_energy` | `E` | secondary neutron energy |
| `total_kinetic_energy` | `TKE` | total kinetic energy, pre-neutron |
| `neutron_number` | `nu` | number of neutrons emitted in a fission |
| `total_kinetic_energy_dispersion` | `sigma_TKE` | standard deviation of the pre-neutron total kinetic energy at fixed mass, σ_TKE(A) |
| `post_neutron_total_kinetic_energy` | `TKE_p` | total kinetic energy, post-neutron |
| `fragment_kinetic_energy` | `E_K` | fragment kinetic energy, pre-neutron |
| `product_kinetic_energy` | `E_K_p` | fragment kinetic energy, post-neutron |
| `neutron_kinetic_energy` | `eps` | mean centre-of-mass neutron energy ⟨ε⟩ |
| `neutron_spectrum_temperature` | `T_eff` | effective temperature of the form fitted to the centre-of-mass neutron spectrum |
| `neutron_spectrum_exponent` | `lambda` | exponent of that form |
| `yield` | `Y` | fission yield |
| `multiplicity` | `nu` | prompt multiplicity per fragment, ν(A) |
| `multiplicity_per_fission` | `nu_bar` | prompt multiplicity per fragment pair, ν̄ |
| `multiplicity_distribution` | `P` | probability of emitting ν neutrons in a fission, P(ν) |
| `spectrum` | `spectrum` | prompt fission neutron spectrum |
| `spectrum_maxwellian_ratio` | `spectrum_maxwellian_ratio` | the spectrum as a ratio to a Maxwellian |
| `spectrum_cf252_ratio` | `spectrum_cf252_ratio` | the spectrum as a ratio to that of 252-Cf(sf) |
| `gamma_multiplicity_per_fission` | `M_gamma_bar` | prompt γ multiplicity per fission, M̄_γ |
| `gamma_multiplicity` | `M_gamma` | prompt γ multiplicity of one fragment |
| `gamma_energy_per_fission` | `E_gamma_tot` | total prompt γ energy per fission, E_γ,tot |
| `gamma_energy` | `E_gamma` | prompt γ energy of one fragment |
| `gamma_mean_energy` | `eps_gamma` | mean energy of a prompt γ photon, ε_γ |

A subscript is written with an underscore — `A_p`, `E_K`, `TKE_p`, `sigma_TKE`, `T_eff` — and
never run together: `T_eff`, not `Teff`. The temperature of the fitted spectrum is `T_eff`
because it is an effective temperature of a form, not the temperature of a nucleus.

The prompt-γ quantities follow the neutron ones: per fragment plain, per fission `_bar` for the
multiplicity as for ν̄, and `E_gamma_tot` for the energy per fission, the field's E_γ,tot. A
mean photon energy is `eps_gamma`, beside `eps` of the neutrons; `E_gamma_bar` would read as
that mean and is not used.

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

Abbreviations are permitted only where the field itself uses them (`TKE`, `EXFOR`, `sf`), and
never as `err`, `param`, `calc`, `val`, `idx`, `num`, `cfg`, `pts`.

## Configuration files

A configuration is named `<system>_<observable>.toml`, the two tokens that name the directories
its data is written to. Sections are `[query]`, `[retrieval]` and `[output]`, and **a key is never
prefixed with its section's name**.

A key's comment states what the key is, in one short line, the enumerated choices where it is
constrained, and the bounds and the unit; it carries no physics narrative or run rationale. The
loader enforces exactly what the comment declares; see [Configurations](configurations.md).

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

The channel distinguishes a thermal from a resonance run of one observable and gives each run a
directory of its own under the same rule. The reaction code cannot: it is `n,f` for both, so a
figure label is keyed on the channel.

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
name the provenance, so the identifier can be recovered from a figure legend.

The `vs` makes an observable name a statement, not a list of symbols. An abscissa is a
**list** of quantities, because it is a joint index, so `["mass", "total_kinetic_energy"]` needs
no composite token of its own and the directory follows from the same rule as every other:
`nu_vs_A_TKE`. A quantity per fission is tabulated against nothing, its abscissa the empty list,
and its directory is the ordinate symbol alone: `M_gamma_bar`, `E_gamma_tot`, `eps_gamma`, each
file one row.

Extensions state a format and nothing else: `.dat` whitespace-separated, `.csv` comma-separated,
`.toml` metadata. A file extension never carries a nuclide.

One header line, ASCII, abscissae first, then the ordinate, then its uncertainty:

```
A nu nu_uncertainty
A TKE nu nu_uncertainty
E spectrum spectrum_uncertainty
nu P P_uncertainty
E_gamma_tot E_gamma_tot_uncertainty
```

**No column is named `value`.** A column named for its quantity can be read without knowing the
file name.

Readers take columns **by position**, not by header text, so renaming a header changes nothing
for code. Nothing downstream may depend on the header text.

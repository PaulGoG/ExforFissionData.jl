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

Prompt neutron multiplicity against fragment mass, one panel per fissioning system. Each frame
advances through the datasets the archive offers for that query in the order the pipeline
processes them; a dataset enters the axes only where its reaction code answers the query. Thirty
datasets kept of 824 considered, with the run record naming the remainder and the reason each was
left out.

```julia
using ExforFissionData

configuration = load_configuration("config/Cf252_sf_nu_vs_A.toml")
result = retrieve(configuration)

length(result.accepted), length(result.rejected)
```

or from a shell,

```
julia scripts/retrieve.jl config/Cf252_sf_nu_vs_A.toml
```

## Observables

A quantity has one name in a configuration and one symbol in a path, a file name and a column
header.

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

An abscissa is a list, because it is a joint index: `["mass"]`, or
`["mass", "total_kinetic_energy"]` for ν(A, TKE). The retrieval is written to
`data/<system>/<observable>/`, where the system is an element symbol, a mass number and an
entrance channel — `Cf252_sf`, `U235_nth`, `U235_nres` — and the observable is the ordinate, `vs`,
then the abscissa symbols: `nu_vs_A_TKE`, `Y_vs_A`, `spectrum_maxwellian_ratio_vs_E`.

Not every combination exists in the archive. ν(TKE), for instance, is reported as a pair quantity,
so `multiplicity_per_fission` against `["total_kinetic_energy"]` returns data where
`multiplicity` returns none.

## Entrance channels

| Channel | Incident energy | Region |
| :--- | :--- | :--- |
| `sf` | — | spontaneous fission |
| `nth` | ≤ 0.1 eV | thermal: Maxwellian and 1/v region below the first resonances |
| `nres` | 0.1 eV to 100 keV | resolved and unresolved compound-nucleus resonances |
| `nfast` | 100 keV to 20 MeV | fast: the smooth statistical-model region |

`nth` spans 0 to 0.1 eV. Below the lowest resonances of the fissile actinides, 0.27 eV in ²³⁵U
and 0.30 eV in ²³⁹Pu, the cross section follows the 1/v law, which Doppler broadening leaves
unchanged (Bethe and Placzek 1937,
[10.1103/PhysRev.51.450](https://doi.org/10.1103/PhysRev.51.450)). A measurement there is
thermal in the sense of the Westcott convention, a Maxwellian at 293.6 K (kT = 0.0253 eV)
corrected by a g-factor, and 0.1 eV ≈ 4 kT is inside the region where that convention joins the
Maxwellian to the 1/E slowing-down spectrum; its epithermal cut-off is about 5 kT
([10.1088/2399-6528/aba735](https://doi.org/10.1088/2399-6528/aba735)). The cadmium cut-off of
0.5 eV that activation work uses as the thermal boundary lies above the first resonances
([10.1080/00223131.2016.1208593](https://doi.org/10.1080/00223131.2016.1208593)), and a
measurement on one of them is a resonance measurement.

`nres`, 0.1 eV to 100 keV, is the region in which the cross section carries compound-nucleus
level structure whose observed shape depends on temperature. The Doppler width Δ = 2√(E·kT/A)
is 0.01 eV at the first resonances, equals the s-wave level spacing of ²³⁵U (about 0.5 eV) near
0.5 keV, and is 6.6 eV at 100 keV, an order of magnitude above the spacings of the fissile
actinides: about 0.5 eV in ²³³U and ²³⁵U, about 2 eV in ²³⁹Pu (Mughabghab, *Atlas of Neutron
Resonances*, 6th ed., 2018,
[10.1016/C2015-0-00524-X](https://doi.org/10.1016/C2015-0-00524-X)). The evaluated libraries
end the unresolved resonance region at 25 keV for ²³⁵U and at a few tens of keV for ²³³U and
²³⁹Pu (ENDF/B-VIII.0, [10.1016/j.nds.2018.02.001](https://doi.org/10.1016/j.nds.2018.02.001);
JENDL-5, [10.1080/00223131.2022.2141903](https://doi.org/10.1080/00223131.2022.2141903)); above
it only averaged cross sections remain.

`nfast`, 100 keV to 20 MeV, is the fast group of reactor physics, E > 0.1 MeV: the smooth
statistical-model region above the unresolved resonances of every actinide this package targets,
up to the upper limit of the general-purpose evaluated files.

A spectrum qualifier in the reaction code can contradict the channel, and a dataset carrying one
is rejected: `FST`, `FIS` and `EPI` under `nth`; `MXW`, `FST` and `FIS` under `nres`; `EPI`
under `nfast` ([`CHANNEL_FORBIDDEN_QUALIFIERS`](@ref)). The archive files a spectrum-averaged
measurement under a dummy incident energy, so the window cannot catch it: `326650021`, ²³⁵U
independent yields under `,,FIS` from a fission-spectrum irradiation, is declared at 0.0253 eV
and would pass a thermal window on its energy alone. `SPA` names an unspecified spectrum and is
admitted everywhere; `MXW` is admitted under `nfast`, where it denotes a fission-Maxwellian
average.

The window of a configuration defaults to the channel's interval and is refused outside it.

## What the package does not do

**No normalisation is applied to ordinates.** Normalisation conventions differ between consumers
and cannot be undone once applied, so the unit token of each dataset is recorded instead. A query returning more than one unit token is flagged: such datasets
must not be renormalised together.

**No point is dropped on the basis of its value or uncertainty.** Quality cuts belong with the
project that can justify them. Values in the far-asymmetric mass tails are statistically poor and
are written unchanged, with their uncertainties.

**The uncertainty column is omitted** when no row of a dataset carries one, rather than written
as a column of zeros.

**Fragment and prompt-neutron observables only.** Prompt-γ quantities, the multiplicity
distribution P(ν), and the centre-of-mass spectrum Φ(ε) are outside the observable set; the last
the archive does not carry as a quantity of its own.

**Spectra between two fissioning systems** — the ratio form the archive holds a good deal of — are
a distinct observable and are excluded. A spectrum as a ratio to a Maxwellian is not: that is
`spectrum_maxwellian_ratio`.

**Relative data is retrieved but kept apart.** A prompt fission neutron spectrum is conventionally
measured relative and normalised afterwards, so most of what the archive holds for ²³⁵U(n,f) is in
arbitrary units. Those datasets are written under `relative/` rather than beside the absolute ones,
because a relative dataset cannot be put on a common scale with anything — not even
another relative dataset. Each must be normalised on its own, and none may be averaged with
absolute data. A reader that takes a whole directory therefore cannot pick one up by accident, and
the run record marks every accepted dataset `relative = true` or `false`.

Arbitrary units remain fatal for every other ordinate, where a relative value is not an
interpretable quantity.

## Conventions applied

Energies are restated in MeV — both an energy abscissa and an ordinate that is itself an energy.
These are exact conversions of a value with the factor recorded in the run record, which is a
different thing from a normalisation.

A written file holds one row per abscissa value. Several things put more than one row on a value,
and they are not handled alike:

| Cause | Treatment |
| :--- | :--- |
| several incident energies | the configured window selects rows; a dataset still holding more than one energy inside it is rejected rather than averaged |
| another independent variable the rendering declares | rejected where it varies; one held at a single value is a condition of the measurement and passes |
| isomeric states | the archive's own total where it gives one, otherwise the resolved states summed with uncertainties in quadrature |
| anything left | inverse-variance weighted mean, uncertainty ``1/\sqrt{\sum 1/\sigma^2}``, counted per dataset and named in a warning |

What is left is not only repetition. The `op=csv` rendering reports a mass as an integer, so a
dataset tabulated on a non-integer mass scale arrives truncated and its neighbouring points
collapse onto one mass number; and it drops independent variables it does not recognise, so a
grid over one of them arrives as unexplained repeats. The run record names every dataset in which
rows were combined, and the subentry stored beside the data settles which case it is.

## Selection

Datasets are chosen by substring tests over the EXFOR reaction code, for instance
`92-U-233(N,F)ELEM/MASS,CUM,FY`. The archive applies its own vocabulary inconsistently, so the
tables in `reaction_codes.jl` are empirical: they encode observed failures of the upstream
labelling rather than a formal grammar.

Three checks are worth naming because they are easy to get wrong:

- the `y:Value` column marks **upper limits** with a `Max(` prefix — those rows are bounds, not
  measurements;
- it also marks **arbitrary units** as `ARB-UNITS`, which carry no scale;
- the incident-energy window applies **per row**, not to the dataset as a whole, since one
  product is frequently reported at several energies;
- a variable the rendering declares in `indVars` and the abscissa does not hold **must not
  vary** — a mass yield at nine kinetic-energy gates is nine yields per mass number;
- `yield` requires the `FY` tag itself, since the quantity code `FY` also files the most probable
  charge against mass, `MASS,PAR,ZP`, which every mass rule admits.

Reaction-code qualifiers that bear on a value's scale — `MSC`, `REL`, `CHN`, `DERIV`, `FCT` — are
recorded per dataset rather than used to reject it, and so are those naming the inducing neutron
spectrum, except that a spectrum no measurement of the channel can have been made in rejects the
dataset; see [Entrance channels](@ref).

## Retrieval

Requests run under bounded concurrency with a per-request timeout and exponential backoff. Dataset
responses are cached on disk and served from the cache on a re-run. The listing of datasets is
requested on every run unless `offline = true` under `[retrieval]`, because the archive adds
entries and a cached listing never discovers them. When the archive cannot be reached, a request
falls back to the cached copy with a warning naming its date. `refresh = true` refetches
everything a run touches and replaces the cached copies, and `max_age_days` expires cached dataset
responses older than that many days. The run record dates the listing and every dataset, and
those dates are what "EXFOR as of" means for a consumer of the data. Datasets are processed and
written in identifier order, so a re-run over unchanged responses reproduces its output exactly.

## API

```@index
```

```@autodocs
Modules = [ExforFissionData]
```

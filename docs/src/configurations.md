```@meta
CurrentModule = ExforFissionData
```

# Configurations

A configuration is named `<system>_<observable>.toml`, the same two tokens that name the
directories its data is written to. Sections are `[query]`, `[retrieval]` and `[output]`. Every
key is validated as the file is read: a value of the wrong type, one outside its bounds, or one
that is not among the enumerated choices stops the run with a message naming the offending key,
so a retrieval cannot start from a configuration it cannot honour. A section or a key the loader
does not know is refused as well — a misspelt `energy_max` would otherwise leave the window open
to every incident energy — and so is an energy window on `sf`, which has no incident particle.

## Keys

| Section | Key | Meaning | Allowed values / bounds | Default |
| :--- | :--- | :--- | :--- | :--- |
| `[query]` | `target_Z` | atomic number of the target | 1 to 118 | required |
| `[query]` | `target_A` | mass number of the target | at least `target_Z`, at most 300 | required |
| `[query]` | `channel` | entrance channel; fixes the incident-energy interval, see [Entrance channels](channels.md) | `"sf"`, `"nth"`, `"nres"`, `"nfast"` | required |
| `[query]` | `abscissa` | quantities the observable is tabulated against | `["mass"]`, `["product_mass"]`, `["charge"]`, `["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]`, `["mass", "total_kinetic_energy"]` | required |
| `[query]` | `ordinate` | the observable | `"yield"`, `"multiplicity"`, `"multiplicity_per_fission"`, `"fragment_kinetic_energy"`, `"product_kinetic_energy"`, `"total_kinetic_energy"`, `"post_neutron_total_kinetic_energy"`, `"neutron_kinetic_energy"`, `"spectrum"`, `"spectrum_maxwellian_ratio"` | required |
| `[query]` | `energy_min` | lower edge of the incident-energy window, MeV | must lie inside the channel's interval (`nth` 0 to 1.0e-7 (0.1 eV), `nres` 1.0e-7 (0.1 eV) to 0.1, `nfast` 0.1 to 20); not allowed for `sf` | the channel's floor |
| `[query]` | `energy_max` | upper edge of the incident-energy window, MeV | above `energy_min`; must lie inside the channel's interval (`nth` 0 to 1.0e-7 (0.1 eV), `nres` 1.0e-7 (0.1 eV) to 0.1, `nfast` 0.1 to 20); not allowed for `sf` | the channel's ceiling |
| `[retrieval]` | `concurrency` | simultaneous requests | 1 to 16 | 4 |
| `[retrieval]` | `timeout` | per-request timeout, seconds | positive | 60.0 |
| `[retrieval]` | `retries` | retry attempts after a failure | 0 to 10 | 4 |
| `[retrieval]` | `backoff` | base of the exponential backoff, seconds | positive | 1.0 |
| `[retrieval]` | `use_cache` | read and write the on-disk response cache | boolean | `true` |
| `[retrieval]` | `refresh` | refetch every response and replace the cached copy; needs `use_cache` | boolean | `false` |
| `[retrieval]` | `save_subentries` | store the original EXFOR subentry text beside the data | boolean | `true` |
| `[retrieval]` | `cache_directory` | where responses are cached | string; empty selects the default | the `Scratch.jl` space |
| `[retrieval]` | `offline` | serve every response from the cache and never contact the archive; needs `use_cache`, excludes `refresh` | boolean | `false` |
| `[retrieval]` | `max_age_days` | a cached dataset response older than this is requested again, the cached copy kept as the fallback | positive number | none (never expires) |
| `[output]` | `directory` | root for retrieved data, relative to the output root | string | `"data"` |
| `[output]` | `significant_digits` | significant digits in tabulated output | 1 to 15 | 7 |
| `[output]` | `record_hostname` | name the machine in the run record | boolean | `false` |

`[query]` and its five required keys must be present. `[retrieval]` and `[output]` may be omitted
entirely, in which case every key they hold takes its default.

The listing of datasets is requested on every run that is not offline, because the archive adds
entries and a cached listing never discovers them. Dataset responses are served from the cache.
Anything the archive cannot serve falls back to the cached copy with a warning, and the run record
carries the retrieval date of the listing and of every dataset.

## Shipped configurations

### 252-Cf(sf)

The incident-energy window is not applied to spontaneous fission, which has no incident particle,
so these configurations omit `energy_min` and `energy_max`.

- `Cf252_sf_Y_vs_A` — pre-neutron mass yields.
- `Cf252_sf_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `Cf252_sf_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `Cf252_sf_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.
- `Cf252_sf_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, against
  secondary neutron energy.

### 235-U(nth,f)

- `U235_nth_Y_vs_A` — pre-neutron mass yields.
- `U235_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U235_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U235_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.
- `U235_nth_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, against
  secondary neutron energy.

### 235-U resonance region

The companion `U235_nth_*` configurations admit thermal incident neutrons only. The GELINA
measurements are made on a resonance-neutron beam whose spectrum-averaged energy is about 580 eV,
so a thermal window excludes them by their own terms. The window of both configurations below is
0.1 eV to 1 keV, the floor being the channel's, and admits those alone; the thermal datasets
belong to the `nth` runs. The `nres` channel is what keeps the two runs apart, so neither has to
be written under a directory of its own.

- `U235_nres_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U235_nres_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.

### 233-U(nth,f)

- `U233_nth_Y_vs_A` — pre-neutron mass yields.
- `U233_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U233_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U233_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.
- `U233_nth_TKE_vs_A` — pre-neutron total kinetic energy against pre-neutron fragment mass. The
  mass dependence of ⟨TKE⟩ is what a Y(A, TKE) carries and a single mean does not. No Y(A, TKE)
  exists for this system, so this is the closest the archive comes.

### 239-Pu(nth,f)

- `Pu239_nth_Y_vs_A` — pre-neutron mass yields.
- `Pu239_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `Pu239_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `Pu239_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.

## Spectra

A prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
so most of what the archive holds is in arbitrary units. Those datasets are retrieved and written
under `relative/`, apart from the absolute ones: each carries a shape and no scale, and none can
be put on a common scale with another.

The spectrum as a ratio to a Maxwellian is the form much of the published spectrum comparison is
done in, and a separate observable from `spectrum`: the archive codes it with MXD, which
`spectrum` excludes. Being a ratio, it is dimensionless and carries its own normalisation, which is
what makes it comparable between laboratories where the absolute spectra are reported in arbitrary
units.

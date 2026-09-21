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

| Section | Key | Meaning | Allowed values / bounds |
| :--- | :--- | :--- | :--- |
| `[query]` | `target_Z` | atomic number of the target | 1 to 118 |
| `[query]` | `target_A` | mass number of the target | at least `target_Z`, at most 300 |
| `[query]` | `channel` | entrance channel | `"sf"`, `"nth"`, `"nres"`, `"nfast"` |
| `[query]` | `abscissa` | quantities the observable is tabulated against | `["mass"]`, `["product_mass"]`, `["charge"]`, `["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]`, `["mass", "total_kinetic_energy"]` |
| `[query]` | `ordinate` | the observable | `"yield"`, `"multiplicity"`, `"multiplicity_per_fission"`, `"fragment_kinetic_energy"`, `"product_kinetic_energy"`, `"total_kinetic_energy"`, `"post_neutron_total_kinetic_energy"`, `"neutron_kinetic_energy"`, `"spectrum"`, `"spectrum_maxwellian_ratio"` |
| `[query]` | `energy_min` | lower edge of the incident-energy window, MeV | at least 0 |
| `[query]` | `energy_max` | upper edge of the incident-energy window, MeV | above `energy_min` |
| `[retrieval]` | `concurrency` | simultaneous requests | 1 to 16 |
| `[retrieval]` | `timeout` | per-request timeout, seconds | positive |
| `[retrieval]` | `retries` | retry attempts after a failure | 0 to 10 |
| `[retrieval]` | `backoff` | base of the exponential backoff, seconds | positive |
| `[retrieval]` | `use_cache` | read and write the on-disk response cache | boolean, default `true` |
| `[retrieval]` | `refresh` | refetch every response and replace the cached copy; needs `use_cache` | boolean, default `false` |
| `[retrieval]` | `save_subentries` | store the original EXFOR subentry text beside the data | boolean, default `true` |
| `[retrieval]` | `cache_directory` | where responses are cached | string, default empty: a `Scratch.jl` space |
| `[output]` | `directory` | root for retrieved data, relative to the output root | string, default `"data"` |
| `[output]` | `significant_digits` | significant digits in tabulated output | 1 to 15 |
| `[output]` | `record_hostname` | name the machine in the run record | boolean, default `false` |

## Shipped configurations

### 252-Cf(sf)

The incident-energy window is not applied to spontaneous fission, which has no incident particle,
so these configurations omit `energy_min` and `energy_max`.

- `Cf252_sf_Y_vs_A` — pre-neutron mass yields.
- `Cf252_sf_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `Cf252_sf_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `Cf252_sf_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy. A
  prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
  so much of what the archive holds is in arbitrary units. Those datasets are retrieved and
  written under `relative/`, apart from the absolute ones: each carries a shape and no scale, and
  none can be put on a common scale with another.
- `Cf252_sf_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, against
  secondary neutron energy. This is the form much of the published spectrum comparison is done in,
  and a separate observable from `spectrum`: the archive codes it with MXD, which `spectrum`
  excludes. Being a ratio, it is dimensionless and carries its own normalisation, which is what
  makes it comparable between laboratories where the absolute spectra are reported in arbitrary
  units.

### 235-U(nth,f)

- `U235_nth_Y_vs_A` — pre-neutron mass yields.
- `U235_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U235_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U235_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy. A
  prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
  so most of what the archive holds is in arbitrary units. Those datasets are retrieved and
  written under `relative/`, apart from the absolute ones: each carries a shape and no scale, and
  none can be put on a common scale with another.
- `U235_nth_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, against
  secondary neutron energy. This is the form much of the published spectrum comparison is done in,
  and a separate observable from `spectrum`: the archive codes it with MXD, which `spectrum`
  excludes. Being a ratio, it is dimensionless and carries its own normalisation.

### 235-U resonance region

- `U235_nres_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass. The
  companion `U235_nth_nu_vs_A.toml` admits thermal incident neutrons only. The GELINA measurements
  are made on a resonance-neutron beam whose spectrum-averaged energy is about 580 eV, so a
  thermal window excludes them by their own terms. Widening the window to 1 keV admits those and
  nothing else. The `nres` channel is what keeps the two runs apart, so neither has to be written
  under a directory of its own.
- `U235_nres_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly. The window reaches to 1 keV rather than stopping at thermal for
  the reason given above: the GELINA measurements sit at a spectrum-averaged 580 eV.

### 233-U(nth,f)

- `U233_nth_Y_vs_A` — pre-neutron mass yields.
- `U233_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U233_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U233_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy. A
  prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
  so most of what the archive holds is in arbitrary units. Those datasets are retrieved and
  written under `relative/`, apart from the absolute ones: each carries a shape and no scale, and
  none can be put on a common scale with another.
- `U233_nth_TKE_vs_A` — pre-neutron total kinetic energy against pre-neutron fragment mass. The
  mass dependence of ⟨TKE⟩ is what a Y(A, TKE) carries and a single mean does not. No Y(A, TKE)
  exists for this system, so this is the closest the archive comes.

### 239-Pu(nth,f)

- `Pu239_nth_Y_vs_A` — pre-neutron mass yields.
- `Pu239_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `Pu239_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `Pu239_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy. A
  prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
  so most of what the archive holds is in arbitrary units. Those datasets are retrieved and
  written under `relative/`, apart from the absolute ones: each carries a shape and no scale, and
  none can be put on a common scale with another.

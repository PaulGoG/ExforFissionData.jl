```@meta
CurrentModule = ExforFissionData
```

# Configurations

A configuration is named `<system>_<observable>.toml`, the same two tokens that name the
directories its data is written to. Sections are `[query]`, `[retrieval]` and `[output]`, for
the width of the TKE distribution the tables `[[width]]`, and for the parameters of the form
fitted to the centre-of-mass neutron spectrum the tables `[[fit_parameter]]`. Every
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
| `[query]` | `abscissa` | quantities the observable is tabulated against | `["mass"]`, `["product_mass"]`, `["charge"]`, `["neutron_energy"]`, `["total_kinetic_energy"]`, `["charge", "product_mass"]`, `["mass", "total_kinetic_energy"]`, `["neutron_number"]`, `[]` (a quantity per fission, prompt-γ ordinates only) | required |
| `[query]` | `ordinate` | the observable | `"yield"`, `"multiplicity"`, `"multiplicity_per_fission"`, `"fragment_kinetic_energy"`, `"product_kinetic_energy"`, `"total_kinetic_energy"`, `"total_kinetic_energy_dispersion"`, `"post_neutron_total_kinetic_energy"`, `"neutron_kinetic_energy"`, `"neutron_spectrum_temperature"`, `"neutron_spectrum_exponent"`, `"multiplicity_distribution"`, `"spectrum"`, `"spectrum_maxwellian_ratio"`, `"spectrum_cf252_ratio"`, `"gamma_multiplicity_per_fission"`, `"gamma_energy_per_fission"`, `"gamma_mean_energy"`, `"gamma_multiplicity"`, `"gamma_energy"` | required |
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
| `[retrieval]` | `base_url` | archive endpoint every request is made relative to; a mirror may be named instead | an http or https URL ending in `/` | `"https://nds.iaea.org/exfor/"` |
| `[retrieval]` | `offline` | serve every response from the cache and never contact the archive; needs `use_cache`, excludes `refresh` | boolean | `false` |
| `[retrieval]` | `max_age_days` | a cached dataset response older than this is requested again, the cached copy kept as the fallback | positive number | none (never expires) |
| `[output]` | `directory` | root for retrieved data, relative to the output root | string | `"data"` |
| `[output]` | `significant_digits` | significant digits in tabulated output | 1 to 15 | 7 |
| `[output]` | `record_hostname` | name the machine in the run record | boolean | `false` |
| `[[width]]` | `subentry` | EXFOR dataset whose column holds a width | 8 characters, or 9 with its pointer; each once | required in each table |
| `[[width]]` | `column` | DATA heading of the width | a MISC-type heading; not `DATA`, an uncertainty or a variable | required in each table |
| `[[width]]` | `holds` | what the column holds | `"standard_deviation"`, `"variance"`, `"fwhm"`, `"hwhm"` | required in each table |
| `[[width]]` | `of` | whose energy the width is of | `"total_kinetic_energy"`, `"fragment_kinetic_energy"` | required in each table |
| `[[fit_parameter]]` | `subentry` | EXFOR dataset whose column holds the parameter | 8 characters, or 9 with its pointer; each once | required in each table |
| `[[fit_parameter]]` | `column` | DATA heading of the parameter | a MISC-type heading; not `DATA`, an uncertainty or a variable | required in each table |

`[query]` and its five required keys must be present. `[retrieval]` and `[output]` may be omitted
entirely, in which case every key they hold takes its default. `[[width]]` is required, at least
once, for the ordinate `"total_kinetic_energy_dispersion"` against `["mass"]`, and refused for
every other ordinate: EXFOR has no code for the width of a kinetic-energy distribution, so a
width is read only from the columns these tables name, never from free text and never from the
datum. See [Observables](observables.md).

`[[fit_parameter]]` is required, at least once, for the ordinates
`"neutron_spectrum_temperature"` and `"neutron_spectrum_exponent"` against `["mass"]`, and
refused for every other ordinate. Each table names a dataset of the mean neutron energy and the
`MISC` column that holds the parameter, whose uncertainty is read from the column `<column>-ERR`.

The listing of datasets is requested on every run that is not offline, because the archive adds
entries and a cached listing never discovers them. Dataset responses are served from the cache.
Anything the archive cannot serve falls back to the cached copy with a warning, and the run record
carries the retrieval date of the listing and of every dataset.

## Shipped configurations

The mass yield, the mean TKE and its width against mass, or the joint yield, are what a
pre-neutron Y(A, TKE) is built from. Each is retrieved experiment by experiment, with the
accession in every file name, so that a consumer can take the three marginals of one
measurement, or its joint matrix, together. The post-neutron products — the mass yield Y(A_p),
the independent yields Y(Z, A_p) and the product kinetic energy E_K_p(A_p) — are retrieved for
the same four systems under `Y_vs_A_p`, `Y_vs_Z_A_p` and `E_K_p_vs_A_p`. Datasets of one
measurement name each other as `correlated_with`, with the relation of their group (see
[Conventions and selection](conventions.md)); the lists below give the relation alone.

### 252-Cf(sf)

The incident-energy window is not applied to spontaneous fission, which has no incident particle,
so these configurations omit `energy_min` and `energy_max`.

- `Cf252_sf_Y_vs_A` — pre-neutron mass yields.
- `Cf252_sf_TKE_vs_A` — pre-neutron total kinetic energy against pre-neutron fragment mass.
- `Cf252_sf_sigma_TKE_vs_A` — the standard deviation of the pre-neutron TKE against mass, from
  the width columns of 23268004 (Göök 2014), 23717004 and 23717006 (Barreau 1985) and 22780003
  (Hambsch 1997); the width column of 12709004 (Weber 1981) is refused as no width.
- `Cf252_sf_Y_vs_A_TKE` — the joint pre-neutron yield Y(A, TKE): 23268002 (Göök 2014), 30 000
  cells of counts, written under `relative/`.
- `Cf252_sf_Y_vs_A_p` — post-neutron mass yields, 18 datasets, 6 coded `SEC` and 12 `CHN`:
  13081002 (Schmitt 1965), 14259009 (Romano 2010), 14420002 (Meierbachtol 2015), 14652002 and
  14652003 (Britt 1964) and 14790002 (Gastis 2022); the chain yields of note are 14020002 (Kiker
  1964), 33158006 (Naik 2021), 30691002 (Li Ze 1983), 21531003 (Thierens 1976), 21592002
  (Blachot 1975) and 13283008 (Harbour 1971), flagged as chain yields in the record.
- `Cf252_sf_Y_vs_Z_A_p` — independent yields of nuclides: nine tables of one to 15 nuclides,
  23560003 (Erten 1978) read from the constants `ELEMENT` and `MASS` of its COMMON section. Refused:
  the 15 yields of correlated fragment pairs coded `CRN`, 13648002 to 13648006, 13749002 and
  14634002 among them, and 5 fractional yields coded `FRC`.
- `Cf252_sf_E_K_p_vs_A_p` — post-neutron kinetic energy against product mass; the archive holds
  none for this system. Its post-neutron kinetic energies, 32928002 and 32928003, are
  `ELEM,SEC,AKE`, resolved in charge rather than mass, and the configuration writes nothing.
- `Cf252_sf_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass. 41720002
  (Basova 1979) and 41694002 (Zamyatnin 1979), which differ by 0.34 neutrons rms over 80 shared
  masses, are two reductions of one measurement, relation `alternative_analysis`.
- `Cf252_sf_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `Cf252_sf_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy. The
  subentry of 40644003 (Starostov 1979, arbitrary units, under `relative/`) marks it superseded by
  40644002, normalised to the number of neutrons, and preliminary; that of 40875002 (Dyachenko 1989,
  absolute) marks it superseded by 41158002 (Lajtai 1990, arbitrary units, under `relative/`). Each
  pair is written; the superseded one carries a qualifier beginning `superseded:`, and 40644003 one
  beginning `preliminary:` too. 14477002 and 14477003 (Blain 2017), the high- and low-energy
  portions of one measurement, and 40064027 and 40064031 (Kroshkin 1970), two figures of one
  measurement, are relation `complementary_range`; 40064027 is tabulated as N(E)/√E; the subentry of
  40064031 heads the energies `MEV` where they are keV, and the table is written from keV. 40418004
  and 40418005 (Blinov 1973), one spectrum at two flight paths, are relation `repeated_run`.
  30099003 (Jeki 1971) is derived from 30099002, relation `dependent`. 23175004, 40064027, 40250003
  and 41689002 are N(E)/√E and carry a qualifier beginning `spectrum_form:`; V0101002 (Mannhart
  1987) is an evaluation and carries one beginning `evaluation:`.
- `Cf252_sf_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, against
  secondary neutron energy. 40418006, 40418007 and 40418008 (Blinov 1973) are one group of relation
  `dependent`: 40418008, the table, is formed from 40418007, the ratio at 50 cm, and supersedes
  40418006, read off a figure, which carries a qualifier beginning `superseded:`; one of the three
  is used. The subentry of 40875003 (Dyachenko 1989), with uncertainties, marks it superseded by
  41158003 (Lajtai 1990), which states none; both are written, and 40875003 carries a qualifier
  beginning `superseded:`. The ten datasets of 22202 (Chalupka 1990) are selections of one
  measurement by energy grouping and detector bias, relation `alternative_analysis`: one
  measurement, never counted as several. 40535002 to 40535005 (Blinov 1980) are one spectrum at four
  flight paths over successive ranges, relation `complementary_range`.
- `Cf252_sf_eps_vs_A` — mean centre-of-mass neutron energy against fragment mass, from 14065003
  (Bowman 1963), 23175012 (Budtz-Jørgensen 1988), 23268011 (Göök 2014) and 41689005 (Piksaykin
  1977), the second and fourth headed `DATA` and in the centre of mass by their publications.
- `Cf252_sf_eps_vs_A_TKE` — the same against mass and TKE jointly: 14065010 (Bowman 1963), 228
  rows at ten TKE values from 163.5 to 217.5 MeV. Refused: 14065008, whose ten mean masses lie
  about 5 u apart and bracket no integer mass within the 3-u interpolation span, and 23175013,
  one mass, 110, held in COMMON, a slice against TKE rather than the joint observable.
- `Cf252_sf_T_eff_vs_A` — the effective temperature T_eff of the form fitted to the
  centre-of-mass neutron spectrum against fragment mass: `MISC1` of 23175012 (Budtz-Jørgensen
  1988), 79 masses, 0.77 to 1.39 MeV, and `MISC` of 23268011 (Göök 2014), 82 masses of its 109,
  0.72 to 1.40 MeV.
- `Cf252_sf_lambda_vs_A` — the exponent λ of the same form against fragment mass: `MISC2` of
  23175012 (Budtz-Jørgensen 1988), 79 masses, 0.11 to 0.94.
- `Cf252_sf_P_vs_nu` — the multiplicity distribution P(ν): 10605005 (Stoughton 1973), 10901006
  (Hoffman 1980), 12337013 (Diven 1956), 12833005 (Gwin 1984), 13715014 (Hicks 1956), 21495003
  (Baron 1966), 30046011 (Boldeman 1967), 307720151, 307720152 and 307720153 (Boldeman 1985, at
  three discriminator biases) and 41425002 (Vorobiev 2001). 30046011 and the three of 30772015 are
  one measurement. 10300005, 10930004 and 14064002 are refused, their means too far from ν̄ for
  distributions of the neutrons emitted.

### 235-U(nth,f)

- `U235_nth_Y_vs_A` — pre-neutron mass yields. 417380041 and 417380042 (Zeynalov 2019) carry a
  qualifier beginning `preliminary:`.
- `U235_nth_TKE_vs_A` — pre-neutron total kinetic energy against pre-neutron fragment mass.
- `U235_nth_sigma_TKE_vs_A` — the standard deviation of the pre-neutron TKE against mass, from
  23014003 (Baba 1997), 40235017 (D'yachenko 1968, a variance) and 40200003 (Zakharova 1973).
- `U235_nth_Y_vs_A_TKE` — the joint yield; the archive holds none for this system, and the
  record lists the slices it holds instead.
- `U235_nth_Y_vs_A_p` — post-neutron mass yields, 37 datasets, 7 coded `SEC` and 30 `CHN`: 14208003
  (Derengowski 1970), 14259005 (Romano 2010), 21752016 (Wagemans 1981), 21981012 (Geltenbort 1985),
  23594002 (Shiraishi 1968), 31738002 (Koblik 2014) and 32888002 (Liu 2022); the chain yields of
  note are 316850021 and 316850022 (Ajitanand 1978), 13359002 (Diiorio 1977), 33186006 (Naik 2023),
  21543013 (Asghar 1977), 10865002 (Maeck 1978), 21531002 (Thierens 1976), 21054087 (Wohlfarth
  1976), 13270003 (Lisman 1970) and 22985006 (Bail 2009), flagged as chain yields in the record.
  31738002 sums to 1.82 over the heavy group alone, A_p 125 to 155, and is written as the archive
  gives it.
- `U235_nth_Y_vs_Z_A_p` — independent yields of nuclides, 52 datasets. The large tables are 10722003
  (Strittmatter 1977), 21689019 (Lang 1980), 221610021 (Rudstam 1990), 22151003 (Sida 1989),
  23586004 (Armbruster 1987), 23558007 (Günther 1972) and 13600002 (Tipnis 1998); the rest are
  radiochemical tables of a few nuclides each, and 21 datasets are read from constants of a COMMON
  section. Refused: 21689014 to 21689018 (Lang 1980), partial yields each at one product kinetic
  energy, and 39 fractional yields coded `FRC`.
- `U235_nth_E_K_p_vs_A_p` — post-neutron kinetic energy against product mass, in MeV: 21543017
  (Asghar 1977), 21313014 (Asghar 1978), 21752017 (Wagemans 1981), 21981015 (Geltenbort 1985),
  23551003 and 23551004 (Konecny 1970), the second combined over its cooling times in `MISC1` to
  `MISC3`, 235580032 (Günther 1972), 31797003 (Bakhromi 1982) and 41496005 (Aleksandrov 1994),
  interpolated from non-integer masses.
- `U235_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass. 41516012
  (Vorobyev 2010) carries a qualifier beginning `preliminary:`.
- `U235_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U235_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.
  40871007 and 40871015 (Nefedov 1983), at the flight paths of 51 cm and 2.313 m, are one
  measurement in two parts, relation `complementary_range`.
- `U235_nth_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, against
  secondary neutron energy. 40930006, 40930013, 40930014 and 40930015 (Starostov 1985) are one
  measurement in four parts, the first cycle with each of three detectors and the second cycle.
- `U235_nth_spectrum_cf252_ratio_vs_E` — the spectrum as a ratio to that of 252-Cf(sf): 40871011 and
  40871012 (Nefedov 1983), 40872007 (Starostov 1983) and 41516017 (Vorobyev 2010), 252-Cf over
  235-U, and 41597002 (Vorobyev 2013), 235-U over 252-Cf. The subentry of 41516017 marks it
  superseded by 41597002; both are written, and 41516017 carries a qualifier beginning `superseded:`
  and one beginning `preliminary:`.
- `U235_nth_eps_vs_A` — mean centre-of-mass neutron energy against fragment mass, from 22464003
  (Nishio 1998), interpolated from a half-integer 2-u grid, and 41502008 (Batenkov 2004);
  23164022 (Al-Adili 2016), fragment kinetic energies, is refused on its magnitude.
- `U235_nth_P_vs_nu` — the multiplicity distribution P(ν): 12833007 (Gwin 1984), 30046008 (Boldeman
  1967), 30772010 (Boldeman 1985), 32820002 (Huang 1961) and V0045012 (Holden 1988), an evaluation,
  written and carrying a qualifier beginning `evaluation:`. The subentry of 30046008 marks it
  superseded by 30772010; both are written, and 30046008 carries a qualifier beginning
  `superseded:`. Refused: 12337009 (Diven 1956), at 80 keV, and 30544002, derived from a model.

### 235-U resonance region

The companion `U235_nth_*` configurations admit thermal incident neutrons only. The GELINA
measurements are made on a resonance-neutron beam whose spectrum-averaged energy is about 580 eV,
so a thermal window excludes them by their own terms. The window of the configurations below is
0.1 eV to 1 keV, the floor being the channel's, and admits those alone; the thermal datasets
belong to the `nth` runs. The `nres` channel keeps the two runs apart: `U235_nres` is a system of
its own and is written to its own directory under the ordinary rule.

- `U235_nres_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U235_nres_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U235_nres_eps_vs_A` — mean centre-of-mass neutron energy against fragment mass: 23444006 (Göök
  2018) at 580 eV, flagged `SPA` like the ν(A) of this channel.

### 233-U(nth,f)

- `U233_nth_Y_vs_A` — pre-neutron mass yields.
- `U233_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass.
- `U233_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `U233_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.
- `U233_nth_TKE_vs_A` — pre-neutron total kinetic energy against pre-neutron fragment mass.
- `U233_nth_sigma_TKE_vs_A` — the standard deviation of the pre-neutron TKE against mass, from
  23014002 (Baba 1997).
- `U233_nth_Y_vs_A_TKE` — the joint yield; the archive holds none for this system.
- `U233_nth_Y_vs_A_p` — post-neutron mass yields, 14 datasets, 3 coded `SEC` and 11 `CHN`:
  21981011 (Geltenbort 1985), 23784002 (Chebboubi 2021) and 41496006 (Aleksandrov 1994); the
  chain yields of note are 132700021 and 132700022 (Lisman 1970), 33187006 (Naik 2023), 21771012
  (Asghar 1981), 10918004 (Wehring 1980) and 13208002 to 13208004 (Bidinosti 1961), flagged as
  chain yields in the record.
- `U233_nth_Y_vs_Z_A_p` — independent yields of nuclides, 18 datasets. The large tables are 10918003
  (Wehring 1980) and 23794002 (Johansson 1997); the rest are radiochemical tables of a few nuclides
  each, and 5 datasets are read from constants of a COMMON section. Refused: 11 fractional yields
  coded `FRC`.
- `U233_nth_E_K_p_vs_A_p` — post-neutron kinetic energy against product mass, in MeV: 21981014
  (Geltenbort 1985) and 23784003 (Chebboubi 2021).
- `U233_nth_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, from
  40873002, 40930004, 40930010, 40930011, 40930012 and 41611010, all formed with T = 1.34 MeV. The
  four of 40930 (Starostov 1985) are one measurement in four parts, the first cycle with each of
  three detectors and the second cycle.
- `U233_nth_spectrum_cf252_ratio_vs_E` — the spectrum as a ratio to that of 252-Cf(sf): 40871013
  (Nefedov 1983) and 40872008 (Starostov 1983), 252-Cf over 233-U, and 416110021 (Vorobyev 2016),
  233-U over 252-Cf in arbitrary units, under `relative/`.
- `U233_nth_eps_vs_A` — mean centre-of-mass neutron energy against fragment mass, from 14369005
  (Fraser 1966), headed `DATA` and in the centre of mass by its publication, and 22660003 (Nishio
  1998).
- `U233_nth_eps_vs_A_TKE` — the same against mass and TKE jointly: 22660004 (Nishio 1998), headed
  `DATA` and in the centre of mass by its publication.
- `U233_nth_P_vs_nu` — the multiplicity distribution P(ν): 12833006 (Gwin 1984), 30046007 (Boldeman
  1967), 30772009 (Boldeman 1985) and V0045011 (Holden 1988), an evaluation, written and carrying a
  qualifier beginning `evaluation:`. The subentry of 30046007 marks it superseded by 30772009; both
  are written, and 30046007 carries a qualifier beginning `superseded:`. Refused: 12337008 (Diven
  1956), at 80 keV.

### 239-Pu(nth,f)

- `Pu239_nth_Y_vs_A` — pre-neutron mass yields.
- `Pu239_nth_TKE_vs_A` — pre-neutron total kinetic energy against pre-neutron fragment mass.
- `Pu239_nth_sigma_TKE_vs_A` — the standard deviation of the pre-neutron TKE against mass, from
  23012005 and 23012006 (Nishio 1995), the second a width of one fragment's energy.
- `Pu239_nth_Y_vs_A_TKE` — the joint yield; the archive holds none for this system, and the
  record lists the slices it holds instead.
- `Pu239_nth_Y_vs_A_p` — post-neutron mass yields, 26 datasets, 10 coded `SEC` and 16 `CHN`:
  21981013 (Geltenbort 1985); 222730131, 222730132 and 22273014 (Schillebeeckx 1992), coded
  `DERIV` and flagged among their `qualifiers`; 23342002 to 23342005 (Gupta 2017); 23583002
  (Boucheneb 1991); and 32879002 (Liu 2022). The chain yields of note are 33178006 (Naik 2022),
  21544008 (Asghar 1978), 22985005 (Bail 2009), 13482002, 134800021 and 134800022 (Fickel 1959)
  and 13270008 (Lisman 1970), flagged as chain yields in the record.
- `Pu239_nth_Y_vs_Z_A_p` — independent yields of nuclides, 24 datasets. The large tables are
  23558006 (Günther 1972) and 22985008 (Bail 2009); the rest are radiochemical tables of a few
  nuclides each, and 9 datasets are read from constants of a COMMON section. Refused: 15 fractional
  yields coded `FRC`.
- `Pu239_nth_E_K_p_vs_A_p` — post-neutron kinetic energy against product mass, in MeV: 21544009
  (Asghar 1978), 21981016 (Geltenbort 1985), 235580022 (Günther 1972), 23583003 (Boucheneb 1991)
  and 416930051 (Belyaev 1988).
- `Pu239_nth_nu_vs_A` — prompt neutron multiplicity per fragment against fragment mass. 41720004
  (Basova 1979) and 41694003 (Zamyatnin 1979), which differ by 0.36 neutrons rms over 73 shared
  masses, are two reductions of one measurement, relation `alternative_analysis`: one measurement,
  taken singly or combined as one, never counted as two. 22650004 (Tsuchiya 2000) is normalised to
  2.88 neutrons per fission by its publication; its pair sum, 3.9 % above ν̄, measures the
  consistency of its table with that normalisation. 23012008 (Nishio 1995) is the difference of the
  pre- and post-neutron masses of one measurement of both fragment velocities and energies, no
  neutron being detected; it carries a qualifier beginning `multiplicity_from_masses:`, and its
  publication gives its total as 3.2 ± 0.1, about 10 % above the evaluation it compares with.
- `Pu239_nth_nu_vs_A_TKE` — prompt neutron multiplicity per fragment against fragment mass and
  total kinetic energy jointly.
- `Pu239_nth_spectrum_vs_E` — prompt fission neutron spectrum against secondary neutron energy.
  40871006 and 40871014 (Nefedov 1983), at the flight paths of 51 cm and 2.313 m, are one
  measurement in two parts, relation `complementary_range`.
- `Pu239_nth_spectrum_maxwellian_ratio_vs_E` — the spectrum as a ratio to a Maxwellian, from
  40873006 (Boytsov 1983), 40930008, 40930016, 40930017 and 40930018 (Starostov 1985) and 41611011
  (Vorobyev 2016), all formed with T = 1.382 MeV; 14684003, from 0.95 MeV, lies outside the thermal
  window. The four of Starostov 1985 are one measurement in four parts, the first cycle with each of
  three detectors and the second cycle.
- `Pu239_nth_spectrum_cf252_ratio_vs_E` — the spectrum as a ratio to that of 252-Cf(sf): 40871009
  and 40871010 (Nefedov 1983) and 40872006 (Starostov 1983), 252-Cf over 239-Pu, and 416110041
  (Vorobyev 2016), 239-Pu over 252-Cf in arbitrary units, under `relative/`.
- `Pu239_nth_eps_vs_A` — mean centre-of-mass neutron energy against fragment mass, from 22650008
  (Tsuchiya 2000) and 41502009 (Batenkov 2004), the second headed `DATA` and in the centre of
  mass by its `REACTION` text. 22650008 carries a qualifier beginning `mean_threshold_unsettled:`.
- `Pu239_nth_P_vs_nu` — the multiplicity distribution P(ν): 12833008 (Gwin 1984), 30046009 (Boldeman
  1967), 30772011 (Boldeman 1985) and V0045013 (Holden 1988), an evaluation, written and carrying a
  qualifier beginning `evaluation:`. The subentry of 30046009 marks it superseded by 30772011; both
  are written, and 30046009 carries a qualifier beginning `superseded:`. Refused: 12337010 (Diven
  1956), at 80 keV.

### 240-Pu(sf)

240-Pu is the compound nucleus of 239-Pu(n_th,f), about 6.5 MeV lower in excitation energy when
it fissions spontaneously. These two stand in for what the archive lacks for 239-Pu(n_th,f).

- `Pu240_sf_sigma_TKE_vs_A` — the standard deviation of the pre-neutron TKE against heavy mass, from
  `22273023` (Schillebeeckx 1992,
  [doi:10.1016/0375-9474(92)90296-V](https://doi.org/10.1016/0375-9474(92)90296-V)), whose `MISC1`
  the entry calls "the dispersion, sigma, of the distribution". Digitised from a figure of the paper
  and scattering accordingly, it is written as it stands.
- `Pu240_sf_Y_vs_A_TKE` — the joint yield in raw event counts, `22413013` (Demattè 1997,
  [doi:10.1016/S0375-9474(97)00032-8](https://doi.org/10.1016/S0375-9474(97)00032-8)), 1-MeV TKE
  steps against heavy masses 120 to 160, under `relative/`; the record lists the TKE slices of
  Wagemans 1984 besides.

## Prompt γ-ray configurations

Twenty-two configurations retrieve the prompt-γ quantities of the four systems; see
[Prompt γ rays](@ref) for the observables and what each record states of a value's definition.

### 252-Cf(sf), prompt γ

- `Cf252_sf_M_gamma_bar` — the multiplicity per fission, 15 datasets: 23174004 (Skarsvåg 1970, above
  100 keV), admitted by name from the archive's listing under `MLT`, 14214009 (Pleasonton,
  ORNL-4844, 1972), the six detectors of 23197 (Oberstedt 2015, 0.1 MeV to 6.0 to 7.7 MeV, coded
  `PAR`) and their average 231970091, 237830031 (Gjestvang 2021, corrected by a factor 1.30 the
  entry gives), 23814003 (Krupa 2004), 415800031 (Sokol 1991, 0.32 to 5.12 MeV within 4 µs),
  14320003 and 14320004 (Smith 1956, the first over 0.5 to 2.3 MeV) and 143870061 (Bowman 1958).
  Refused: 234170041 (Qi 2018), two detectors in one table; the light and heavy groups of 14214; the
  K X-rays of 33071; the uncorrected 237830032 and 415800021. The totals Smith 1956 (8.2 MeV) and
  Sokol 1991 (9.6 MeV) state in MISC columns without an uncertainty are kept in reasons among the
  rejections of `Cf252_sf_E_gamma_tot`, and the mean photon energy of Krupa 2004 (0.83 MeV) among
  those of `Cf252_sf_eps_gamma`.
- `Cf252_sf_E_gamma_tot` — the total energy per fission, 12 datasets: 14214008, the six detectors of
  23197 and their average, 237830041, 23814004 and 143870062, the last two read on their magnitude
  alone, and 232130061 (Mehta 1973), read from its subentry.
- `Cf252_sf_eps_gamma` — the mean photon energy, 9 datasets: 14214029, the six detectors of 23197
  and their average, and 415800032 (Sokol 1991).
- `Cf252_sf_M_gamma_vs_A` — the multiplicity of one fragment against its pre-neutron mass:
  23814005 (Krupa 2004).
- `Cf252_sf_E_gamma_vs_A` — the γ energy of one fragment against its pre-neutron mass: 23814006
  (Krupa 2004), read from its subentry.
- `Cf252_sf_E_gamma_tot_vs_A` — the total energy per fission against the light-fragment mass:
  23213010 (Mehta 1973), read from its subentry.
- `Cf252_sf_M_gamma_bar_vs_A` — the multiplicity per fission against the pre-neutron mass of one
  fragment, over a partial γ-energy range: 22757003 (Hotzel 1996, 3.5 to 8 MeV) and 23857004 (Singer
  1997, 4 to 8 MeV), read from their code `PAR/PRE,FY,G`, 'Partial yield of fission gammas from
  both fragments' in Dictionary 236. Refused: 23857005, the same for ternary fission.
- `Cf252_sf_M_gamma_bar_vs_TKE` — the multiplicity per fission against TKE: 32788003 (Wang 2016).
- `Cf252_sf_E_gamma_tot_vs_TKE` — the total energy per fission against TKE: 23213018 (Mehta 1973).
- `Cf252_sf_E_gamma_tot_vs_nu` — the total energy per fission against the number of neutrons the
  fission emitted: 232130301 (Mehta 1973), the number read from its MISC column.

### 235-U(nth,f), prompt γ

- `U235_nth_M_gamma_bar` — 11 datasets: 14214005 (Pleasonton 1972, within ∼5 ns by its
  publication), the five detectors of 31729 (Oberstedt 2013, 0.1 to 6.0 MeV) and their average
  31729008, 232830021 (Pollitt 2015) and 23263002 (Murray 2014), both preliminary, 23541004 (Makii
  2019, 1 to 6 MeV) and 23659004 (Wright 2024, whose range is not coded). Refused: 14201003 (Peelle
  1971), two ranges in one table, and 14195002 (Verbinski 1973), tabulated in bins of γ energy.
- `U235_nth_E_gamma_tot` — 5 datasets: 14214004, 14735002 (Deutsch 1944, within 2 µs), 232830023,
  and the values stated outside the DATA tables by 31729001 (6.92 ± 0.09 MeV) and 23541005 (4.07 ±
  0.07 MeV over 1 to 6 MeV).
- `U235_nth_eps_gamma` — 10 datasets: 14214027, the five detectors of 31729 and their average,
  232830022, 23541005 and 23659003.
- `U235_nth_M_gamma_vs_A` — the multiplicity of one fragment against its pre-neutron mass:
  14197005 (Pleasonton 1972), whose row at A = 82, −0.36 ± 1.36, is written as given and noted.
- `U235_nth_M_gamma_bar_vs_A` — the multiplicity per fission against the heavy-fragment mass:
  14197003 (Pleasonton 1972).
- `U235_nth_eps_gamma_vs_A` — the mean photon energy against the heavy-fragment mass: 14197004
  (Pleasonton 1972), read from its subentry.

The entry 31729 was measured in a cold neutron beam whose temperature, 100 K, the csv rendering
gives as an incident energy of 100 eV; it is read as kT = 8.6 meV.

### 239-Pu(nth,f), prompt γ

- `Pu239_nth_M_gamma_bar` — 5 datasets: 14214007 (Pleasonton, ORNL-4844) and 317780061 to
  317780063 and 31778007 (Gatera 2017, three detectors and their summed spectrum, 0.1 to 7.0 MeV,
  recorded within a 300 ns acquisition window).
- `Pu239_nth_E_gamma_tot` — 5 datasets: 14214006 and the four totals Gatera 2017 states outside its
  DATA tables, 31778002 to 31778005.
- `Pu239_nth_eps_gamma` — 5 datasets: 14214028 and 317780081 to 317780083 and 31778009.

### 233-U(nth,f), prompt γ

- `U233_nth_M_gamma_bar`, `U233_nth_E_gamma_tot`, `U233_nth_eps_gamma` — one dataset each, from
  14214 (Pleasonton, ORNL-4844): 6.31 photons, 6.69 MeV and 1.06 MeV per photon, the values of
  Pleasonton 1973 (doi:10.1016/0375-9474(73)90161-9), which has no entry of its own.

## Spectra

A prompt fission neutron spectrum is conventionally measured relative and normalised afterwards,
so most of what the archive holds is in arbitrary units. Those datasets are retrieved and written
under `relative/`, apart from the absolute ones: each carries a shape and no scale, and none can
be put on a common scale with another.

Much of the published comparison of spectra is made as a ratio to a Maxwellian, which is a
separate observable from `spectrum`: the archive codes it with `MXD`, which `spectrum` excludes.
Being a ratio, it is dimensionless and carries its own normalisation, so it can be compared
between laboratories whose absolute spectra are reported in arbitrary units.

A ratio to a Maxwellian states no spectrum without the temperature T of the Maxwellian
√E exp(−E/T) it was formed with, so every such dataset must give it, in `KT-NRM` of its subentry,
of subentry 001 or of its DATA table; a dataset that gives none is refused. The run record states
it per dataset as `maxwellian_temperature_mev`. Every dataset of the four shipped configurations
gives it.

The ratio to the spectrum of 252-Cf(sf), `spectrum_cf252_ratio`, is the one observable read from
the ratio of two reaction codes, and is tabulated against `["neutron_energy"]` alone; the loader
refuses any other abscissa and refuses it for 252-Cf(sf) itself. The archive gives it in both
orientations, and each dataset is written as tabulated, its orientation in the run record. The
ratios coded `MSC`, those outside the thermal window — `23444002` at 580 eV, `31692006` at
100 eV, `411100091` at 2.9 to 14.7 MeV — and the ratios of 239-Pu to 235-U, `14290004` and
`14418002`, are refused.

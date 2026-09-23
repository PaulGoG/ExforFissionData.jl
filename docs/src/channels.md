```@meta
CurrentModule = ExforFissionData
```

# Entrance channels

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

## Window rule

A system is an element symbol, a mass number and an **entrance channel** — `sf` spontaneous, `nth`
thermal-neutron-induced, `nres` resonance-region, `nfast` fast. The channel decides the EXFOR
reaction code, so the configuration names the channel and never the code: the two can disagree
only if both are written down. The window that selects datasets is `energy_min` and
`energy_max`; it defaults to the channel's interval in the table above and is refused outside it,
so that a thermal directory cannot hold a fast measurement. The bounds follow from the physics
set out above.

## Spectrum qualifiers

A spectrum qualifier in the reaction code can contradict the channel, and a dataset carrying one
is rejected: `FST`, `FIS` and `EPI` under `nth`; `MXW`, `FST` and `FIS` under `nres`; `EPI`
under `nfast` ([`CHANNEL_FORBIDDEN_QUALIFIERS`](@ref)). The archive files a spectrum-averaged
measurement under a dummy incident energy, so the window cannot catch it: `326650021`, ²³⁵U
independent yields under `,,FIS` from a fission-spectrum irradiation, is declared at 0.0253 eV
and would pass a thermal window on its energy alone. `SPA` names an unspecified spectrum and is
admitted everywhere; `MXW` is admitted under `nfast`, where it denotes a fission-Maxwellian
average.

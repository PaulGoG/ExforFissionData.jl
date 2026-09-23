```@meta
CurrentModule = ExforFissionData
```

# Conventions and selection

**Energies are restated in MeV** — both an energy abscissa and an ordinate that is itself an
energy. These are exact conversions of a value with the factor recorded in the run record, which
is a different thing from a normalisation.

**Values carry seven significant digits**, set by `significant_digits` under `[output]`.
Significant digits rather than decimal places, because the ordinates span many orders of
magnitude: an absolute prompt fission neutron spectrum is of order 10⁻⁷ PC/FIS/MEV, which seven
decimal places would reduce to one significant digit and eight would erase.

**No normalisation is applied to ordinates.** Normalisation conventions differ between consumers
and cannot be undone once applied, so the unit token of each dataset is recorded in the run record
instead. A query returning more than one unit token is flagged: such datasets must not be
renormalised together.

**No point is dropped on the basis of its value or uncertainty.** Quality cuts belong with the
project that can justify them. Values in the far-asymmetric mass tails are statistically poor and
are written unchanged, with their uncertainties.

**The uncertainty column is omitted** when no row of a dataset carries one, rather than written
as a column of zeros.

**One row per abscissa value.** Several things put more than one row on an abscissa value, and
they are not handled alike:

| Cause | Treatment |
| :--- | :--- |
| several incident energies | the configured window selects rows; a dataset still holding more than one energy inside it is rejected, naming them, rather than averaged |
| another independent variable of the subentry DATA table — a kinetic-energy gate, an angle | rejected where the variable varies: a mean over gates is not the observable asked for. One held at a single value is a condition of the measurement and passes |
| isomeric states | the archive's own total where it gives one, otherwise the resolved states summed with uncertainties in quadrature |
| anything left | inverse-variance weighted mean, uncertainty `1/√(Σ1/σ²)`, counted per dataset as `abscissae_combined` and named in a warning |

The abscissa and the test for other variables come from the **subentry DATA table**, not from the
`op=csv` rendering. The rendering reports a mass as an integer by truncation, 63.51 and 64.91 as
63 and 64, and drops the independent variables it does not recognise; it still supplies the
ordinate, its uncertainty, the unit and the incident energy. The two are aligned row by row, the
truncated product against the subentry's `MASS` and `ELEM` and the secondary energy against its
`E` or `TKE`, and a dataset on which they disagree is rejected. A mass is rounded to the nearest
integer with ties up, since ties to even would put a 1-u grid centred on half-integers, 80.5,
81.5 and 82.5, on 80, 82 and 82; the run record gives per dataset how many masses were
non-integer, `mass_values_non_integer`, and the largest distance rounding moved one,
`mass_rounding_max`. A bin given as a `-MIN`, `-MAX` pair contributes its midpoint, recorded as
`abscissa_binned`.

Rows that still share an abscissa value are either genuine repetition — a chain yield measured
through several nuclides of one mass — or one measurement under different auxiliary conditions.
They are combined, and `combined_over` in the run record names the auxiliary columns of the
subentry, a flight path or a flag, that varied among them. The subentry stored beside the data is
the reference.

## Selection

Datasets are chosen by substring tests over the EXFOR reaction code — for instance
`92-U-233(N,F)ELEM/MASS,CUM,FY`. The archive applies its own vocabulary inconsistently, so the
tables in `src/reaction_codes.jl` are empirical: they encode observed failures of the upstream
labelling rather than a formal grammar. A rule that looks redundant usually guards a real entry.

The checks easiest to get wrong:

- the `y:Value` column marks **upper limits** with a `Max(` prefix; those rows are bounds, not
  measurements;
- it also marks **arbitrary units** as `ARB-UNITS`, which carry no scale and cannot be combined
  with absolute data;
- the incident-energy window is applied **per row**, not to the dataset as a whole. An EXFOR
  dataset frequently reports one product at several energies, and admitting all of them collapses
  an excitation function into a single number;
- what a dataset is tabulated against is read from its **subentry DATA table**, which is
  aligned with the csv rendering row by row — the truncated product against `MASS` and `ELEM`,
  the secondary energy against `E` or `TKE` — and a dataset on which the two disagree is
  rejected;
- a heading of the subentry DATA table that the EXFOR format classes as an independent variable,
  other than the abscissa's own and the incident energy, **must not vary**. `23591005` (Straede,
  1987) is a mass yield at nine fragment kinetic energies, and projected onto mass it is nine
  yields per mass number. `23268002`, whose `TKE` column the csv rendering drops, is rejected from
  `Cf252_sf_Y_vs_A` on the same rule;
- a spectrum whose energies are in the centre-of-mass frame, `E-CM`, is not a laboratory
  spectrum and is rejected;
- the quantity code `FY` files more than yields. `MASS,PAR,ZP` is the most probable charge against
  mass, which satisfies every mass rule, so `yield` requires the `FY` tag itself: six such
  datasets for 235-U would otherwise sit among the mass yields at values near 40.

Reaction-code qualifiers that bear on a value's scale — `MSC`, `REL`, `CHN`, `DERIV`, `FCT` — are
recorded per dataset without rejecting it, and so are those naming the inducing neutron spectrum,
except that a spectrum no measurement of the channel can have been made in rejects the dataset;
see [Entrance channels](channels.md).

## Known miscoded entries

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
`ordinate = "multiplicity_per_fission"` accepts them as pair data, which they are not: for 252-Cf
a pair multiplicity is about 3.76 everywhere, and `23118006` reports 0.56 at A = 80. The tag rules
are not loosened to admit them, since `MASS,PR,NU` is the correct code for genuine pair data and
admitting it would mix the two quantities. Both appear in the rejection list of the run record
with their reaction codes.

Only the one-dimensional projections are affected. The same Göök entry compiles the joint
distribution correctly as `23268008`, `MASS,PR/FRG,NU/TKE`, which
`abscissa = ["mass", "total_kinetic_energy"]` retrieves in full — 2234 points of ν(A, TKE). A
consumer that wants ν(A) from this measurement should take the joint distribution and marginalise
it rather than reach for the miscoded projection.

One is known for `ordinate = "yield"`, and it is the rendering that misstates it. `23268002`
(Göök, 2014), `98-CF-252(0,F)MASS,PRE,FY,,MSC`, is the joint distribution Y(A, TKE): 30 000 rows
of counts on a 150 × 200 grid, which its subentry heads `TKE`, `MASS`, `DATA` in `ARB-UNITS`. The
`op=csv` rendering drops the TKE column and gives the unit as `PART/FIS`. The subentry shows the
column, and `Cf252_sf_Y_vs_A` rejects the dataset as also tabulated against
`TKE [MEV] (200 values)`.

One more is known for `ordinate = "spectrum"`, and it is a mislabelled unit rather than a
mislabelled quantity. `40064031` (Kroshkin, 1970), `98-CF-252(0,F),PR,NU/DE,,REL`, heads its
energy column `MEV` over values running from 5.128 to 2132.8. The subentry contradicts itself:
its own `REACTION` text gives the range as "5 keV - 2 MeV", and its comment places the structure
it reports at 85 keV to 0.75 MeV. The column is keV. The dataset is retrieved and written as the
archive states it, since a unit token is not something this package overrules, but its abscissa is
a factor of 1000 too large and it is the one dataset in `Cf252_sf/spectrum_vs_E` reaching past
40 MeV — a sanity check on the abscissa range finds it immediately.

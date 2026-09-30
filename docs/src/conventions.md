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
as a column of zeros. Where the csv rendering carries no uncertainty at all but the subentry does,
in `DATA-ERR`, `ERR-T` or `ERR-S` in that order, it is read from the subentry and put on the scale
of the csv ordinate; `uncertainty_source` in the run record says which (`23268002` gives `ERR-S`
on each of its 30 000 cells, and the rendering on none).

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
`E` or `TKE`, and a dataset on which they disagree is rejected.

Masses are written as integers and are never rounded to become so; `mass_treatment` in the run
record says which of three cases applied.

- **Integer masses** are written as the subentry gives them.
- **A bin with integer edges**, `MASS-MIN` to `MASS-MAX` such as 126–127, holds each integer mass
  from one edge to the other. The value of a mean — a kinetic energy, a multiplicity — holds for
  every mass of its bin and is written at each with its own uncertainty, which the repetition
  does not reduce; the widths are recorded as `mass_bin_widths_u`. A yield over several masses is
  their sum and holds for none of them, so it is not written (`10865003` gives the yield of
  masses 135 and 136 together). Bins that share or split an edge mass leave open which bin it
  belongs to and are not placed.
- **Non-integer masses** — a digitised curve, a half-integer grid — are interpolated linearly onto
  the integer masses within their range, separately at each value of any other abscissa quantity.
  The uncertainty is interpolated like the value, as for fully correlated neighbours, so an
  interpolated point is never more precise than the two it lies between. Nothing is interpolated
  across more than `mass_interpolation_span_u` = 3 u: measured tabulations sample the mass at
  up to 2.5 u, and a wider interval is a gap in the measurement, such as the unmeasured
  symmetric region between two branches. The integer masses in such gaps are counted as
  `mass_gaps_skipped`.

Energies from a `-MIN`, `-MAX` pair contribute the midpoint of the bin, recorded as
`abscissa_binned`.

Rows that still share an abscissa value are either genuine repetition — a chain yield measured
through several nuclides of one mass — or one measurement under different auxiliary conditions.
They are combined, and `combined_over` in the run record names the auxiliary columns of the
subentry, a flight path or a flag, that varied among them. The subentry stored beside the data is
the reference.

## Selection

Datasets are chosen by the codes of their EXFOR reaction code — for instance
`92-U-233(N,F)ELEM/MASS,CUM,FY`. The code is read into its subfields, product (SF4), branch
(SF5), parameter (SF6), particle (SF7), modifier (SF8) and data type (SF9), each split at its
`/` separators, and every test compares a whole code in a named subfield: `DE`, the energy
differential of SF6, is never read inside the data type `DERIV`, nor `KE` inside `KEP`, the most
probable value, or inside `TKE`. `AKE`, the older coding of the mean kinetic energy, is accepted
wherever `KE` is. A combination of several reactions — a ratio, sum or difference — is never the
quantity itself and is rejected. Which codes each observable requires and forbids is still
empirical, since the archive applies its own vocabulary inconsistently: the tables in
`src/reaction_codes.jl` encode observed failures of the upstream labelling. A rule that looks
redundant usually guards a real entry.

Where no code can tell two datasets apart, a dataset is read from its subentry text one at a time
(`src/curation.jl`), and the run record carries the evidence as `curation`. An observable against
pre-neutron mass takes only pre-neutron masses: an entry that states its masses were not
corrected for neutron emission has every dataset against such a mass rejected, with the
subentry that states it as the reason — entries 40232 and 40420 (Zakharova 1973 and 1979), whose
ν(A) and ν(A, TKE) share that mass determination. A blank branch field
is decided kinematically: a double-velocity measurement gives pre-neutron masses and energies
directly, since isotropic neutron emission leaves the mean fragment velocity unchanged, while a
double-energy measurement gives provisional masses until they are corrected with ν(A), and is
admitted only where its entry states that correction.

The checks easiest to get wrong:

- the `y:Value` column marks **upper limits** with a `Max(` prefix; those rows are bounds, not
  measurements;
- it also marks **arbitrary units** as `ARB-UNITS`, which carry no scale and cannot be combined
  with absolute data. The subentry's own unit decides where the two differ: `23268002` is counts
  in `ARB-UNITS` in its subentry and `PART/FIS` in the rendering;
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
  datasets for 235-U would otherwise sit among the mass yields at values near 40;
- a yield against the pre-neutron mass must carry the pre-neutron branch `PRE`, and the chain
  yield `CHN` and the provisional yield `PRV` are refused beside it. A chain yield is a
  post-neutron product mass, and a provisional mass is one derived from the two fragment energies
  without correcting them for neutron emission; before the rule the `Y_vs_A` retrievals of the
  four systems carried 69 chain and 5 provisional yields beside 51 pre-neutron ones. A
  multiplicity against mass, `MASS,PR/FRG,NU`, carries no branch and is not affected.

Reaction-code qualifiers that bear on a value's scale — `MSC`, `REL`, `CHN`, `DERIV`, `FCT` — are
recorded per dataset without rejecting it where the observable admits them, and so are those naming the inducing neutron spectrum,
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
of counts on a 150 × 200 grid, which its subentry heads `TKE`, `MASS`, `DATA` and `ERR-S` in
`ARB-UNITS`. Its code names no TKE, and the `op=csv` rendering drops the TKE and ERR-S columns
and gives the unit as `PART/FIS`. It is read from its subentry (`src/curation.jl`): retrieved by
`Cf252_sf_Y_vs_A_TKE` in counts, under `relative/`, with its uncertainties, and rejected by
`Cf252_sf_Y_vs_A` as the joint distribution it is.

One more is known for `ordinate = "spectrum"`, and it is a mislabelled unit rather than a
mislabelled quantity. `40064031` (Kroshkin, 1970), `98-CF-252(0,F),PR,NU/DE,,REL`, heads its
energy column `MEV` over values running from 5.128 to 2132.8. The subentry contradicts itself:
its own `REACTION` text gives the range as "5 keV - 2 MeV", and its comment places the structure
it reports at 85 keV to 0.75 MeV. The column is keV. The dataset is retrieved and written as the
archive states it, since a unit token is not something this package overrules, but its abscissa is
a factor of 1000 too large and it is the one dataset in `Cf252_sf/spectrum_vs_E` reaching past
40 MeV — a sanity check on the abscissa range finds it immediately.

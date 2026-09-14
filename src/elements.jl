# Element symbols.
#
# The configuration names the fissioning target by its charge and mass numbers, which identify a
# nuclide unambiguously, and the EXFOR nuclide symbol is formed from them here. A symbol written
# into a configuration could disagree with the numbers beside it; one derived from them cannot.

"""
Chemical symbols indexed by atomic number, Z = 1 to 118.

Written as one string in periodic-table order, ten to a row, because a table that can be read
across is a table whose entries can be checked; indexing by Z is what the code needs and is what
splitting it gives.
"""
const ELEMENT_SYMBOLS = Tuple(String.(split("H  He Li Be B  C  N  O  F  Ne \
             Na Mg Al Si P  S  Cl Ar K  Ca \
             Sc Ti V  Cr Mn Fe Co Ni Cu Zn \
             Ga Ge As Se Br Kr Rb Sr Y  Zr \
             Nb Mo Tc Ru Rh Pd Ag Cd In Sn \
             Sb Te I  Xe Cs Ba La Ce Pr Nd \
             Pm Sm Eu Gd Tb Dy Ho Er Tm Yb \
             Lu Hf Ta W  Re Os Ir Pt Au Hg \
             Tl Pb Bi Po At Rn Fr Ra Ac Th \
             Pa U  Np Pu Am Cm Bk Cf Es Fm \
             Md No Lr Rf Db Sg Bh Hs Mt Ds \
             Rg Cn Nh Fl Mc Lv Ts Og")))

"""Largest atomic number [`ELEMENT_SYMBOLS`](@ref) covers."""
const MAXIMUM_CHARGE = length(ELEMENT_SYMBOLS)

"""
    element_symbol(Z) -> String

The chemical symbol of the element of atomic number `Z`.

Throws an `ArgumentError` outside 1 to $(MAXIMUM_CHARGE).

# Example

```jldoctest
julia> element_symbol(98)
"Cf"
```
"""
function element_symbol(Z::Integer)
    1 ≤ Z ≤ MAXIMUM_CHARGE || throw(
        ArgumentError(
            "atomic number $(Z) lies outside 1 to $(MAXIMUM_CHARGE), for which a chemical \
             symbol is defined",
        ),
    )
    return ELEMENT_SYMBOLS[Z]
end

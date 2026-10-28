# Complement test of prompt-neutron multiplicities tabulated against fragment mass.
#
#     julia scripts/complement_test.jl <output-directory>
#
# Decides whether a dataset coded MASS,PR,NU (no FRG) holds the multiplicity of one fragment,
# ν(A), or of the fragment pair, ν_pair against one fragment's mass, from the data alone (rule of
# v0.2.2). Two forms:
#
#   internal  sets with both halves, i.e. pairs (A, A₀ − A) spanning at least COVERAGE_MIN of the
#             light-fragment yield. S = ν(A_L) + ν(A_H) averaged with the light-fragment yield:
#             per fragment ⇔ |S/ν̄ − 1| ≤ FRAGMENT_BAND and D = ν(A_L) − ν(A_H) ≡ 0 rejected
#                            (D changes sign, χ²_D/n beyond 1 + 3√(2/n); without σ, a runs test
#                            on the signs of D at the same 3σ level);
#             per fission  ⇔ |S/ν̄ − 2| ≤ FISSION_BAND and D ≡ 0 holds.
#             The bands are a quarter of the gap between the readings, so the classification
#             never hinges on the scale. S itself is ν_pair(A), which varies with the mass split;
#             only its yield-weighted mean is ν̄.
#   sibling   one-sided and joint sets, against a per-fragment dataset (FRG) of the same entry or,
#             for joint sets, a 1-D ν(A) at ⟨TKE⟩(A) or another experiment's joint ν(A, TKE):
#             per fragment ⇒ ν(A) = ν_FRG(A);
#             per fission  ⇒ ν(A) = ν_FRG(A) + ν_FRG(A₀ − A);
#             one reading must fit SIBLING_FACTOR times better (χ² where stated, else rms), and
#             all comparisons of a set must agree.
#
# Anything else is undecided. The scale is recorded, never a gate: pair_sum_deviation = S/(kν̄) − 1
# with k = 1 per fragment and 2 per fission, its uncertainty, and scale_consistent = |dev| ≤ 3σ,
# unset where no uncertainty is tabulated. The yields are the experiment's own where its entry
# has a pre-neutron Y(A), else the system fallback.
#
# A complement is taken at a tabulated mass or interpolated linearly between neighbours at most
# MAX_SPAN apart. Yields for the weighting are one accepted Y(A) per system, read from a
# retrieval tree. ν̄ is the total average neutron yield of the IAEA Neutron Data Standards 2017
# (Carlson et al., Nucl. Data Sheets 148, 143 (2018), doi:10.1016/j.nds.2018.02.002, Table 11);
# the delayed part, at most 0.7 % of it, is below the resolution of the test.
#
# Subentry texts are read through the package client and its response cache.

include(joinpath(@__DIR__, "..", "activate.jl"))

using ExforFissionData: RetrievalOptions
using ExforFissionData
using Printf, Statistics

const X = ExforFissionData
const MAX_SPAN = 4.0
const TREE = joinpath(dirname(@__DIR__), "data")

# Decision constants of the v0.2.2 rule.
const COVERAGE_MIN = 0.9
const FRAGMENT_BAND = 0.25
const FISSION_BAND = 0.5
const SIGNIFICANCE = 3.0
const RUNS_P = 0.0027   # two-sided 3σ
const SIBLING_FACTOR = 2.0

# Fallback yields per system, by dataset identifier: Göök 2014 for Cf, Geltenbort 1985 otherwise.
const SYSTEMS = Dict(
    "Cf252_sf" => (A₀ = 252, ν̄ = 3.764, σν̄ = 0.016, yields = "23268003"),
    "U235_nth" => (A₀ = 236, ν̄ = 2.425, σν̄ = 0.011, yields = "21981006"),
    "Pu239_nth" => (A₀ = 240, ν̄ = 2.878, σν̄ = 0.013, yields = "21981007"),
    "U233_nth" => (A₀ = 234, ν̄ = 2.487, σν̄ = 0.011, yields = "21981005"),
)

# (system, candidate, per-fragment siblings of the same entry)
const CANDIDATES = [
    ("Cf252_sf", "14387005", String[]),
    ("Cf252_sf", "14652004", String[]),
    ("Cf252_sf", "23118006", String[]),
    ("Cf252_sf", "23175008", String[]),
    ("Cf252_sf", "23213012", ["23213014"]),
    ("Cf252_sf", "23268005", String[]),
    ("Cf252_sf", "404200022", String[]),
    ("Cf252_sf", "41689004", String[]),
    ("Cf252_sf", "41720003", ["41720002"]),
    ("Pu239_nth", "22650004", String[]),
    ("Pu239_nth", "23012007", ["23012008"]),
    ("Pu239_nth", "41397003", ["41397002"]),
    ("Pu239_nth", "41502006", String[]),
    ("Pu239_nth", "41502007", String[]),
    ("Pu239_nth", "41674002", String[]),
    ("Pu239_nth", "41694004", ["41694003"]),
    ("Pu239_nth", "41720005", ["41720004"]),
    ("U233_nth", "22660006", ["22660005"]),
    ("U233_nth", "41397006", ["41397004"]),
    ("U233_nth", "41674003", String[]),
    ("U235_nth", "21095003", ["21095002", "21095004"]),
    ("U235_nth", "21095005", ["21095002", "21095004"]),
    ("U235_nth", "21834009", String[]),
    ("U235_nth", "21834010", String[]),
    ("U235_nth", "22464005", ["22464004"]),
    ("U235_nth", "41397007", ["41397005"]),
    ("U235_nth", "41502005", String[]),
    ("U235_nth", "41516013", ["41516012"]),
    ("U235_nth", "41673002", String[]),
    # joint ν(A, TKE)
    ("Cf252_sf", "14838002", String[]),
    ("Cf252_sf", "23118007", String[]),
    ("Cf252_sf", "23175010", String[]),
    ("Cf252_sf", "23268007", ["23268008"]),
    ("Cf252_sf", "40420003", String[]),
    ("Cf252_sf", "41712005", String[]),
    ("U233_nth", "22660009", ["22660008"]),
    ("U235_nth", "22464009", ["22464007"]),
]

# ν̄ at a fast incident energy, ENDF/B-VIII.0 235U MF1/MT452 (Brown et al., Nucl. Data Sheets
# 148, 1 (2018), doi:10.1016/j.nds.2018.02.001): 0.5 MeV for 21834009, 5.55 MeV for 21834010.
const FAST_NUBAR = Dict("21834009" => 2.4836, "21834010" => 3.1411)

# The pre-neutron Y(A) of the same experiment, where its entry has one, for the yield weighting:
# read from the retrieval tree when accepted there, else from its subentry (21834002/3 lie at
# 0.5 and 5.55 MeV, outside every shipped window). Entries 14652 (Y(A) post-neutron only), 41502,
# 41689 and 41712 have none.
const OWN_YIELDS = Dict(
    "23268005" => "23268003",
    "23118006" => "23118002",
    "23175008" => "23175002",
    "22650004" => "22650002",
    "23012007" => "23012004",
    "21834009" => "21834002",
    "21834010" => "21834003",
)

# Joint sets without a joint per-fragment sibling: compared at TKE = ⟨TKE⟩(A) with a
# one-dimensional per-fragment ν(A). With ν linear in TKE, the mean of ν(A, TKE) over the TKE
# distribution at fixed A is ν(A, ⟨TKE⟩(A)). (ν(A) datasets, ⟨TKE⟩(A) file under TKE_vs_A)
const MEAN_TKE_CHECKS = Dict(
    "23175010" => (["23175008"], "23175003_C.Budtz-jorgensen_1988.dat"),
    "23118007" => (["23118006"], "23268004_A.Goeoek_2014.dat"),
    "41712005" => (["41712002"], "41712003_I.D.Alkhazov_1988.dat"),
    "14838002" => (["23268005"], "23268004_A.Goeoek_2014.dat"),
)

# Joint sets compared cell by cell with the joint per-fragment ν(A, TKE) of another experiment.
const EXTERNAL_SIBLINGS = Dict("14838002" => ["23268008"], "23118007" => ["23268008"])

# Largest TKE interval bridged when complements of joint data lie on different TKE grids, MeV.
const TKE_SPAN = 6.0

"""One tabulated point: mass, TKE (NaN for one-dimensional data), ν, σ (NaN when absent)."""
const Point = NamedTuple{(:A, :TKE, :ν, :σ), NTuple{4, Float64}}

function _centre(data, single, low, high, i)
    c = X.column(data, single)
    c === nothing || return coalesce(data.values[c][i], NaN)
    l, h = X.column(data, low), X.column(data, high)
    (l === nothing || h === nothing) && return NaN
    a, b = data.values[l][i], data.values[h][i]
    (ismissing(a) || ismissing(b)) && return NaN
    return (a + b) / 2
end

function points(identifier, options)
    text = X.subentry_text(identifier, options).body
    data = X.parse_subentry(text, identifier).data
    d = X.column(data, "DATA")
    e = something(
        X.column(data, "DATA-ERR"),
        X.column(data, "ERR-S"),
        X.column(data, "+DATA-ERR"),
        Some(nothing),
    )
    tke_heading = X.column(data, "TKE") !== nothing ? "TKE" : "E"
    found = Point[]
    for i in 1:X.line_count(data)
        A = _centre(data, "MASS", "MASS-MIN", "MASS-MAX", i)
        T = _centre(data, tke_heading, "TKE-MIN", "TKE-MAX", i)
        ν = coalesce(data.values[d][i], NaN)
        σ = e === nothing ? NaN : coalesce(data.values[e][i], NaN)
        (isnan(A) || isnan(ν)) && continue
        push!(found, (A = A, TKE = T, ν = ν, σ = σ))
    end
    return found, text
end

# ν at mass `a` and TKE `t` (NaN for 1-D) from `pts`: tabulated, or linear between neighbours at
# most MAX_SPAN apart in mass and TKE_SPAN apart in TKE.
function _along(row, x, key, span)
    sort!(row; by = p -> getfield(p, key))
    exact = findfirst(p -> abs(getfield(p, key) - x) < 1.0e-6, row)
    exact === nothing || return (ν = row[exact].ν, σ = row[exact].σ)
    i = findfirst(p -> getfield(p, key) > x, row)
    (i === nothing || i == 1) && return nothing
    l, h = row[i - 1], row[i]
    getfield(h, key) - getfield(l, key) > span && return nothing
    w = (x - getfield(l, key)) / (getfield(h, key) - getfield(l, key))
    return (ν = l.ν + w * (h.ν - l.ν), σ = l.σ + w * (h.σ - l.σ))
end

function at(pts::Vector{Point}, a, t)
    isnan(t) && return _along(filter(p -> isnan(p.TKE), pts), a, :A, MAX_SPAN)
    masses = sort!(unique(p.A for p in pts if !isnan(p.TKE)))
    curve(m) = _along(filter(p -> p.A == m && !isnan(p.TKE), pts), t, :TKE, TKE_SPAN)
    exact = findfirst(m -> abs(m - a) < 1.0e-6, masses)
    exact === nothing || return curve(masses[exact])
    i = findfirst(>(a), masses)
    (i === nothing || i == 1) && return nothing
    masses[i] - masses[i - 1] > MAX_SPAN && return nothing
    l, h = curve(masses[i - 1]), curve(masses[i])
    (l === nothing || h === nothing) && return nothing
    w = (a - masses[i - 1]) / (masses[i] - masses[i - 1])
    return (ν = l.ν + w * (h.ν - l.ν), σ = l.σ + w * (h.σ - l.σ))
end

# A pre-neutron Y(A) as mass => yield, from the retrieval tree or, failing that, the subentry.
function reference_yield(system, identifier, options)
    directory = joinpath(TREE, system, "Y_vs_A")
    names = filter(n -> startswith(n, identifier * "_"), readdir(directory))
    table = Dict{Float64, Float64}()
    if !isempty(names)
        for line in Iterators.drop(eachline(joinpath(directory, only(names))), 1)
            f = split(line)
            table[parse(Float64, f[1])] = parse(Float64, f[2])
        end
    else
        for p in first(points(identifier, options))
            table[p.A] = p.ν
        end
    end
    return table
end

# The light-fragment yield: the light side where tabulated, else Y_H(A₀ − A), which equals it
# for pre-neutron masses.
function light_yield(Y, A₀)
    light = Dict(a => v for (a, v) in Y if a < A₀ / 2)
    for (a, v) in Y
        a > A₀ / 2 && !haskey(light, A₀ - a) && (light[A₀ - a] = v)
    end
    return light
end

function yield_at(Y, a)
    haskey(Y, round(a)) || return 0.0
    abs(a - round(a)) < 1.0e-6 && return Y[round(a)]
    lo, hi = floor(a), ceil(a)
    return get(Y, lo, 0.0) * (hi - a) + get(Y, hi, 0.0) * (a - lo)
end

function level(pts, Y)
    one = filter(p -> isnan(p.TKE), pts)
    isempty(one) && return NaN
    w = [yield_at(Y, p.A) for p in one]
    return sum(w) > 0 ? sum(w .* [p.ν for p in one]) / sum(w) : NaN
end

# Exact P(R ≤ r) of the Wald–Wolfowitz runs test for n₁ and n₂ signs in random order.
function runs_probability(r, n₁, n₂)
    (n₁ == 0 || n₂ == 0) && return 1.0
    ways(R) =
        iseven(R) ? 2 * binomial(n₁ - 1, R ÷ 2 - 1) * binomial(n₂ - 1, R ÷ 2 - 1) :
        binomial(n₁ - 1, R ÷ 2) * binomial(n₂ - 1, R ÷ 2 - 1) +
        binomial(n₁ - 1, R ÷ 2 - 1) * binomial(n₂ - 1, R ÷ 2)
    return sum(big(ways(R)) for R in 2:r) / binomial(big(n₁ + n₂), n₁) |> Float64
end

function internal(pts, A₀, Y)
    Y = light_yield(Y, A₀)
    pairs = []
    for p in pts
        p.A < A₀ / 2 - 1.0e-6 || continue
        h = at(pts, A₀ - p.A, p.TKE)
        h === nothing && continue
        push!(pairs, (A = p.A, T = p.TKE, νL = p.ν, νH = h.ν, σL = p.σ, σH = h.σ))
    end
    isempty(pairs) && return nothing
    D = [q.νL - q.νH for q in pairs]
    S = [q.νL + q.νH for q in pairs]
    σD = [hypot(q.σL, q.σH) for q in pairs]
    z = filter(isfinite, abs.(D) ./ σD)
    w = [yield_at(Y, q.A) for q in pairs]
    one_dimensional = all(q -> isnan(q.T), pairs)
    lo, hi = extrema(q.A for q in pairs)
    spanned = sum(v for (a, v) in Y if lo - 0.5 ≤ a ≤ hi + 0.5; init = 0.0)
    light_total = sum(v for (a, v) in Y if a < A₀ / 2; init = 0.0)
    weighted = one_dimensional && sum(w) > 0
    # Signs of D in mass order (1-D) and their runs; zeros carry no sign.
    signs =
        [sign(q.νL - q.νH) for q in sort(pairs; by = q -> q.A) if abs(q.νL - q.νH) > 1.0e-9]
    runs = isempty(signs) ? 0 : 1 + count(i -> signs[i] != signs[i - 1], 2:length(signs))
    return (
        n = length(pairs),
        max_D = maximum(abs.(D)),
        rms_D = sqrt(mean(D .^ 2)),
        median_z = isempty(z) ? NaN : median(z),
        chi2_D = isempty(z) ? NaN : mean(z .^ 2),
        positive = count(>(1.0e-9), D),
        negative = count(<(-1.0e-9), D),
        zero = count(d -> abs(d) ≤ 1.0e-9, D),
        S_weighted = weighted ? sum(w .* S) / sum(w) : NaN,
        σS_weighted = weighted && any(isfinite, σD) ?
                      sqrt(sum(x -> isfinite(x) ? x : 0.0, (w .* σD) .^ 2)) /
                      sum(w[isfinite.(σD)]) : NaN,
        σ_pairs = count(isfinite, σD),
        coverage = one_dimensional && light_total > 0 ? spanned / light_total : NaN,
        S_min = minimum(S),
        S_max = maximum(S),
        runs = runs,
        runs_p = one_dimensional ?
                 runs_probability(runs, count(>(0), signs), count(<(0), signs)) : NaN,
    )
end

# Whether D ≡ 0 holds (:holds), is rejected with a change of sign (:rejected), or neither: χ²
# over the pairs with a stated uncertainty, else the runs test on the signs of D.
function zero_difference(t)
    n = t.σ_pairs
    if n > 0
        limit = 1 + SIGNIFICANCE * sqrt(2 / n)
        t.chi2_D ≤ limit && return :holds
        return t.positive > 0 && t.negative > 0 ? :rejected : :neither
    end
    t.max_D ≤ 1.0e-9 && return :holds
    return t.positive > 0 && t.negative > 0 && t.runs_p < RUNS_P ? :rejected : :neither
end

# The internal reading of a set with both halves, or `nothing` when it has not both halves.
function internal_reading(t, ν̄)
    (t === nothing || !(isfinite(t.coverage) && t.coverage ≥ COVERAGE_MIN)) &&
        return nothing
    r = t.S_weighted / ν̄
    z = zero_difference(t)
    abs(r - 1) ≤ FRAGMENT_BAND && z == :rejected && return :per_fragment
    abs(r - 2) ≤ FISSION_BAND && z == :holds && return :per_fission
    return :undecided
end

# One sibling comparison: χ² when both are finite, else rms.
function sibling_verdict(fragment_χ², pair_χ², fragment_rms, pair_rms)
    f, p =
        isfinite(fragment_χ²) && isfinite(pair_χ²) ? (fragment_χ², pair_χ²) :
        (fragment_rms, pair_rms)
    (isfinite(f) && isfinite(p)) || return nothing
    SIBLING_FACTOR * f ≤ p && return :per_fragment
    SIBLING_FACTOR * p ≤ f && return :per_fission
    return :undecided
end

# The scale of a set read from its pair sum: S/(kν̄) − 1 and its uncertainty (NaN without one).
function pair_sum_scale(t, reading, ν̄, σν̄)
    k = reading == :per_fission ? 2 : 1
    ratio = t.S_weighted / (k * ν̄)
    σ = ratio * hypot(t.σS_weighted / t.S_weighted, σν̄ / ν̄)
    return (
        deviation = ratio - 1,
        σ = σ,
        consistent = isfinite(σ) ? abs(ratio - 1) ≤ SIGNIFICANCE * σ : missing,
    )
end

function sibling_test(pts, sib, A₀)
    fragment = Float64[]
    pair = Float64[]
    zf = Float64[]
    zp = Float64[]
    for p in pts
        own = at(sib, p.A, p.TKE)
        other = at(sib, A₀ - p.A, p.TKE)
        (own === nothing || other === nothing) && continue
        push!(fragment, p.ν - own.ν)
        push!(pair, p.ν - (own.ν + other.ν))
        σf = hypot(p.σ, own.σ)
        σp = sqrt(p.σ^2 + own.σ^2 + other.σ^2)
        isfinite(σf) && σf > 0 && push!(zf, (fragment[end] / σf)^2)
        isfinite(σp) && σp > 0 && push!(zp, (pair[end] / σp)^2)
    end
    isempty(fragment) && return nothing
    return (
        n = length(fragment),
        rms_fragment = sqrt(mean(fragment .^ 2)),
        rms_pair = sqrt(mean(pair .^ 2)),
        chi2_fragment = isempty(zf) ? NaN : mean(zf),
        chi2_pair = isempty(zp) ? NaN : mean(zp),
    )
end

function mean_tke(system, name)
    pts = Point[]
    for line in Iterators.drop(eachline(joinpath(TREE, system, "TKE_vs_A", name)), 1)
        f = split(line)
        push!(pts, (A = parse(Float64, f[1]), TKE = NaN, ν = parse(Float64, f[2]), σ = NaN))
    end
    return pts
end

function mean_tke_test(pts, fragment, tke, A₀)
    as_fragment = Float64[]
    as_pair = Float64[]
    for a in sort!(unique(p.A for p in pts))
        t = something(at(tke, a, NaN), at(tke, A₀ - a, NaN), Some(nothing))
        t === nothing && continue
        joint = at(pts, a, t.ν)
        own = at(fragment, a, NaN)
        other = at(fragment, A₀ - a, NaN)
        (joint === nothing || own === nothing || other === nothing) && continue
        push!(as_fragment, joint.ν - own.ν)
        push!(as_pair, joint.ν - (own.ν + other.ν))
    end
    isempty(as_fragment) && return nothing
    return (
        n = length(as_fragment),
        rms_fragment = sqrt(mean(as_fragment .^ 2)),
        rms_pair = sqrt(mean(as_pair .^ 2)),
        mean_fragment = mean(as_fragment),
        mean_pair = mean(as_pair),
    )
end

function reaction_text(text, identifier)
    sub = X.subentry_identifier(identifier)
    i = findfirst("SUBENT        $(sub)", text)
    block = i === nothing ? text : text[first(i):end]
    lines = split(block, '\n')
    k = findfirst(l -> startswith(l, "REACTION"), lines)
    k === nothing && return ""
    out = [strip(lines[k][12:end])]
    for l in lines[(k + 1):end]
        startswith(l, "           ") || break
        push!(out, strip(l))
    end
    return join(out, " ")
end

function main(arguments)
    output = isempty(arguments) ? pwd() : abspath(arguments[1])
    mkpath(output)
    options = RetrievalOptions(; use_cache = true)
    yields =
        Dict(s => reference_yield(s, SYSTEMS[s].yields, options) for s in keys(SYSTEMS))
    header = [
        "system",
        "identifier",
        "nubar",
        "points",
        "A_min",
        "A_max",
        "nu_min",
        "nu_max",
        "nu_yield_weighted",
        "pairs",
        "max_D",
        "rms_D",
        "median_absD_over_sigma",
        "chi2_D_per_pair",
        "D_pos",
        "D_neg",
        "D_zero",
        "D_runs",
        "D_runs_p",
        "S_yield_weighted",
        "S_sigma",
        "yield_coverage",
        "S_min",
        "S_max",
        "siblings",
        "sib_n",
        "rms_minus_sibling",
        "rms_minus_sibling_pair_sum",
        "chi2_as_fragment",
        "chi2_as_pair",
        "yield_reference",
        "yields_own",
        "meanTKE_reference",
        "meanTKE_n",
        "meanTKE_rms_as_fragment",
        "meanTKE_rms_as_pair",
        "meanTKE_mean_as_fragment",
        "meanTKE_mean_as_pair",
        "external",
        "ext_n",
        "ext_rms_as_fragment",
        "ext_rms_as_pair",
        "ext_chi2_as_fragment",
        "ext_chi2_as_pair",
        "both_halves",
        "S_over_nubar",
        "D_zero_test",
        "reading",
        "pair_sum_deviation",
        "pair_sum_deviation_sigma",
        "scale_consistent",
        "reaction_text",
    ]
    f(x) = x isa AbstractFloat ? (isnan(x) ? "" : @sprintf("%.4g", x)) : string(x)
    summary = String[]
    open(joinpath(output, "complement_test.tsv"), "w") do io
        println(io, join(header, '\t'))
        for (system, id, siblings) in CANDIDATES
            s = SYSTEMS[system]
            ν̄ = get(FAST_NUBAR, id, s.ν̄)
            # The evaluated ν̄ at a fast energy is taken without an uncertainty.
            σν̄ = haskey(FAST_NUBAR, id) ? 0.0 : s.σν̄
            pts, text = points(id, options)
            row = Dict{String, Any}(h => "" for h in header)
            row["system"] = system
            row["identifier"] = id
            row["nubar"] = ν̄
            row["points"] = length(pts)
            row["reaction_text"] = reaction_text(text, id)
            row["siblings"] = join(siblings, "+")
            verdicts = Union{Nothing, Symbol}[]
            reading_internal = nothing
            t = nothing
            if !isempty(pts)
                As = [p.A for p in pts]
                νs = [p.ν for p in pts]
                row["A_min"], row["A_max"] = extrema(As)
                row["nu_min"], row["nu_max"] = extrema(νs)
                own = haskey(OWN_YIELDS, id)
                Y = own ? reference_yield(system, OWN_YIELDS[id], options) : yields[system]
                row["yield_reference"] = get(OWN_YIELDS, id, s.yields)
                row["yields_own"] = own
                row["nu_yield_weighted"] = level(pts, Y)
                t = internal(pts, s.A₀, Y)
                if t !== nothing
                    row["pairs"] = t.n
                    row["max_D"], row["rms_D"] = t.max_D, t.rms_D
                    row["median_absD_over_sigma"], row["chi2_D_per_pair"] =
                        t.median_z, t.chi2_D
                    row["D_pos"], row["D_neg"], row["D_zero"] =
                        t.positive, t.negative, t.zero
                    row["D_runs"], row["D_runs_p"] = t.runs, t.runs_p
                    row["S_yield_weighted"], row["S_sigma"] = t.S_weighted, t.σS_weighted
                    row["yield_coverage"] = t.coverage
                    row["S_min"], row["S_max"] = t.S_min, t.S_max
                    row["D_zero_test"] = zero_difference(t)
                    reading_internal = internal_reading(t, ν̄)
                    row["both_halves"] = reading_internal !== nothing
                    reading_internal === nothing || (row["S_over_nubar"] = t.S_weighted / ν̄)
                else
                    row["pairs"] = 0
                    row["both_halves"] = false
                end
                if !isempty(siblings)
                    sib = reduce(vcat, [first(points(x, options)) for x in siblings])
                    b = sibling_test(pts, sib, s.A₀)
                    if b !== nothing
                        row["sib_n"] = b.n
                        row["rms_minus_sibling"], row["rms_minus_sibling_pair_sum"] =
                            b.rms_fragment, b.rms_pair
                        row["chi2_as_fragment"], row["chi2_as_pair"] =
                            b.chi2_fragment, b.chi2_pair
                        push!(
                            verdicts,
                            sibling_verdict(
                                b.chi2_fragment,
                                b.chi2_pair,
                                b.rms_fragment,
                                b.rms_pair,
                            ),
                        )
                    end
                end
            end
            if haskey(MEAN_TKE_CHECKS, id) && !isempty(pts)
                ids, file = MEAN_TKE_CHECKS[id]
                fragment = reduce(vcat, [first(points(x, options)) for x in ids])
                m = mean_tke_test(pts, fragment, mean_tke(system, file), s.A₀)
                row["meanTKE_reference"] = join(ids, "+") * " at " * file
                if m !== nothing
                    row["meanTKE_n"] = m.n
                    row["meanTKE_rms_as_fragment"], row["meanTKE_rms_as_pair"] =
                        m.rms_fragment, m.rms_pair
                    row["meanTKE_mean_as_fragment"], row["meanTKE_mean_as_pair"] =
                        m.mean_fragment, m.mean_pair
                    push!(verdicts, sibling_verdict(NaN, NaN, m.rms_fragment, m.rms_pair))
                end
            end
            if haskey(EXTERNAL_SIBLINGS, id) && !isempty(pts)
                ext =
                    reduce(vcat, [first(points(x, options)) for x in EXTERNAL_SIBLINGS[id]])
                row["external"] = join(EXTERNAL_SIBLINGS[id], "+")
                b = sibling_test(pts, ext, s.A₀)
                if b !== nothing
                    row["ext_n"] = b.n
                    row["ext_rms_as_fragment"], row["ext_rms_as_pair"] =
                        b.rms_fragment, b.rms_pair
                    row["ext_chi2_as_fragment"], row["ext_chi2_as_pair"] =
                        b.chi2_fragment, b.chi2_pair
                    push!(
                        verdicts,
                        sibling_verdict(
                            b.chi2_fragment,
                            b.chi2_pair,
                            b.rms_fragment,
                            b.rms_pair,
                        ),
                    )
                end
            end
            filter!(!isnothing, verdicts)
            reading = if reading_internal !== nothing
                reading_internal
            elseif isempty(verdicts)
                :untested
            else
                allequal(verdicts) ? first(verdicts) : :undecided
            end
            row["reading"] = reading
            scale = "-"
            if reading_internal in (:per_fragment, :per_fission)
                q = pair_sum_scale(t, reading, ν̄, σν̄)
                row["pair_sum_deviation"], row["pair_sum_deviation_sigma"] =
                    q.deviation, q.σ
                row["scale_consistent"] = ismissing(q.consistent) ? "unset" : q.consistent
                scale = @sprintf(
                    "%+.4f ± %s  consistent=%s  yields=%s%s",
                    q.deviation,
                    isnan(q.σ) ? "–" : @sprintf("%.4f", q.σ),
                    row["scale_consistent"],
                    row["yield_reference"],
                    row["yields_own"] ? " (own)" : " (fallback)"
                )
            end
            push!(summary, @sprintf("%-10s %-10s %-14s %s", id, system, reading, scale))
            println(io, join([f(row[h]) for h in header], '\t'))
        end
    end
    write(joinpath(output, "classification.txt"), join(summary, '\n') * '\n')
    print(join(summary, '\n') * '\n')
    return nothing
end

main(ARGS)

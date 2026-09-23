# Retrieval from the IAEA EXFOR web interface.
#
# Two endpoints are used: `x4list` returns the identifiers of the datasets matching a query, and
# `x4get` returns one dataset, either as the csv rendering or as the original subentry text.
#
# A query can name several hundred datasets. Requests are therefore issued under a bounded
# concurrency limit with a timeout and bounded retries, and every response is cached on disk.
# The cache is what makes a re-run cost the archive one listing request and what keeps the load
# on a public service proportionate to the data actually being used.
#
# It is not a statement that the archive stands still. Entries are revised — the HISTORY of a
# subentry records each alteration — and new ones are added. A dataset response is served from
# the cache while it is usable, not refreshed, and younger than `max_age_days`. The listing of
# datasets is requested on every run, because a cached listing never discovers an entry added
# after it was written. Whatever is requested falls back to a usable cached copy, with a warning
# naming the date of that copy, when the archive cannot be reached. `offline` serves the cache
# alone and never contacts the archive; `refresh` requests everything a run touches and replaces
# what is cached. Every response carries the date it was obtained from the archive.

"""Base URL of the IAEA EXFOR web interface."""
const EXFOR_BASE = "https://nds.iaea.org/exfor/"

"""
Value of the `User-Agent` header sent with every request.

Identifying the client is the courtesy owed a shared public service: it lets whoever runs the
archive see what its automated traffic actually is, and gives them somebody to contact if a
client misbehaves. The version is read from the project file, so a report names something that
can be looked up rather than "some Julia script".
"""
const USER_AGENT = let version = pkgversion(@__MODULE__)
    string(
        "ExforFissionData.jl/",
        version === nothing ? "unknown" : version,
        " (+https://github.com/PaulGoG/ExforFissionData.jl)",
    )
end

"""
    RetrievalOptions(; kwargs...)

Transport settings for EXFOR retrieval.

# Fields
- `concurrency::Int = 4`: simultaneous in-flight requests.
- `timeout::Float64 = 60.0`: per-request timeout in seconds.
- `retries::Int = 4`: retry attempts after a failed request.
- `backoff::Float64 = 1.0`: base of the exponential backoff in seconds; attempt `k` waits
  `backoff · 2^(k-1)`.
- `use_cache::Bool = true`: read and write the on-disk response cache.
- `refresh::Bool = false`: refetch every response and replace the cached copy, which is how a
  cache is brought up to date with entries the archive has revised or added since.
- `cache_directory::String`: where responses are cached; defaults to a `Scratch.jl` space, which
  keeps the cache out of the package tree and out of any project directory.
- `offline::Bool = false`: serve every response from the cache and never contact the archive; a
  response that is not cached is an error.
- `max_age_days::Float64 = Inf`: a cached dataset response older than this is requested again,
  the cached copy being kept only as the fallback; `Inf` never expires a response.
"""
Base.@kwdef struct RetrievalOptions
    concurrency::Int = 4
    timeout::Float64 = 60.0
    retries::Int = 4
    backoff::Float64 = 1.0
    use_cache::Bool = true
    refresh::Bool = false
    cache_directory::String = ""
    offline::Bool = false
    max_age_days::Float64 = Inf
end

"""
    cache_directory(options) -> String

The directory backing the response cache, created if absent.

Falls back to a `Scratch.jl` scratch space when `options.cache_directory` is empty.
"""
function cache_directory(options::RetrievalOptions)
    directory = if isempty(options.cache_directory)
        @get_scratch!("exfor-responses")
    else
        options.cache_directory
    end
    isdir(directory) || mkpath(directory)
    return directory
end

# A filesystem-safe name for a query string. EXFOR identifiers and query parameters are short and
# alphanumeric, so escaping the few punctuation characters keeps cache entries legible on disk.
function _cache_key(query::AbstractString)
    return replace(String(query), r"[^A-Za-z0-9._-]" => "_")
end

"""
    is_usable_response(body) -> Bool

Whether a response body is worth parsing or keeping.

The archive answers some requests with HTTP 200 and a short application-level message instead of
data, and a transient failure can yield an empty body under the same status. Neither is a
response to cache: an entry is otherwise fetched at most once, so storing one silently removes
that dataset from every later run.

The archive also answers a request for an identifier it does not know with a message beginning
`-?-` (`-?-No such data in the database-`), which was cached and written out as subentry text.
"""
function is_usable_response(body::AbstractString)
    trimmed = strip(body)
    isempty(trimmed) && return false
    startswith(trimmed, "No EXFOR file") && return false
    startswith(trimmed, "-?-") && return false
    return true
end

"""
    Response

One response of the archive.

# Fields
- `body::String`: the text.
- `retrieved::DateTime`: when the body was obtained from the archive, in UTC — the modification
  time of the cache file for a cached copy, the moment of the request otherwise.
- `from_cache::Bool`: whether the body was served from the cache rather than requested.
"""
struct Response
    body::String
    retrieved::DateTime
    from_cache::Bool
end

"""
    Listing

The dataset identifiers matching a query, with the provenance of the listing.

# Fields
- `identifiers::Vector{String}`: the identifiers, sorted.
- `retrieved::DateTime`: when the listing was obtained from the archive, in UTC.
- `from_cache::Bool`: whether the listing was served from the cache rather than requested.
"""
struct Listing
    identifiers::Vector{String}
    retrieved::DateTime
    from_cache::Bool
end

"""
    subentry_identifier(identifier) -> String

The eight-character subentry identifier of an EXFOR dataset.

An EXFOR dataset identifier is the eight-character subentry identifier, followed by a
one-character pointer when the subentry holds several datasets in pointed columns (`400170021`,
`30666002I`). The archive serves subentries by the eight characters alone and answers the
nine-character form with `-?-No such data in the database-`.

Throws an `ArgumentError` unless `identifier` has eight or nine characters.

# Example

```julia
julia> subentry_identifier("400170021")
"40017002"
```
"""
function subentry_identifier(identifier::AbstractString)
    8 ≤ length(identifier) ≤ 9 || throw(
        ArgumentError(
            "dataset identifier \"$(identifier)\" must be 8 characters, or 9 when the ninth \
             is a pointer",
        ),
    )
    return String(first(identifier, 8))
end

"""
    fetch_response(query, options; listing = false) -> Response

Retrieve `query` relative to [`EXFOR_BASE`](@ref) under the cache policy.

A dataset response is served from the cache while it is usable, not refreshed, and younger than
`options.max_age_days`. A listing (`listing = true`) is always requested, because the archive adds
entries and a cached listing never discovers them. Whichever is requested falls back to a usable
cached copy, with a warning naming the date of that copy, when the archive cannot be reached.
`options.offline` serves the cache alone and throws an `ArgumentError` for a query that is not
cached.

Retries on transport failures and on server errors with exponential backoff; a 4xx response is
not retried, since it will not succeed on repetition. Throws the final exception when a request
fails and nothing usable is cached.
"""
function fetch_response(
    query::AbstractString,
    options::RetrievalOptions;
    listing::Bool = false,
)
    path = joinpath(cache_directory(options), _cache_key(query))
    # An unusable entry counts as a miss rather than being served. Caches written before this
    # check existed hold empty bodies and archive error messages, and this repairs them on the
    # next run instead of requiring anyone to know they need clearing.
    cached = options.use_cache && isfile(path) ? read(path, String) : ""
    usable = is_usable_response(cached)
    cached_at = usable ? Dates.unix2datetime(mtime(path)) : typemin(DateTime)

    if options.offline
        usable && return Response(cached, cached_at, true)
        throw(ArgumentError("offline: no cached response for \"$(query)\" under \
                 $(cache_directory(options))"))
    end
    if usable && !options.refresh && !listing
        age_days = (Dates.now(Dates.UTC) - cached_at) / Dates.Day(1)
        age_days ≤ options.max_age_days && return Response(cached, cached_at, true)
    end

    url = string(EXFOR_BASE, query)
    for attempt in 1:(options.retries + 1)
        try
            response = HTTP.get(
                url;
                headers = ["User-Agent" => USER_AGENT],
                request_timeout = options.timeout,
                connect_timeout = options.timeout,
                retry = false,
                status_exception = true,
            )
            body = String(response.body)
            # Retried rather than accepted: every instance of this observed so far has been
            # transient, with the archive serving the same identifier correctly moments later.
            # After the last attempt the body is returned anyway, so that one unlucky dataset
            # is rejected with a reason rather than aborting the whole retrieval.
            if !is_usable_response(body) && attempt ≤ options.retries
                sleep(options.backoff * 2.0^(attempt - 1))
                continue
            end
            if options.use_cache && is_usable_response(body)
                # Write through a name unique to this task, so that a concurrent reader never
                # sees a partial file and two tasks fetching the same query cannot collide on
                # the temporary. The rename is atomic within a filesystem.
                temporary =
                    string(path, ".", getpid(), ".", objectid(current_task()), ".partial")
                write(temporary, body)
                mv(temporary, path; force = true)
            end
            if !is_usable_response(body) && usable
                @warn(
                    "the archive returned no usable body; serving the cached response",
                    query,
                    retrieved = cached_at,
                )
                return Response(cached, cached_at, true)
            end
            return Response(body, Dates.now(Dates.UTC), false)
        catch exception
            # Only transport failures are retried; anything else is a defect and propagates.
            exception isa Union{HTTP.HTTPError, Base.IOError} || rethrow()
            # A 4xx will not succeed on repetition; the last attempt has nothing left to try.
            if (exception isa HTTP.StatusError && 400 ≤ exception.status < 500) ||
               attempt > options.retries
                usable || rethrow()
                @warn(
                    "the archive could not be reached; serving the cached response",
                    query,
                    retrieved = cached_at,
                    exception = exception,
                )
                return Response(cached, cached_at, true)
            end
            sleep(options.backoff * 2.0^(attempt - 1))
        end
    end
    # The final iteration either returns or rethrows, so control never reaches here.
    error("unreachable: retrieval of $(url) neither returned nor threw")
end

"""
    dataset_identifiers(target, reaction, quantity, options) -> Listing

Identifiers of every EXFOR dataset matching a target, reaction and quantity, as a
[`Listing`](@ref) that records when the archive was asked.

`target` is an EXFOR nuclide symbol such as `"U-233"`, `reaction` is `"n,f"` or `"0,f"`, and
`quantity` is an EXFOR quantity code such as `"FY"` or `"NU"`. The identifiers are returned
sorted, so that everything downstream is independent of the order the service happens to use.
The listing is requested on every run that is not offline; see [`fetch_response`](@ref).

# Example

```julia
julia> listing = dataset_identifiers("U-233", "n,f", "FY", RetrievalOptions());

julia> listing.identifiers
```
"""
function dataset_identifiers(
    target::AbstractString,
    reaction::AbstractString,
    quantity::AbstractString,
    options::RetrievalOptions,
)
    query = "x4list?Target=$(target)&Reaction=$(reaction)&Quantity=$(quantity)&txt"
    response = fetch_response(query, options; listing = true)
    identifiers = String[]
    for line in eachline(IOBuffer(response.body))
        token = strip(line)
        isempty(token) && continue
        push!(identifiers, String(token))
    end
    return Listing(sort!(identifiers), response.retrieved, response.from_cache)
end

"""
    dataset_csv(identifier, options) -> Response

The `op=csv&plus=2` rendering of one dataset, with the date it was obtained from the archive.
"""
function dataset_csv(identifier::AbstractString, options::RetrievalOptions)
    return fetch_response("x4get?DatasetID=$(identifier)&op=csv&plus=2", options)
end

"""
    subentry_text(identifier, options) -> Response

The original EXFOR subentry text of one dataset, retained beside the extracted data so that
every written file can be traced to the archive record it came from.

The subentry is requested by its eight-character identifier, from
[`subentry_identifier`](@ref). A dataset identifier with a ninth character points into a
subentry shared by several datasets, and the archive does not know the nine-character form.
"""
function subentry_text(identifier::AbstractString, options::RetrievalOptions)
    return fetch_response("x4get?sub=$(subentry_identifier(identifier))", options)
end

"""Batch size from which [`map_bounded`](@ref) logs its progress."""
const PROGRESS_MINIMUM = 100

"""
    map_bounded(f, items, options) -> Vector

Apply `f` to each element of `items` with at most `options.concurrency` tasks in flight.

Results are returned in the order of `items`, never in completion order, so that a run is
reproducible regardless of how the network behaves. An exception in a task propagates when that
task is fetched, in input order; the tasks after it still run to completion but are not awaited.
"""
function map_bounded(f, items::AbstractVector, options::RetrievalOptions)
    semaphore = Base.Semaphore(max(1, options.concurrency))
    total = length(items)
    completed = Threads.Atomic{Int}(0)
    # One line per tenth of a batch large enough to keep a user waiting; small batches stay quiet.
    stride = total ≥ PROGRESS_MINIMUM ? max(1, total ÷ 10) : 0
    tasks = map(items) do item
        Threads.@spawn begin
            Base.acquire(semaphore)
            try
                f(item)
            finally
                Base.release(semaphore)
                done = Threads.atomic_add!(completed, 1) + 1
                stride > 0 &&
                    done % stride == 0 &&
                    done < total &&
                    @info "requests completed" completed = done of = total
            end
        end
    end
    return map(Base.fetch, tasks)
end

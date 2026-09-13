# Retrieval from the IAEA EXFOR web interface.
#
# Two endpoints are used: `x4list` returns the identifiers of the datasets matching a query, and
# `x4get` returns one dataset, either as the csv rendering or as the original subentry text.
#
# A query can name several hundred datasets. Requests are therefore issued under a bounded
# concurrency limit with a timeout and bounded retries, and every response is cached on disk:
# an EXFOR entry is immutable once published, so a dataset never needs fetching twice. The cache
# is what makes a re-run cost nothing and what keeps the load on a public service proportionate
# to the data actually being used.

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
- `cache_directory::String`: where responses are cached; defaults to a `Scratch.jl` space, which
  keeps the cache out of the package tree and out of any project directory.
"""
Base.@kwdef struct RetrievalOptions
    concurrency::Int = 4
    timeout::Float64 = 60.0
    retries::Int = 4
    backoff::Float64 = 1.0
    use_cache::Bool = true
    cache_directory::String = ""
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
"""
function is_usable_response(body::AbstractString)
    trimmed = strip(body)
    isempty(trimmed) && return false
    startswith(trimmed, "No EXFOR file") && return false
    return true
end

"""
    request(query, options) -> String

Retrieve `query` relative to [`EXFOR_BASE`](@ref), through the cache when enabled.

Retries on transport failures and on server errors with exponential backoff; a 4xx response is
not retried, since it will not succeed on repetition. Throws the final exception when every
attempt fails.
"""
function request(query::AbstractString, options::RetrievalOptions)
    path = joinpath(cache_directory(options), _cache_key(query))
    if options.use_cache && isfile(path)
        cached = read(path, String)
        # An unusable entry counts as a miss rather than being served. Caches written before
        # this check existed hold empty bodies and archive error messages, and this repairs them
        # on the next run instead of requiring anyone to know they need clearing.
        is_usable_response(cached) && return cached
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
            return body
        catch exception
            # A 4xx will not succeed on repetition; the last attempt has nothing left to try.
            if exception isa HTTP.StatusError && 400 ≤ exception.status < 500
                rethrow()
            end
            attempt > options.retries && rethrow()
            sleep(options.backoff * 2.0^(attempt - 1))
        end
    end
    # The final iteration either returns or rethrows, so control never reaches here.
    error("unreachable: retrieval of $(url) neither returned nor threw")
end

"""
    dataset_identifiers(target, reaction, quantity, options) -> Vector{String}

Identifiers of every EXFOR dataset matching a target, reaction and quantity.

`target` is an EXFOR nuclide symbol such as `"U-233"`, `reaction` is `"n,f"` or `"0,f"`, and
`quantity` is an EXFOR quantity code such as `"FY"` or `"NU"`. The identifiers are returned
sorted, so that everything downstream is independent of the order the service happens to use.

# Example

```julia
julia> identifiers = dataset_identifiers("U-233", "n,f", "FY", RetrievalOptions());
```
"""
function dataset_identifiers(
    target::AbstractString,
    reaction::AbstractString,
    quantity::AbstractString,
    options::RetrievalOptions,
)
    query = "x4list?Target=$(target)&Reaction=$(reaction)&Quantity=$(quantity)&txt"
    body = request(query, options)
    identifiers = String[]
    for line in eachline(IOBuffer(body))
        token = strip(line)
        isempty(token) && continue
        push!(identifiers, String(token))
    end
    return sort!(identifiers)
end

"""
    dataset_csv(identifier, options) -> String

The `op=csv&plus=2` rendering of one dataset.
"""
function dataset_csv(identifier::AbstractString, options::RetrievalOptions)
    return request("x4get?DatasetID=$(identifier)&op=csv&plus=2", options)
end

"""
    subentry_text(identifier, options) -> String

The original EXFOR subentry text of one dataset, retained beside the extracted data so that
every written file can be traced to the archive record it came from.
"""
function subentry_text(identifier::AbstractString, options::RetrievalOptions)
    return request("x4get?sub=$(identifier)", options)
end

"""
    map_bounded(f, items, options) -> Vector

Apply `f` to each element of `items` with at most `options.concurrency` tasks in flight.

Results are returned in the order of `items`, never in completion order, so that a run is
reproducible regardless of how the network behaves. An exception in any task propagates once
every task has been awaited.
"""
function map_bounded(f, items::AbstractVector, options::RetrievalOptions)
    semaphore = Base.Semaphore(max(1, options.concurrency))
    tasks = map(items) do item
        Threads.@spawn begin
            Base.acquire(semaphore)
            try
                f(item)
            finally
                Base.release(semaphore)
            end
        end
    end
    return map(Base.fetch, tasks)
end

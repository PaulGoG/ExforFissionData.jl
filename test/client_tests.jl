# The archive client: bounded concurrency, the response cache, and a retrieval served from it.

@testset "client" begin
    @testset "bounded concurrency" begin
        # Results follow the input order, never completion order, so two runs agree.
        options = ExforFissionData.RetrievalOptions(; concurrency = 4)
        delays = [0.05, 0.0, 0.03, 0.0, 0.01, 0.0, 0.02, 0.0, 0.04]
        result = ExforFissionData.map_bounded(eachindex(delays), options) do index
            sleep(delays[index])
            index
        end
        @test result == collect(eachindex(delays))

        # The semaphore bounds work in flight. Counting concurrent entries must never exceed it.
        for limit in (1, 3)
            options = ExforFissionData.RetrievalOptions(; concurrency = limit)
            in_flight = Threads.Atomic{Int}(0)
            peak = Threads.Atomic{Int}(0)
            ExforFissionData.map_bounded(1:24, options) do _
                current = Threads.atomic_add!(in_flight, 1) + 1
                old = peak[]
                while current > old
                    old = Threads.atomic_cas!(peak, old, current)
                end
                sleep(0.005)
                Threads.atomic_sub!(in_flight, 1)
                nothing
            end
            @test peak[] ≤ limit
        end

        # A task that throws surfaces rather than being swallowed.
        options = ExforFissionData.RetrievalOptions(; concurrency = 2)
        @test_throws TaskFailedException ExforFissionData.map_bounded(1:4, options) do index
            index == 3 && error("failure in task $(index)")
            index
        end
    end

    @testset "response cache" begin
        directory = mktempdir()
        options = ExforFissionData.RetrievalOptions(; cache_directory = directory)
        # A cached response is returned without a request, which is what makes a re-run free and
        # keeps one dataset from being fetched from the archive more than once.
        key = ExforFissionData._cache_key("x4get?DatasetID=10433002&op=csv&plus=2")
        write(joinpath(directory, key), "cached body")
        @test ExforFissionData.fetch_response(
            "x4get?DatasetID=10433002&op=csv&plus=2",
            options,
        ).body == "cached body"

        # The response carries when the archive served it, which is what the run record dates
        # each dataset by.
        dataset_query = "x4get?DatasetID=10433002&op=csv&plus=2"
        response = ExforFissionData.fetch_response(dataset_query, options)
        @test response.from_cache
        @test response.body == "cached body"
        @test response.retrieved isa DateTime

        # An empty rendering is asked for again rather than trusted, while a rendering with rows
        # is served without a request: the unreachable archive shows which was attempted.
        header = join(EXFOR_HEADER, ',') * "\n"
        empty_query = "x4get?DatasetID=22413013&op=csv&plus=2"
        write(joinpath(directory, ExforFissionData._cache_key(empty_query)), header)
        unreachable_dataset =
            RetrievalOptions(; cache_directory = directory, retries = 0, timeout = 0.001)
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(empty_query, unreachable_dataset)
        end
        @test response.from_cache && response.body == header
        @test ExforFissionData.is_empty_rendering(header)
        @test !ExforFissionData.is_empty_rendering(header * "22413013,1997\n")
        @test_logs ExforFissionData.fetch_response(dataset_query, unreachable_dataset)

        # Offline serves the cache and refuses anything it does not hold.
        offline = RetrievalOptions(; cache_directory = directory, offline = true)
        @test ExforFissionData.fetch_response(dataset_query, offline).from_cache
        uncached_query = "x4get?DatasetID=99999999&op=csv&plus=2"
        message = try
            ExforFissionData.fetch_response(uncached_query, offline)
            ""
        catch exception
            @test exception isa ArgumentError
            exception.msg
        end
        @test occursin("offline", message)

        # The listing is always requested, since a cached listing never discovers an entry the
        # archive adds; when the archive cannot be reached, the cached copy stands in.
        listing_query = "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"
        write(joinpath(directory, ExforFissionData._cache_key(listing_query)), "10000002\n")
        unreachable =
            RetrievalOptions(; cache_directory = directory, retries = 0, timeout = 0.001)
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(listing_query, unreachable; listing = true)
        end
        @test response.from_cache
        @test response.body == "10000002\n"

        # A dataset response older than max_age_days is requested again, and the cached copy
        # is the fallback.
        sleep(0.01)
        expiring = RetrievalOptions(;
            cache_directory = directory,
            retries = 0,
            timeout = 0.001,
            max_age_days = 1e-9,
        )
        response = @test_logs (:warn, r"cached") match_mode = :any begin
            ExforFissionData.fetch_response(dataset_query, expiring)
        end
        @test response.from_cache
        @test response.body == "cached body"

        listing = ExforFissionData.dataset_identifiers("U-233", "n,f", "FY", offline)
        @test listing isa ExforFissionData.Listing
        @test listing.identifiers == ["10000002"]
        @test listing.from_cache

        # A pointer dataset lives in a subentry shared with others, requested by the eight
        # characters the archive knows it by.
        @test subentry_identifier("400170021") == "40017002"
        @test subentry_identifier("30666002I") == "30666002"
        @test subentry_identifier("10864009") == "10864009"
        @test_throws ArgumentError subentry_identifier("1086400")
        @test_throws ArgumentError subentry_identifier("1086400912")

        # Requests identify the client. The archive is a shared public service, and this
        # package asks its users to be considerate of it, so it names itself and its version
        # rather than arriving anonymously.
        @test occursin("ExforFissionData.jl/", ExforFissionData.USER_AGENT)
        @test occursin(
            "github.com/PaulGoG/ExforFissionData.jl",
            ExforFissionData.USER_AGENT,
        )
        @test occursin(string(pkgversion(ExforFissionData)), ExforFissionData.USER_AGENT)

        # Reaching a written value goes through these, so they are part of the result rather
        # than internals and must be exported; a user should not have to name an unexported
        # type to read what a retrieval produced.
        for name in (:AcceptedDataset, :ReducedDataset, :RetrievalResult, :Dataset)
            @test name in names(ExforFissionData)
        end

        # The archive answers some requests with HTTP 200 and a short message instead of data,
        # and a transient failure gives an empty body under the same status. Caching either one
        # removes that dataset from every later run, because an entry is fetched at most once.
        @test is_usable_response("DatasetID,year1\n40871011,1983")
        @test !is_usable_response("")
        @test !is_usable_response("   \n ")
        @test !is_usable_response("No EXFOR file...")
        # The answer to an identifier the archive does not know, which was once cached and
        # written out as subentry text.
        @test !is_usable_response("-?-No such data in the database-")

        # A poisoned entry is a miss, not a response. Without this, a cache written before the
        # check existed would keep serving the failure forever; with it, the next run repairs
        # itself. No request is made here, so an empty cache file must surface as a failure to
        # reach the archive rather than as the empty string.
        for poison in ("", "No EXFOR file...")
            write(joinpath(directory, key), poison)
            @test_throws ExforFissionData.HTTP.HTTPError ExforFissionData.fetch_response(
                "x4get?DatasetID=10433002&op=csv&plus=2",
                ExforFissionData.RetrievalOptions(;
                    cache_directory = directory,
                    retries = 0,
                    timeout = 0.001,
                ),
            )
        end

        # An unparseable body is reported as a response failure, not as a layout change: the
        # column contract is not what went wrong, and saying so sends the reader to the wrong file.
        for body in ("", "No EXFOR file...")
            message = try
                ExforFissionData.parse_dataset("40871011", body)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("no usable data", message)
            # Must not send the reader to src/schema.jl, which is what validate_header's
            # message does and which is the wrong place to look for this failure.
            @test !occursin("must be updated", message)
        end

        # Cache keys stay distinct across the queries that differ only in punctuation.
        @test ExforFissionData._cache_key(
            "x4list?Target=U-235&Reaction=n,f&Quantity=FY&txt",
        ) != ExforFissionData._cache_key(
            "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt",
        )
    end

    @testset "retrieval from a seeded cache" begin
        mktempdir() do directory
            cache = joinpath(directory, "cache")
            mkpath(cache)
            seed(query, body) =
                write(joinpath(cache, ExforFissionData._cache_key(query)), body)
            configuration_file = joinpath(directory, "U233_nth_Y_vs_A.toml")
            write(
                configuration_file,
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                energy_min = 0.0
                energy_max = 1.0e-7

                [retrieval]
                cache_directory = "$(cache)"
                save_subentries = false
                offline = true
                """,
            )
            configuration = load_configuration(configuration_file)
            listing = "x4list?Target=U-233&Reaction=n,f&Quantity=FY&txt"
            csv(identifier) = "x4get?DatasetID=$(identifier)&op=csv&plus=2"
            thermal(; kwargs...) = exfor_row(; incident_ev = 0.0253, kwargs...)

            # A non-integer mass scale the rendering truncates, restored from the subentry,
            # beside a dataset gated on a variable the abscissa does not hold.
            seed(listing, "10000002\n10000003\n")
            seed(
                csv("10000002"),
                exfor_csv([
                    thermal(; product_za = 63, y = 6.0, dy = 0.1),
                    thermal(; product_za = 64, y = 6.4, dy = 0.1),
                    thermal(; product_za = 66, y = 5.0, dy = 0.1),
                ]),
            )
            seed(
                "x4get?sub=10000002",
                exfor_subentry(;
                    subentry = "10000002",
                    headings = ["MASS", "DATA", "DATA-ERR"],
                    units = ["NO-DIM", "PRT/FIS", "PRT/FIS"],
                    rows = [[63.51, 6.0, 0.1], [64.91, 6.4, 0.1], [66.0, 5.0, 0.1]],
                    common = (headings = ["EN-DUMMY"], units = ["EV"], values = [0.0253]),
                ),
            )
            gated_rows = [
                thermal(; dataset_id = "10000003", product_za = 100, secondary_ev = energy) for energy in (1.00e8, 1.07e8)
            ]
            seed(csv("10000003"), exfor_csv(gated_rows))
            seed("x4get?sub=10000003", exfor_subentry_for(gated_rows))
            rerun() = retrieve(configuration; root = directory)
            result = rerun()
            @test [entry.dataset.identifier for entry in result.accepted] == ["10000002"]
            @test only(result.rejected).identifier == "10000003"
            @test occursin("E [EV] (2 values)", only(result.rejected).reason)
            record = TOML.parsefile(result.metadata_file)
            @test !haskey(record["datasets"], "combined_warning")
            @test only(record["accepted"])["abscissae_combined"] == 0
            @test only(record["accepted"])["mass_values_non_integer"] == 2
            @test only(record["accepted"])["mass_treatment"] == "interpolated"
            written = readlines(joinpath(result.directory, only(result.accepted).file))
            @test [first(split(line, ' ')) for line in written[2:end]] == ["64", "65", "66"]
            @test haskey(record["run"], "package_version")
            @test haskey(record["conventions"], "abscissa_resolution")
            # Every response is dated, so the record states which archive it reflects.
            @test record["run"]["listing_from_cache"] == true
            @test haskey(record["run"], "listing_retrieved_utc")
            @test only(record["accepted"])["from_cache"] == true
            @test haskey(only(record["accepted"]), "retrieved_utc")
            @test haskey(record["datasets"], "retrieved_latest_utc")
            @test haskey(record["conventions"], "archive_state")

            # Every response failing the column contract is the rendering having changed, and
            # must stop the run instead of reporting an archive with nothing in it.
            shifted = collect(EXFOR_HEADER)
            shifted[26] = "ProdZAX"
            for identifier in ("10000002", "10000003")
                seed(
                    csv(identifier),
                    exfor_csv([thermal(; product_za = 100)]; header = shifted),
                )
            end
            @test_throws LayoutError rerun()
        end
    end
end

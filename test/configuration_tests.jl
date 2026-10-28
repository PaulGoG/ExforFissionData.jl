# Configuration loading and validation, the shipped configurations, the vocabulary tables and the
# Query constructors.

@testset "configuration" begin
    @testset "configuration validation" begin
        configuration = load_configuration_text(u233_yield_toml("energy_max = 1.0e-7\n"))
        @test target_symbol(configuration.query) == "U-233"
        @test !configuration.query.spontaneous
        # The EXFOR reaction and quantity codes are derived from the channel and the ordinate.
        # A configuration that could state them could state them wrongly, and the quantity in
        # particular decides which datasets the archive offers at all.
        @test configuration.query.reaction == "n,f"
        @test configuration.query.quantity == "FY"
        # These two name the directories the data is written to, and a consumer keys its stored
        # data on them, so they must stay stable as long as the query does.
        @test system_label(configuration.query) == "U233_nth"
        @test observable_label(configuration.query) == "Y_vs_A"

        spontaneous = load_configuration_text("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["mass", "total_kinetic_energy"]
        ordinate = "multiplicity"
        """)
        @test spontaneous.query.spontaneous
        @test spontaneous.query.reaction == "0,f"
        @test system_label(spontaneous.query) == "Cf252_sf"
        @test observable_label(spontaneous.query) == "nu_vs_A_TKE"

        # A thermal and a resonance run of one observable differ by system, not by an output
        # directory chosen to keep them apart.
        resonance = load_configuration_text("""
        [query]
        target_Z = 92
        target_A = 235
        channel = "nres"
        abscissa = ["mass"]
        ordinate = "multiplicity"
        energy_max = 1.0e-3
        """)
        @test system_label(resonance.query) == "U235_nres"
        @test resonance.query.reaction == "n,f"

        @test element_symbol(98) == "Cf"
        @test element_symbol(92) == "U"
        @test_throws ArgumentError element_symbol(0)

        # A key the loader does not know is refused, not ignored. The misspelt window is the
        # case that matters: it would fall back to every incident energy the archive holds.
        misspelt = write_config(u233_yield_toml("energy_maxx = 1.0e-7\n"))
        @test_throws ["`energy_maxx`", "[query]"] load_configuration(misspelt)
        @test_throws ArgumentError load_configuration_text(u233_yield_toml("""
        [reduction]
        weighting = "none"
        """))
        # Refreshing replaces cached responses, so it has nothing to act on without a cache.
        refreshed = load_configuration_text(u233_yield_toml("""
        [retrieval]
        refresh = true
        """))
        @test refreshed.retrieval.refresh
        @test !configuration.retrieval.refresh
        @test_throws ArgumentError load_configuration_text(u233_yield_toml("""
        [retrieval]
        use_cache = false
        refresh = true
        """))

        # Offline serves the cache alone, so it needs one and cannot be combined with refresh,
        # which always contacts the archive.
        offline = load_configuration_text(u233_yield_toml("""
        [retrieval]
        offline = true
        """))
        @test offline.retrieval.offline
        @test offline.retrieval.max_age_days == Inf
        @test !configuration.retrieval.offline
        exception = try
            load_configuration_text(u233_yield_toml("""
            [retrieval]
            use_cache = false
            offline = true
            """))
            nothing
        catch error
            error
        end
        @test exception isa ArgumentError
        @test occursin("offline", exception.msg)
        @test_throws ArgumentError load_configuration_text(u233_yield_toml("""
        [retrieval]
        offline = true
        refresh = true
        """))

        # A cached dataset response expires after a positive number of days.
        aged = load_configuration_text(u233_yield_toml("""
        [retrieval]
        max_age_days = 30
        """))
        @test aged.retrieval.max_age_days === 30.0
        for age in (0, -1)
            @test_throws ArgumentError load_configuration_text(u233_yield_toml("""
            [retrieval]
            max_age_days = $(age)
            """))
        end

        # The endpoint defaults to the IAEA archive and must be an http or https URL.
        @test configuration.retrieval.base_url == ExforFissionData.EXFOR_BASE
        @test_throws "base_url" load_configuration_text(u233_yield_toml("""
        [retrieval]
        base_url = "ftp://example/"
        """))

        # Spontaneous fission has no incident particle, so a window on it cannot be honoured.
        @test_throws ArgumentError load_configuration_text("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = ["mass"]
        ordinate = "yield"
        energy_max = 1.0e-7
        """)

        # The window lies inside its channel's interval and defaults to it, so a thermal
        # directory cannot hold a fast measurement.
        channel_config(channel, window) = write_config("""
        [query]
        target_Z = 92
        target_A = 235
        channel = "$(channel)"
        abscissa = ["mass"]
        ordinate = "yield"
        $(window)
        """)
        for (channel, window, needles) in [
            ("nth", "energy_max = 1.0", ["nth", "1.0e-7"]),
            ("nres", "energy_min = 0.0", ["nres"]),
            ("nfast", "energy_max = 30.0", ["nfast"]),
        ]
            exception = try
                load_configuration(channel_config(channel, window))
                nothing
            catch error
                error
            end
            @test exception isa ArgumentError
            for needle in needles
                @test occursin(needle, exception.msg)
            end
        end
        for (channel, bounds) in
            [("nth", (0.0, 1.0e-7)), ("nres", (1.0e-7, 0.1)), ("nfast", (0.1, 20.0))]
            query = load_configuration(channel_config(channel, "")).query
            @test query.energy_min == bounds[1]
            @test query.energy_max == bounds[2]
        end

        # Arbitrary units are fatal for most observables and normal for a spectrum, which is
        # conventionally measured relative.
        @test tolerates_relative_scale("spectrum")
        @test tolerates_relative_scale("spectrum_maxwellian_ratio")
        @test !tolerates_relative_scale("yield")
        @test !tolerates_relative_scale("multiplicity")
        @test !tolerates_relative_scale("fragment_kinetic_energy")

        # The machine name is off unless asked for: the run record is written to be committed by
        # whoever consumes the data, and it is the one field identifying a person, not a result.
        @test !configuration.record_hostname
        hostnamed = load_configuration_text(u233_yield_toml("""
        energy_max = 1.0e-7

        [output]
        record_hostname = true
        """))
        @test hostnamed.record_hostname

        for (content, needle) in [
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "p,f"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "channel",
            ),
            (
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["charge_polarisation"]
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                # An abscissa is a list even when it names one quantity, so that a joint index
                # needs no vocabulary of its own.
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = "mass"
                ordinate = "yield"
                """,
                "abscissa",
            ),
            (
                # A quantity cannot be tabulated against itself: two columns would be called TKE.
                """
                [query]
                target_Z = 92
                target_A = 233
                channel = "nth"
                abscissa = ["total_kinetic_energy"]
                ordinate = "total_kinetic_energy"
                """,
                "tabulated against itself",
            ),
            (u233_yield_toml("""
             energy_min = 1.0
             energy_max = 0.5
             """), "energy_max"),
            (u233_yield_toml("""
             [retrieval]
             concurrency = 99
             """), "concurrency"),
            (
                """
                [query]
                target_A = 233
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "target_Z",
            ),
            (
                # A mass number below the charge is not a nuclide.
                """
                [query]
                target_Z = 92
                target_A = 12
                channel = "nth"
                abscissa = ["mass"]
                ordinate = "yield"
                """,
                "target_A",
            ),
        ]
            path = write_config(content)
            exception = try
                load_configuration(path)
                nothing
            catch error
                error
            end
            @test exception isa ArgumentError
            @test occursin(needle, exception.msg)
        end
    end

    @testset "shipped configurations" begin
        # Every configuration in config/ must load and validate, so a shipped example cannot
        # drift out of step with the validator that reads it.
        directory = joinpath(pkgdir(ExforFissionData), "config")
        files = filter(endswith(".toml"), readdir(directory; join = true))
        @test !isempty(files)
        for file in files
            query = load_configuration(file).query
            # One name for one thing: a configuration is named for the system and observable it
            # retrieves, which are the two directories its data is written to.
            @test basename(file) ==
                  string(system_label(query), "_", observable_label(query), ".toml")
            @test query.reaction == ExforFissionData.CHANNEL_REACTION[query.channel]
            @test query.quantity == ExforFissionData.ORDINATE_QUANTITY[query.ordinate]
        end

        # The [retrieval] and [output] sections of `lines`, keys and comments without values.
        function retrieval_and_output(lines)
            block = String[]
            for line in lines[findfirst(==("[retrieval]"), lines):end]
                header = match(r"^\[+([^\]]+)\]", line)
                header === nothing || header[1] in ("retrieval", "output") || break
                assignment = match(r"^(#?\s*\w+)\s*=[^#]*(#.*)?$", line)
                push!(
                    block,
                    assignment === nothing ? rstrip(line) :
                    string(assignment[1], " = ", something(assignment[2], "")),
                )
            end
            while !isempty(block) && isempty(last(block))
                pop!(block)
            end
            return block
        end
        # The comment of the line assigning `key`, with the indented comment lines after it.
        function key_comment(lines, key)
            index = findfirst(line -> startswith(line, key * " ="), lines)
            own = findfirst('#', lines[index])
            comments = own === nothing ? String[] : [lines[index][own:end]]
            for line in lines[(index + 1):end]
                occursin(r"^\s+#", line) || break
                push!(comments, strip(line))
            end
            return join(comments, ' ')
        end

        # The comments are copied between files: they must neither drift apart nor fall out of
        # step with the vocabulary they enumerate.
        @test allequal(retrieval_and_output(readlines(file)) for file in files)
        for file in files
            lines = readlines(file)
            abscissae = [
                String[m[1] for m in eachmatch(r"\"(\w+)\"", bracket.match)] for
                bracket in eachmatch(r"\[[^\[\]]*\]", key_comment(lines, "abscissa"))
            ]
            @test sort(abscissae) == sort(unique([ABSCISSAE; [String[]]]))
            ordinates =
                [m[1] for m in eachmatch(r"\"(\w+)\"", key_comment(lines, "ordinate"))]
            @test sort(ordinates) == sort(ORDINATES)
        end
    end

    @testset "the ordinate tables agree" begin
        ordinates = Set(keys(ExforFissionData.ORDINATE_RULES))
        @test Set(keys(ExforFissionData.ORDINATE_TOKEN)) == ordinates
        @test Set(keys(ExforFissionData.ORDINATE_QUANTITY)) == ordinates
        @test Set(ORDINATES) == ordinates
        # Every subset of the ordinates the source names is one.
        for subset in (
            ExforFissionData.GAMMA_ORDINATES,
            ExforFissionData.GAMMA_PER_FISSION_ORDINATES,
            keys(ExforFissionData.GAMMA_OBSERVABLES),
            ExforFissionData.RELATIVE_SCALE_ORDINATES,
            last.(ExforFissionData.RELATIVE_SCALE_OBSERVABLES),
            [last(observable) for observable in keys(ExforFissionData.OBSERVABLE_RULES)],
            ExforFissionData.ENERGY_ORDINATES,
            ExforFissionData.CENTRE_OF_MASS_ORDINATES,
            ExforFissionData.MULTIPLICITY_ORDINATES,
            ExforFissionData.EXTENSIVE_ORDINATES,
            keys(ExforFissionData.PARAMETER_ORDINATES),
            keys(ExforFissionData.PARAMETER_MEANINGS),
            (ExforFissionData.REFERENCE_RATIO_ORDINATE,),
            (ExforFissionData.MAXWELLIAN_RATIO_ORDINATE,),
            (ExforFissionData.DISTRIBUTION_ORDINATE,),
            (ExforFissionData.WIDTH_ORDINATE,),
            (ExforFissionData.PARAMETER_SOURCE_ORDINATE,),
        )
            @test issubset(subset, ordinates)
        end
    end

    @testset "a Query validates its fields" begin
        # The ten fields stated whole must agree with what the channel and ordinate derive.
        stated(; channel = "nth", reaction = "n,f", window = (0.0, 1.0e-7)) = Query(
            92,
            233,
            channel,
            reaction,
            "FY",
            ["mass"],
            "yield",
            window...,
            channel == "sf",
        )
        @test stated() isa Query
        @test_throws ArgumentError stated(; reaction = "0,f")
        @test_throws ArgumentError stated(; channel = "p,f")
        @test_throws ArgumentError stated(; window = (1.0e-7, 0.0))

        # The seven-argument form derives the reaction, the quantity and spontaneity.
        spontaneous = Query(98, 252, "sf", ["mass"], "multiplicity", 0.0, Inf)
        @test spontaneous.spontaneous
        @test spontaneous.reaction == "0,f"
        @test spontaneous.quantity == "NU"
        thermal = Query(92, 235, "nth", ["mass"], "yield", 0.0, 1.0e-7)
        @test !thermal.spontaneous
        @test thermal.reaction == "n,f"
        @test thermal.quantity == "FY"
    end

    @testset "a width configuration" begin
        base = """
        [query]
        target_Z = 94
        target_A = 239
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "total_kinetic_energy_dispersion"
        """
        entry(;
            subentry = "23012005",
            column = "MISC",
            holds = "hwhm",
            of = "total_kinetic_energy",
        ) = """
[[width]]
subentry = "$(subentry)"
column = "$(column)"
holds = "$(holds)"
of = "$(of)"
"""
        configuration = load_configuration_text(base * entry())
        @test only(configuration.widths) == ExforFissionData.WidthColumn(
            "23012005",
            "MISC",
            "hwhm",
            "total_kinetic_energy",
        )
        # The message of the refusal of the configuration `text`.
        refusal(text) = error_message(() -> load_configuration_text(text))
        # A mean is never read as a width, nor an uncertainty or a variable.
        for column in ("DATA", "DATA-ERR", "ERR-S", "MASS", "TKE")
            @test occursin("width", refusal(base * entry(; column = column)))
        end
        @test occursin("one of", refusal(base * entry(; holds = "rms")))
        @test occursin("one of", refusal(base * entry(; of = "TKE")))
        @test occursin("names none", refusal(base))
        @test occursin("twice", refusal(base * entry() * entry()))
        @test occursin(
            "alone",
            refusal(
                replace(base, "total_kinetic_energy_dispersion" => "total_kinetic_energy") *
                entry(),
            ),
        )
    end
end

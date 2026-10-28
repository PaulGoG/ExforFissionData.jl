# Readings of single datasets: correlation groups, preliminary and superseded results, a
# multiplicity derived from masses, and the curated tables themselves.

@testset "curation" begin
    @testset "two publications of one measurement" begin
        # 41516017 is superseded by 41597002, which publishes the same ratio inverted.
        group = ExforFissionData.correlation_group("41516017")
        @test group.members == ["41516017", "41597002"]
        @test ExforFissionData.correlation_group("41597002") === group
        @test occursin("SPSDD", group.reason)
    end

    @testset "one measurement in several datasets" begin
        group(identifier) = ExforFissionData.correlation_group(identifier)
        # Boldeman's distributions of 1967, superseded by the reanalysis of 1985, and one
        # 252-Cf(sf) measurement at three discriminator biases.
        @test group("30046008").members == ["30046008", "30772010"]
        @test group("307720152").members ==
              ["30046011", "307720151", "307720152", "307720153"]
        @test group("30772011").members == ["30046009", "30772011"]
        @test group("30046007").members == ["30046007", "30772009"]
        @test group("12833005") === nothing
        # The spectra of Starostov 1985, each in four parts: three detectors in the first
        # cycle, and the second cycle.
        @test group("40930011").members == ["40930004", "40930010", "40930011", "40930012"]
        @test group("40930006").members == ["40930006", "40930013", "40930014", "40930015"]
        @test group("40930018").members == ["40930008", "40930016", "40930017", "40930018"]
        @test occursin("COREL", group("40930018").reason)
        # The derived 252-Cf(sf) spectrum of the same entry is no part of them.
        @test group("40930002") === nothing
        # No dataset stands in two groups.
        @test allunique(
            reduce(vcat, [g.members for g in ExforFissionData.CORRELATION_GROUPS]),
        )
        # Every group says how its members are related, from a closed set.
        relations = ExforFissionData.CORRELATION_RELATIONS
        @test all(g -> g.relation in relations, ExforFissionData.CORRELATION_GROUPS)
        @test_throws ArgumentError ExforFissionData.CorrelationGroup(
            ["10000001", "10000002"],
            "duplicate",
            "no relation of the set",
        )
        @test group("400170093").relation == "repeated_run"
        @test group("30046008").relation == "republication"
        @test group("40930011").relation == "complementary_range"
        # Boldeman's four biases are four runs, by the fission numbers of the publication.
        @test group("307720152").relation == "repeated_run"
        @test occursin("doi:10.13182/NSE85-A17133", group("30046011").reason)
        # Basova 1979 and Zamyatnin 1979: two reductions of one measurement, for each system.
        @test group("41720002").members == ["41694002", "41720002"]
        @test group("41720004").members == ["41694003", "41720004"]
        @test group("41694003").relation == "alternative_analysis"
        written = ExforFissionData._curation_record("41720004")
        @test written["correlated_with"] == ["41694003"]
        @test written["correlation_relation"] == "alternative_analysis"
        # A republication is a superseded dataset and the one that supersedes it, in that order.
        for g in ExforFissionData.CORRELATION_GROUPS
            g.relation == "republication" || continue
            @test length(g.members) == 2
            @test ExforFissionData.SUPERSEDED_DATASETS[g.members[1]].by == g.members[2]
        end
        # The spectrum groups: selections of one set of events, parts of one spectrum by flight
        # path, detector or figure, and one spectrum measured at two flight paths.
        chalupka = group("222020052")
        @test length(chalupka.members) == 10
        @test chalupka.relation == "alternative_analysis"
        @test group("222020041") === chalupka
        @test group("40535004").members == ["40535002", "40535003", "40535004", "40535005"]
        for identifier in ("40535002", "14477003", "40064031", "40871014", "40871007")
            @test group(identifier).relation == "complementary_range"
        end
        @test group("40418005").members == ["40418004", "40418005"]
        @test group("40418004").relation == "repeated_run"
        # One member formed from another: 40418008 from 40418007, superseding 40418006, and
        # 30099003 from 30099002.
        @test group("40418007").members == ["40418006", "40418007", "40418008"]
        @test group("40418008").relation == "dependent"
        @test group("30099003").members == ["30099002", "30099003"]
        @test group("30099002").relation == "dependent"
        @test "dependent" in relations
    end

    @testset "results the archive marks preliminary" begin
        qualifier = ExforFissionData.preliminary_qualifier("41502008")
        @test startswith(qualifier, "preliminary: ")
        @test occursin("doi:10.1063/1.1945175", qualifier)
        # The flag belongs to the entry: its multiplicities carry it as its energies do.
        @test ExforFissionData.preliminary_qualifier("41502005") == qualifier
        @test ExforFissionData.preliminary_qualifier("41425014") === nothing
        @test endswith(qualifier, "and the entry carries STATUS PRELM")
        # The code alone flags: entry 41516 in its common subentry, 41516012 in its own too.
        preliminary_qualifier = ExforFissionData.preliminary_qualifier
        @test preliminary_qualifier("41516017") ==
              "preliminary: the entry carries STATUS (PRELM), 'Data are preliminary.'"
        @test startswith(
            preliminary_qualifier("41516012"),
            preliminary_qualifier("41516017"),
        )
        @test occursin(
            "; its subentry carries STATUS (PRELM)",
            preliminary_qualifier("41516012"),
        )
        # A subentry flags each of its pointers, and no other subentry of its entry.
        @test preliminary_qualifier("417380041") == preliminary_qualifier("417380042")
        @test startswith(
            preliminary_qualifier("417380041"),
            "preliminary: its subentry carries",
        )
        @test preliminary_qualifier("41738003") === nothing
        @test occursin("(OUTDT,40644002)", preliminary_qualifier("40644003"))
        @test preliminary_qualifier("40644002") === nothing
        @test preliminary_qualifier("41597002") === nothing

        # It is written among the qualifiers of the dataset, and never refuses it.
        query = test_query(;
            target_Z = 94,
            target_A = 239,
            abscissa = ["mass"],
            ordinate = "neutron_kinetic_energy",
        )
        rows = [
            exfor_row(;
                dataset_id = "41502009",
                reaction_code = "94-PU-239(N,F)MASS,PR,KE,N",
                value_kind = "Data(EV)",
                product_za = mass,
                y = value,
                incident_ev = 0.0253,
            ) for (mass, value) in ((97, 1.38e6), (101, 1.31e6))
        ]
        text = exfor_subentry(;
            entry = "41502",
            subentry = "41502009",
            bib = ["REACTION   (94-PU-239(N,F)MASS,PR,KE,N)"],
            common = (headings = ["EN-DUMMY"], units = ["EV"], values = [0.0253]),
            headings = ["MASS", "DATA"],
            units = ["NO-DIM", "MEV"],
            rows = [[97.0, 1.38], [101.0, 1.31]],
        )
        accepted = select_dataset("41502009", exfor_csv(rows), text, query)
        @test accepted isa Dataset
        @test qualifier in ExforFissionData._qualifiers(accepted)
        @test accepted.record["mean_formed_from"] == "unstated"
        @test accepted.record["mean_threshold_mev"] == 0.2
        @test occursin("Mannhart", accepted.record["mean_evidence"])
        # A mean whose threshold is settled carries no flag for it.
        @test !any(
            startswith("mean_threshold_unsettled:"),
            ExforFissionData._qualifiers(accepted),
        )
    end

    @testset "a multiplicity derived from fragment masses" begin
        # 23012008 (Nishio 1995): nu(m*) is the pre- minus the post-neutron mass of one
        # measurement of both velocities and energies. It is read by its code and flagged.
        qualifier = ExforFissionData.mass_difference_qualifier("23012008")
        @test startswith(qualifier, "multiplicity_from_masses: ")
        @test ExforFissionData.mass_difference_qualifier("22650004") === nothing
        record = ExforFissionData._curation_record("23012008")
        for passage in (
            "doi:10.1080/18811248.1995.9731725",
            "subtracting m from m*",
            "3.2 +- 0.1",
            "Eq. (17)",
        )
            @test occursin(passage, record["curation"])
        end
        # The passages stand beside the selection and take no part in it.
        for identifier in keys(ExforFissionData.MASS_DIFFERENCE_MULTIPLICITIES)
            @test !haskey(ExforFissionData.CURATED_DATASETS, identifier)
        end
        # Two reductions of one measurement may be combined as one; they never count as two.
        @test occursin(
            "never count both",
            ExforFissionData.correlation_group("41720002").reason,
        )
    end

    @testset "datasets a subentry marks superseded" begin
        superseded_qualifier = ExforFissionData.superseded_qualifier
        qualifier = superseded_qualifier("41516017")
        @test startswith(qualifier, "superseded: by 41597002")
        @test occursin("(SPSDD,41597002)", qualifier)
        # `correlated_with` reads alike on both of a pair; the qualifier is on one alone.
        @test superseded_qualifier("41597002") === nothing
        @test superseded_qualifier("30046011") === nothing
        # 40644003 is marked preliminary and outdated beside it, and the qualifier says so.
        @test endswith(
            superseded_qualifier("40644003"),
            "(SPSDD,40644002), beside (PRELM) and (OUTDT,40644002)",
        )
        # The absolute spectrum of 40875002 is superseded by one in arbitrary units.
        @test startswith(superseded_qualifier("40875002"), "superseded: by 41158002")
        # Each shares a correlation group with the dataset that supersedes it, and no other.
        for (identifier, superseded) in ExforFissionData.SUPERSEDED_DATASETS
            shared = ExforFissionData.correlation_group(identifier)
            @test superseded.by in shared.members
            # A pair is a republication, or dependent where the STATUS says the later is
            # formed from the earlier (41198002, DEP on 41179002); with a third member formed
            # from the same data the group is dependent.
            if length(shared.members) == 2
                @test shared.members == [identifier, superseded.by]
                @test shared.relation in ("republication", "dependent")
                shared.relation == "dependent" && @test occursin("DEP", shared.reason)
            else
                @test shared.relation == "dependent"
            end
        end
    end

    @testset "curated tables are disjoint" begin
        # `merge` lets a repeated identifier overwrite another in silence.
        individual = keys(ExforFissionData.INDIVIDUAL_READINGS)
        readings = keys(ExforFissionData.MULTIPLICITY_READINGS)
        @test !isempty(individual) && !isempty(readings)
        @test isdisjoint(individual, readings)
        @test length(ExforFissionData.CURATED_DATASETS) ==
              length(individual) + length(readings)
        # A prompt-γ curation and any other are never kept for one dataset.
        @test isdisjoint(
            keys(ExforFissionData.CURATED_DATASETS),
            keys(ExforFissionData.GAMMA_CURATIONS),
        )
    end
end

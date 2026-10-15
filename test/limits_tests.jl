# Rows coded as bounds or as approximate values, the reason of an empty rendering, a kinetic
# energy with a blank branch, the curated bound of 23175011, and the sum of yields.

@testset "rows coded as bounds and approximate values" begin
    query = test_query()
    code = "92-U-233(N,F)MASS,PRE,FY"
    # A bound leaves the table, listed with its value and place; an approximate value stays,
    # listed; the rows retrieved count both.
    rows = [
        exfor_row(;
            product_za = 100,
            y = 6.0,
            dy = 0.5,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
        exfor_row(;
            value_kind = "Max(PART/FIS)",
            product_za = 101,
            y = 0.5,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
        exfor_row(;
            value_kind = "Aprx(PART/FIS)",
            product_za = 102,
            y = 7.0,
            dy = 0.7,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
    ]
    dataset = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
    @test dataset isa Dataset
    @test dataset.record["rows_left_out"] ==
          ["Max(PART/FIS) 0.5, row 2 (ProdZA 101, incident 0.0253 eV)"]
    @test dataset.record["approximate_rows"] ==
          ["Aprx(PART/FIS) 7.0 ± 0.7, row 3 (ProdZA 102, incident 0.0253 eV)"]
    reduced = reduce_dataset(dataset, query)
    @test reduced.table[!, 1] == [100, 102]
    @test reduced.diagnostics["rows_retrieved"] == 3
    @test reduced.diagnostics["rows_written"] == 2
    # The record names the datasets concerned, with their counts.
    directory = mktempdir()
    config_path = joinpath(directory, "configuration.toml")
    write(
        config_path,
        """
        [query]
        target_Z = 92
        target_A = 233
        channel = "nth"
        abscissa = ["mass"]
        ordinate = "yield"
        """,
    )
    retrieved = DateTime(2026, 10, 15, 12)
    record_path = joinpath(directory, "retrieval.toml")
    write_metadata(
        record_path,
        load_configuration(config_path),
        [AcceptedDataset(dataset, reduced, "10000002.dat", retrieved, false)],
        Rejection[],
        ExforFissionData.Listing(["10000002"], retrieved, false),
    )
    record = TOML.parsefile(record_path)
    @test occursin("10000002 (1 row)", record["datasets"]["rows_left_out_warning"])
    @test occursin("10000002 (1 row)", record["datasets"]["approximate_warning"])

    # A two-sided bound leaves with the limits.
    rows = [
        exfor_row(; product_za = 100, y = 6.0, incident_ev = 0.0253, reaction_code = code),
        exfor_row(;
            value_kind = "Min2Max(PART/FIS)",
            product_za = 101,
            y = 0.5,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
    ]
    dataset = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
    @test dataset isa Dataset
    @test startswith(only(dataset.record["rows_left_out"]), "Min2Max(PART/FIS) 0.5")

    # A dataset of bounds alone is refused with the count of each kind.
    rows = [
        exfor_row(;
            value_kind = "Max(PART/FIS)",
            product_za = p,
            y = 0.5,
            incident_ev = 0.0253,
            reaction_code = code,
        ) for p in (100, 101)
    ]
    refused = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
    @test refused isa Rejection
    @test occursin("every row is a bound", refused.reason)
    @test occursin("2 Max(PART/FIS)", refused.reason)
    @test occursin("limit", refused.reason)

    # Value rows of two units cannot be one dataset; a kind this package does not read refuses it.
    rows = [
        exfor_row(; product_za = 100, y = 6.0, incident_ev = 0.0253, reaction_code = code),
        exfor_row(;
            value_kind = "Data(PC/FIS)",
            product_za = 101,
            y = 6.0,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
    ]
    refused = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
    @test refused isa Rejection
    @test occursin("different units", refused.reason)
    rows = [
        exfor_row(;
            value_kind = "Other(PART/FIS)",
            product_za = 100,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
    ]
    refused = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
    @test refused isa Rejection
    @test occursin("none this package reads", refused.reason)

    # A bound on one isomeric state beside a value of the other: the value is written as a
    # single state, and the record names the bound left out from both sides.
    charge_query = test_query(; abscissa = ["charge", "product_mass"], ordinate = "yield")
    code = "92-U-233(N,F)ELEM/MASS,IND,FY"
    rows = [
        exfor_row(;
            product_za = 54130,
            isomer = 0,
            y = 1.0,
            dy = 0.1,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
        exfor_row(;
            value_kind = "Max(PART/FIS)",
            product_za = 54130,
            isomer = 1,
            y = 0.1,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
        exfor_row(;
            product_za = 54131,
            y = 2.0,
            dy = 0.1,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
    ]
    dataset =
        select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), charge_query)
    @test dataset isa Dataset
    @test dataset.record["isomer_states_left_out"] == ["Xe-130"]
    @test occursin("ProdZA 54130, ProdM 1", only(dataset.record["rows_left_out"]))
    reduced = reduce_dataset(dataset, charge_query)
    @test reduced.diagnostics["isomer_single_state_nuclides"] ==
          ["Xe-130 (the other state a bound, left out)"]
end

@testset "the reason of an empty rendering" begin
    # The subentry says it holds no data.
    nodata = exfor_subentry(;
        entry = "30959",
        subentry = "30959002",
        bib = [
            "REACTION   (94-PU-239(N,F)MASS,CHN,FY,,MXW)",
            "STATUS     (NODATA) Data are identical to those in BARC-584.",
        ],
        headings = ["MASS", "DATA"],
        units = ["NO-DIM", "PC/FIS"],
        rows = [[100.0, 6.0]],
    )
    reason = ExforFissionData.empty_rendering_reason("30959002", nodata)
    @test startswith(
        reason,
        "dataset is empty: the subentry holds no data, STATUS (NODATA)",
    )
    @test occursin("BARC-584", reason)
    # The subentry holds a DATA table, so the rendering alone is empty.
    filled = exfor_subentry(;
        entry = "30959",
        subentry = "30959002",
        bib = [
            "REACTION   (94-PU-239(N,F)MASS,CHN,FY,,MXW)",
            "STATUS     (TABLE) Table 2.",
        ],
        headings = ["MASS", "DATA"],
        units = ["NO-DIM", "PC/FIS"],
        rows = [[100.0, 6.0], [101.0, 7.0]],
    )
    @test occursin(
        "although the subentry DATA table holds 2 lines",
        ExforFissionData.empty_rendering_reason("30959002", filled),
    )
    # The subentry holds no DATA table and does not say so.
    bare = replace(
        filled,
        r"^DATA .*?^ENDDATA[^\n]*\n"ms => "NODATA               0          0\n",
    )
    @test ExforFissionData.empty_rendering_reason("30959002", bare) ==
          "dataset is empty: the subentry holds no DATA table"
end

@testset "a kinetic energy with a blank branch" begin
    # 22985002 (Bail 2009): MASS,,KE,,MXW says neither PRE nor SEC; nothing is written for it.
    query = test_query(;
        target_Z = 94,
        target_A = 239,
        abscissa = ["product_mass"],
        ordinate = "product_kinetic_energy",
    )
    code = "94-PU-239(N,F)MASS,,KE,,MXW"
    rows = [
        exfor_row(;
            dataset_id = "22985002",
            value_kind = "Data(EV)",
            product_za = 130,
            y = 8.0e7,
            dy = 4.0e6,
            incident_ev = 0.0253,
            reaction_code = code,
        ),
    ]
    refused = select_dataset(
        "22985002",
        exfor_csv(rows),
        exfor_subentry_for(rows; unit = "EV"),
        query,
    )
    @test refused isa Rejection
    @test occursin("branch field SF5 is blank", refused.reason)
end

@testset "the TKE at which neutron emission stops is curated out" begin
    # 23175011 (Budtz-Jørgensen 1988): DATA-MAX alone, the bound of the TKE distribution per
    # mass, refused for what it is rather than as a dataset of limits.
    query = test_query(;
        target_Z = 98,
        target_A = 252,
        channel = "sf",
        abscissa = ["mass"],
        ordinate = "total_kinetic_energy",
    )
    rows = [
        exfor_row(;
            dataset_id = "23175011",
            value_kind = "Max(EV)",
            product_za = 83,
            y = 1.6615e8,
            dy = 4.12e6,
            reaction_code = "98-CF-252(0,F)MASS,,KE,LF+HF,MSC",
        ),
    ]
    refused = ExforFissionData.screen_dataset("23175011", exfor_csv(rows), query)
    @test refused isa Rejection
    @test occursin("neutron emission ceases", refused.reason)
    @test occursin("10.1016/0375-9474(88)90508-8", refused.reason)
end

@testset "the sum of yields is written without a binary tail" begin
    query = test_query()
    rows = [
        exfor_row(;
            product_za = 100 + i,
            y = v,
            incident_ev = 0.0253,
            reaction_code = "92-U-233(N,F)MASS,PRE,FY",
        ) for (i, v) in enumerate((0.1, 0.2, 0.7))
    ]
    dataset = select_dataset("10000002", exfor_csv(rows), exfor_subentry_for(rows), query)
    @test dataset isa Dataset
    @test reduce_dataset(dataset, query).diagnostics["yield_sum"] == 1.0
end

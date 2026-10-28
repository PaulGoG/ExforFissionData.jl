# The prompt-γ observables: rules, configuration, readings of the code, definitions, refusals and
# values stated outside the DATA tables.

@testset "prompt γ: the codes each ordinate admits" begin
    per_fission = tag_rule(String[], "gamma_multiplicity_per_fission")
    @test matches(per_fission, "98-CF-252(0,F)0-G-0,PR,FY")
    @test matches(per_fission, "98-CF-252(0,F)0-G-0,PR/PAR,FY")
    @test occursin("MSC", rejection_reason(per_fission, "98-CF-252(0,F)0-G-0,PR,FY,,MSC"))
    @test occursin("NUM", rejection_reason(per_fission, "98-CF-252(0,F)0-G-0,NUM,FY"))
    @test occursin("\"DE\"", rejection_reason(per_fission, "98-CF-252(0,F)0-G-0,PR,FY/DE"))
    @test occursin("RAW", rejection_reason(per_fission, "98-CF-252(0,F)0-G-0,PR,FY,,RAW"))
    # The γ codes stay refused for every other ordinate.
    @test occursin(
        "\"0-G-0\" in SF4",
        rejection_reason(tag_rule(["mass"], "yield"), "98-CF-252(0,F)0-G-0,PR,FY"),
    )
    @test occursin(
        "\"G\" in SF7",
        rejection_reason(
            tag_rule(["mass"], "multiplicity"),
            "98-CF-252(0,F)MASS,PRE/PR/FRG,NU,G",
        ),
    )
    @test matches(
        tag_rule(["mass"], "gamma_multiplicity"),
        "98-CF-252(0,F)MASS,PRE/PR/FRG,FY,G",
    )
    against_tke = tag_rule(["total_kinetic_energy"], "gamma_multiplicity_per_fission")
    @test matches(against_tke, "98-CF-252(0,F)0-G-0,PR,FY/TKE")
    @test occursin(
        "\"0-G-0\" in SF4",
        rejection_reason(against_tke, "98-CF-252(0,F),PR,FY/TKE"),
    )
    energy = tag_rule(String[], "gamma_energy_per_fission")
    @test matches(energy, "98-CF-252(0,F)0-G-0,PR,KE,,MSC")
    @test matches(energy, "92-U-235(N,F)0-G-0,PR/PAR,KE,,MXW")
end

@testset "prompt γ: configurations" begin
    configuration(abscissa, ordinate) = load_configuration_text("""
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = $(abscissa)
        ordinate = "$(ordinate)"
        """)
    @test observable_label(configuration("[]", "gamma_multiplicity_per_fission").query) ==
          "M_gamma_bar"
    @test observable_label(configuration("[]", "gamma_mean_energy").query) == "eps_gamma"
    @test observable_label(
        configuration("[\"neutron_number\"]", "gamma_energy_per_fission").query,
    ) == "E_gamma_tot_vs_nu"
    @test observable_label(configuration("[\"mass\"]", "gamma_mean_energy").query) ==
          "eps_gamma_vs_A"
    @test observable_label(configuration("[\"mass\"]", "gamma_multiplicity").query) ==
          "M_gamma_vs_A"
    @test occursin(
        "only the prompt-γ quantities per fission",
        error_message(() -> configuration("[]", "yield")),
    )
    @test occursin(
        "is retrieved against",
        error_message(() -> configuration("[\"charge\"]", "gamma_mean_energy")),
    )
    @test occursin(
        "is retrieved against",
        error_message(
            () -> configuration("[\"neutron_number\"]", "gamma_multiplicity_per_fission"),
        ),
    )
end

@testset "prompt γ: what an energy coded KE holds" begin
    reading = ExforFissionData.gamma_energy_reading
    total = reading("Total gammas energy.", [6.64])
    @test (total.reading, total.basis) == ("total_energy_per_fission", "REACTION text")
    mean = reading("Average gamma energy per gamma", [0.85])
    @test (mean.reading, mean.basis) == ("mean_photon_energy", "REACTION text")
    @test reading("Average gamma energy", [0.80]).basis == "REACTION text"
    @test reading("Average energy of single gamma.", [1.46]).reading == "mean_photon_energy"
    # Nothing in the words: the magnitude alone, recorded as such.
    bare = reading("", [6.7])
    @test (bare.reading, bare.basis) == ("total_energy_per_fission", "magnitude")
    @test reading(
        "Prompt gamma emission average energy for binary and ternary LRA fission.",
        [7.0],
    ).basis == "magnitude"
    # Words naming one quantity over values of the other refuse the dataset.
    @test occursin("names the total", reading("Total gamma energy", [0.85]))
    @test occursin("lie in neither", reading("", [2.9]))

    # The words of the reaction of a pointer.
    text = exfor_subentry(;
        bib = [
            "REACTION  1(98-CF-252(0,F)0-G-0,PR/PAR,FY)",
            "            Prompt fission gamma-ray multiplicity",
            "          2(98-CF-252(0,F)0-G-0,PR/PAR,KE)",
            "            Average gamma energy",
        ],
        headings = ["DATA", "DATA"],
        units = ["PRT/FIS", "MEV"],
        pointers = ['1', '2'],
        rows = [[8.28, 0.80]],
    )
    @test ExforFissionData.reaction_text(text, "100000021") ==
          "Prompt fission gamma-ray multiplicity"
    @test ExforFissionData.reaction_text(text, "100000022") == "Average gamma energy"
end

@testset "prompt γ: a quantity per fission and its definition" begin
    query = cf252_query(; abscissa = String[], ordinate = "gamma_multiplicity_per_fission")
    code = "98-CF-252(0,F)0-G-0,PR/PAR,FY"
    row(y, dy) = exfor_row(;
        reaction_code = code,
        value_kind = "Data(PART/FIS)",
        y,
        dy,
        product_za = 0,
    )
    text(rows; extra = String[]) = exfor_subentry(;
        bib = vcat(
            ["REACTION   ($(code))", "            Prompt fission gamma-ray multiplicity"],
            extra,
        ),
        common = (
            headings = ["E-MIN", "E-MAX"],
            units = ["MEV", "MEV"],
            values = [0.1, 7.2],
        ),
        headings = ["DATA", "DATA-ERR", "FLAG"],
        units = ["PRT/FIS", "PRT/FIS", "NO-DIM"],
        rows,
    )
    dataset = select_dataset(
        "10000002",
        exfor_csv([row(8.28, 0.08)]),
        text([[8.28, 0.08, 1.0]]),
        query,
    )
    @test dataset isa Dataset
    @test dataset.record["gamma_energy_min_mev"] == 0.1
    @test dataset.record["gamma_energy_max_mev"] == 7.2
    @test dataset.record["gamma_energy_range_basis"] == "entry"
    @test dataset.record["gamma_range_partial"]
    @test !dataset.record["gamma_range_limited"]
    @test dataset.record["time_window_basis"] == "unstated"
    @test ExforFissionData.gamma_definition_unstated(dataset.record) == ["window"]
    reduced = reduce_dataset(dataset, query)
    @test isempty(reduced.abscissa_columns)
    @test reduced.table.M_gamma_bar == [8.28]
    path = joinpath(mktempdir(), "10000002.dat")
    write_dataset(path, reduced)
    @test readlines(path) == ["M_gamma_bar M_gamma_bar_uncertainty", "8.28 0.08"]

    # Two values, two detectors of one experiment: refused with both, not combined.
    two = select_dataset(
        "10000002",
        exfor_csv([row(8.30, 0.15), row(8.60, 0.19)]),
        text([[8.30, 0.15, 1.0], [8.60, 0.19, 2.0]]),
        query,
    )
    @test two isa Rejection
    @test occursin("8.3 ± 0.15, 8.6 ± 0.19", two.reason)

    # Fragment groups and X-rays are refused by curation, with the group's value.
    group = ExforFissionData.gamma_refusal(
        "14214023",
        "98-CF-252(0,F)0-G-0,PR,FY,,MXW/MSC",
        4.82,
        0.9,
        "PART/FIS",
    )
    @test occursin("light fragment group, 4.82 ± 0.9 PART/FIS", group)
    @test occursin(
        "K X-rays",
        ExforFissionData.gamma_refusal("330710041", "", 0.145, 0.002, "PART/FIS"),
    )
    @test ExforFissionData.gamma_refusal("10000002", code, 8.28, 0.08, "PART/FIS") ===
          nothing
end

@testset "prompt γ: a window stated in the subentry text" begin
    # 14735 (Deutsch 1944): the window is in METHOD, read with its place.
    query = test_query(;
        target_Z = 92,
        target_A = 235,
        abscissa = String[],
        ordinate = "gamma_energy_per_fission",
    )
    code = "92-U-235(N,F)0-G-0,PR,KE,,MSC"
    csv = exfor_csv([
        exfor_row(;
            dataset_id = "14735002",
            reaction_code = code,
            value_kind = "Data(EV)",
            y = 5.1e6,
            dy = 3.0e5,
            incident_ev = 0.0253,
            product_za = 0,
        ),
    ])
    text(method) = exfor_subentry(;
        entry = "14735",
        subentry = "14735002",
        bib = vcat(
            [
                "REACTION   ($(code))",
                "            The total energy of the gamma rays per fission.",
            ],
            method,
        ),
        common = (headings = ["EN"], units = ["EV"], values = [0.0253]),
        headings = ["DATA", "DATA-ERR"],
        units = ["MEV", "MEV"],
        rows = [[5.1, 0.3]],
    )
    stated = [
        "METHOD     The gamma rays investigated, i.e., these emitted",
        "           within less than 2 microseconds of the fission process",
    ]
    dataset = select_dataset("14735002", csv, text(stated), query)
    @test dataset isa Dataset
    @test dataset.record["time_window_ns"] == [0.0, 2000.0]
    @test dataset.record["time_window_basis"] == "subentry text"
    @test occursin("subentry 14735002, METHOD", dataset.record["time_window_evidence"])
    @test dataset.record["quantity_reading"] == "total_energy_per_fission"
    @test dataset.record["quantity_reading_basis"] == "REACTION text"
    @test occursin("EN 0.0253 EV", dataset.record["incident_energy_basis"])
    # The incident energy is written without a binary tail.
    @test occursin("2.53e-8 MeV", dataset.record["incident_energy_basis"])
    @test reduce_dataset(dataset, query).diagnostics["incident_energies_mev"] == [2.53e-8]
    # A statement the text no longer holds refuses the dataset until it is reviewed.
    gone = select_dataset("14735002", csv, text(["METHOD     Geiger counters."]), query)
    @test gone isa Rejection
    @test occursin("must be reviewed", gone.reason)
    # The total is not the mean photon energy.
    mean_query = test_query(;
        target_Z = 92,
        target_A = 235,
        abscissa = String[],
        ordinate = "gamma_mean_energy",
    )
    wrong = select_dataset("14735002", csv, text(stated), mean_query)
    @test wrong isa Rejection
    @test occursin("holds the total energy per fission", wrong.reason)
end

@testset "prompt γ: a value stated outside the DATA table" begin
    query = test_query(;
        target_Z = 92,
        target_A = 235,
        abscissa = String[],
        ordinate = "gamma_energy_per_fission",
    )
    # 23541005 (Makii 2019): the total over 1 to 6 MeV, in the ADD-RES of the subentry.
    value = only(v for v in ExforFissionData.STATED_VALUES if v.source == "23541005")
    @test value in ExforFissionData.stated_values(query)
    text(words) = exfor_subentry(;
        entry = "23541",
        subentry = "23541005",
        bib = words,
        headings = ["E-MIN", "E-MAX", "DATA"],
        units = ["MEV", "MEV", "MEV"],
        rows = [[1.0, 6.0, 1.78]],
    )
    stated = ["ADD-RES    Average total gamma energy 4.07 +- 0.07 MeV"]
    dataset = ExforFissionData.stated_dataset(value, text(stated), query)
    @test dataset isa Dataset
    @test dataset.identifier == "23541005"
    @test occursin("subentry 23541005, ADD-RES", dataset.record["stated_value_evidence"])
    @test dataset.record["gamma_range_partial"]
    @test dataset.record["gamma_energy_range_basis"] == "entry"
    reduced = reduce_dataset(dataset, query)
    @test reduced.table.E_gamma_tot ≈ [4.07] rtol = 1.0e-9
    @test reduced.table.E_gamma_tot_uncertainty ≈ [0.07] rtol = 1.0e-9
    # Words the text no longer holds, or that do not state the value, refuse it.
    @test ExforFissionData.stated_dataset(value, text(["ADD-RES    none"]), query) isa
          Rejection
    fields = Any[getfield(value, name) for name in fieldnames(ExforFissionData.StatedValue)]
    fields[findfirst(==(:value), fieldnames(ExforFissionData.StatedValue))] = 4.08
    misread = ExforFissionData.StatedValue(fields...)
    refused = ExforFissionData.stated_dataset(misread, text(stated), query)
    @test refused isa Rejection
    @test occursin("do not state", refused.reason)
end

@testset "prompt γ: an incident energy the rendering misstates" begin
    # 31729 (Oberstedt 2013): KT-K 100 K of a cold beam, rendered as 100 eV.
    query = test_query(;
        target_Z = 92,
        target_A = 235,
        abscissa = String[],
        ordinate = "gamma_multiplicity_per_fission",
    )
    csv = exfor_csv([
        exfor_row(;
            dataset_id = "317290071",
            reaction_code = "92-U-235(N,F)0-G-0,PR/PAR,FY,,MXW",
            value_kind = "Data(PART/FIS)",
            y = 8.25,
            dy = 0.17,
            incident_ev = 100.0,
            product_za = 0,
        ),
    ])
    screened = ExforFissionData.screen_dataset("317290071", csv, query)
    @test screened isa ExforFissionData.Screened
    @test isapprox(
        only(screened.table[!, ExforFissionData.COL_INCIDENT_ENERGY]),
        8.617333262e-3;
        rtol = 1.0e-9,
    )
    other = ExforFissionData.screen_dataset(
        "10000002",
        replace(csv, "317290071" => "10000002"),
        query,
    )
    @test other isa Rejection
    @test occursin("outside the window", other.reason)
end

@testset "prompt γ: against fragment mass, by name, and kept in reasons" begin
    # The photon is named against a mass: the mean energy of the prompt neutrons of a
    # fragment is no mean photon energy.
    against_mass = tag_rule(["mass"], "gamma_mean_energy")
    @test occursin(
        "\"G\" in SF7",
        rejection_reason(against_mass, "98-CF-252(0,F)MASS,PRE/PR,KE,N"),
    )
    @test matches(
        tag_rule(["mass"], "gamma_multiplicity_per_fission"),
        "92-U-235(N,F)MASS,PR,FY,G,MXW",
    )
    # Skarsvag 1970 comes in by name under MLT, for the multiplicity per fission alone.
    per_fission =
        cf252_query(; abscissa = String[], ordinate = "gamma_multiplicity_per_fission")
    @test ExforFissionData.named_listing(per_fission) == ("MLT", ["23174004"])
    against_tke = cf252_query(;
        abscissa = ["total_kinetic_energy"],
        ordinate = "gamma_multiplicity_per_fission",
    )
    @test ExforFissionData.named_listing(against_tke) === nothing
    # A value in a MISC column without an uncertainty is kept in a reason, with its words.
    energy = cf252_query(; abscissa = String[], ordinate = "gamma_energy_per_fission")
    smith = only(
        v for v in ExforFissionData.unadmitted_values(energy) if v.identifier == "14320004"
    )
    text(misc) = exfor_subentry(;
        entry = "14320",
        subentry = "14320004",
        bib = [
            "REACTION   (98-CF-252(0,F)0-G-0,PR,FY) Photon emission in",
            "MISC-COL   Total energy loss in photons from Table 2.",
        ],
        headings = ["DATA", "MISC"],
        units = ["PRT/FIS", "MEV"],
        rows = [[10.3, misc]],
    )
    note = ExforFissionData.unadmitted_note(smith, text(8.2))
    @test occursin("8.2 MEV in its column MISC", note)
    @test occursin("subentry 14320004, MISC-COL", note)
    @test occursin("must be reviewed", ExforFissionData.unadmitted_note(smith, text(8.3)))
    # A row note is recorded with the dataset, the row uncurated.
    @test occursin(
        "A = 82",
        only(ExforFissionData._curation_record("14197005")["row_notes"]),
    )
end

@testset "prompt γ: ranges that limit the photons counted; windows of publications" begin
    # 41580 (Sokol 1991): the 320 to 5120 keV of the DETECTOR text are a threshold and a ceiling
    # of the detection; the set is written and named in gamma_range_warning with its range.
    query = cf252_query(; abscissa = String[], ordinate = "gamma_multiplicity_per_fission")
    code = "98-CF-252(0,F)0-G-0,PR,FY"
    csv = exfor_csv([
        exfor_row(;
            dataset_id = "41580003",
            reaction_code = code,
            value_kind = "Data(PART/FIS)",
            y = 6.58,
            dy = 0.4,
            product_za = 0,
        ),
    ])
    text = exfor_subentry(;
        entry = "41580",
        subentry = "41580003",
        bib = [
            "REACTION   ($(code))",
            "            Average gamma multiplicity per one spontaneous fission.",
            "DETECTOR   (GE) Gamma-quanta were registered in",
            "           energy range of 320 - 5120 keV during 4 microsec",
            "            after FF registration.",
        ],
        headings = ["DATA", "DATA-ERR"],
        units = ["PRT/FIS", "PRT/FIS"],
        rows = [[6.58, 0.4]],
    )
    dataset = select_dataset("41580003", csv, text, query)
    @test dataset isa Dataset
    @test dataset.record["gamma_energy_min_mev"] == 0.32
    @test dataset.record["gamma_energy_max_mev"] == 5.12
    @test dataset.record["gamma_energy_range_basis"] == "subentry text"
    @test dataset.record["gamma_range_limited"]
    @test !dataset.record["gamma_range_partial"]
    @test dataset.record["time_window_ns"] == [0.0, 4000.0]
    directory = mktempdir()
    config_path = joinpath(directory, "configuration.toml")
    write(
        config_path,
        """
        [query]
        target_Z = 98
        target_A = 252
        channel = "sf"
        abscissa = []
        ordinate = "gamma_multiplicity_per_fission"
        """,
    )
    retrieved = DateTime(2026, 10, 15, 12)
    record_path = joinpath(directory, "retrieval.toml")
    write_metadata(
        record_path,
        load_configuration(config_path),
        [
            AcceptedDataset(
                dataset,
                reduce_dataset(dataset, query),
                "41580003.dat",
                retrieved,
                false,
            ),
        ],
        Rejection[],
        ExforFissionData.Listing(["41580003"], retrieved, false),
    )
    record = TOML.parsefile(record_path)
    @test occursin(
        "41580003 (0.32 to 5.12 MeV, stated range)",
        record["datasets"]["gamma_range_warning"],
    )
    @test only(record["accepted"])["gamma_range_limited"]

    # 23659 (Wright 2024): the range of the abstract, its threshold forced by the γ-flash.
    wright = ExforFissionData.gamma_definition(
        "23659003",
        "92-U-235(N,F)0-G-0,PR,KE",
        nothing,
        "",
    )
    @test wright["gamma_energy_min_mev"] == 0.8
    @test wright["gamma_energy_max_mev"] == 6.8
    @test wright["gamma_energy_range_basis"] == "publication"
    @test occursin("10.1140/epja/s10050-024-01277-8", wright["gamma_energy_range_evidence"])
    @test wright["gamma_range_limited"]

    # Pleasonton 1973: the window of the 233-U and 239-Pu sets of 14214; the 252-Cf sets stay
    # unstated, and the 235-U sets keep the abstract of 1972.
    for identifier in
        ("14214002", "14214003", "14214026", "14214006", "14214007", "14214028")
        definition = ExforFissionData.gamma_definition(identifier, "", nothing, "")
        @test definition["time_window_ns"] == [0.0, 5.0]
        @test definition["time_window_basis"] == "publication"
        @test occursin("10.1016/0375-9474(73)90161-9", definition["time_window_evidence"])
    end
    @test ExforFissionData.gamma_definition("14214008", "", nothing, "")["time_window_basis"] ==
          "unstated"
    @test occursin(
        "10.1103/PhysRevC.6.1023",
        ExforFissionData.gamma_definition("14214004", "", nothing, "")["time_window_evidence"],
    )

    # 31778 (Gatera 2017): the ±3 ns gate of the publication defines the value; the 300 ns
    # trigger of the entry is recorded beside it.
    gatera = ExforFissionData.gamma_definition(
        "31778002",
        "",
        nothing,
        exfor_subentry(;
            entry = "31778",
            subentry = "31778002",
            bib = [
                "DETECTOR   (SCIN) Three LaBr3:Ce. The detectors response",
                "            functions simulated with GEANT4.",
                "METHOD     (COINC) The system was triggered whenever a gamma ray",
                "            was detected within a window of 300 ns following the",
                "            fission trigger.",
            ],
        ),
    )
    @test gatera["time_window_ns"] == [-3.0, 3.0]
    @test gatera["time_window_kind"] == "prompt gate"
    @test gatera["time_window_basis"] == "publication"
    @test occursin("±3 ns around zero", gatera["time_window_evidence"])
    @test gatera["acquisition_window_ns"] == [0.0, 300.0]
    @test occursin("subentry 31778002, METHOD", gatera["acquisition_window_evidence"])

    # 23197 (Oberstedt 2015): the gate of its four detectors, not of the two of Billnert 2013
    # nor of their average.
    gate(identifier) = any(
        s ->
            s.quantity == :window &&
            s.basis == "publication" &&
            (s.low, s.high) == (-3.0, 3.0),
        ExforFissionData.gamma_statements(identifier),
    )
    @test all(gate, ("231970051", "231970063", "231970072", "231970081"))
    @test !any(gate, ("231970021", "231970033", "231970091"))

    # Skarsvag 1970 is cited by DOI.
    @test occursin(
        "doi:10.1016/0375-9474(70)90757-8",
        ExforFissionData.GAMMA_CURATIONS["23174004"].reason,
    )

    # Incident energies are written without a binary tail.
    @test ExforFissionData.energy_mev_from_ev(0.0253) == 2.53e-8
    @test string(ExforFissionData.energy_mev_from_ev(0.0363)) == "3.63e-8"
    @test string(ExforFissionData.energy_mev_from_ev(8.617333262e-3)) == "8.617333262e-9"
end

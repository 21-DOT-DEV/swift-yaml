import Testing
import Foundation
import YAML

// YAML 1.2.2 spec conformance — the 28 worked examples of the specification's
// overview chapter (Chapter 2, yaml.org/spec/1.2.2/#chapter-2-language-overview),
// decoded through `YAMLDecoder` and checked against their specified meaning.
// This pins the library's real 1.2 support surface: which spec constructs decode
// correctly, and — in one place (the plan's deviation manifest) — where we differ.
//
// Each example's YAML is transcribed inline as a verbatim multi-line raw literal
// (`#"""…"""#`), so the test mirrors the spec's own layout — indentation and all.
// Where an example has a natural JSON twin, `agree` cross-checks the YAML result
// against Foundation's `JSONDecoder` on the equivalent JSON — an independent
// witness that never touches the YAML engine. Divergences are split by cause:
// multi-document input decodes the first document only (an intended, documented
// contract), and two genuine gaps are strict `withKnownIssue`s that flag if fixed.
@Suite struct SpecConformance {

    // MARK: - Models (shared across examples that share a shape)

    struct StatsRBI: Codable, Equatable { let hr: Int; let avg: Double; let rbi: Int }
    struct Stats: Codable, Equatable { let hr: Int; let avg: Double }
    struct Player: Codable, Equatable { let name: String; let hr: Int; let avg: Double }
    struct Teams: Codable, Equatable { let american: [String]; let national: [String] }
    struct Rankings: Codable, Equatable { let hr: [String]; let rbi: [String] }
    struct Item: Codable, Equatable { let item: String; let quantity: Int }
    struct Scoped: Codable, Equatable { let name: String; let accomplishment: String; let stats: String }
    struct Flow2: Codable, Equatable { let plain: String; let quoted: String }
    struct Misc: Codable, Equatable { let booleans: [Bool]; let string: String }
    struct PBP: Codable, Equatable { let time: String; let player: String; let action: String }
    struct Log: Codable, Equatable { let Time: String; let User: String; let Warning: String }
    struct StrTags: Codable, Equatable {
        let notDate: String; let appTag: String
        enum CodingKeys: String, CodingKey { case notDate = "not-date"; case appTag = "application specific tag" }
    }
    struct Pic: Codable, Equatable { let picture: Data }
    struct Point: Codable, Equatable { let x: Int; let y: Int }
    struct Shape: Codable, Equatable {
        let center: Point?; let radius: Int?; let start: Point?
        let finish: Point?; let color: Int?; let text: String?
    }
    struct Address: Codable, Equatable { let lines: String; let city: String; let state: String; let postal: Int }
    struct Addr: Codable, Equatable { let given: String; let family: String; let address: Address }
    struct Prod: Codable, Equatable { let sku: String; let quantity: Int; let description: String; let price: Double }
    struct Invoice: Codable, Equatable {
        let invoice: Int; let date: String; let billTo: Addr; let shipTo: Addr
        let product: [Prod]; let tax: Double; let total: Double; let comments: String
        enum CodingKeys: String, CodingKey {
            case invoice, date, billTo = "bill-to", shipTo = "ship-to", product, tax, total, comments
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ yaml: String) throws -> T {
        try YAMLDecoder().decode(type, from: yaml)
    }

    /// Independent cross-check: the YAML decode must equal the `JSONDecoder`
    /// decode of the equivalent JSON — a witness that never touches the YAML engine.
    private func agree<T: Decodable & Equatable>(_ type: T.Type, yaml: String, json: String) throws {
        let fromYAML = try YAMLDecoder().decode(type, from: yaml)
        let fromJSON = try JSONDecoder().decode(type, from: Data(json.utf8))
        #expect(fromYAML == fromJSON)
    }

    // MARK: - Clean — collections (cross-checked against JSONDecoder)

    /// 2.1 Sequence of Scalars (a list of strings).
    @Test func example_2_01_sequenceOfScalars() throws {
        try agree([String].self,
            yaml: #"""
            - Mark McGwire
            - Sammy Sosa
            - Ken Griffey
            """#,
            json: #"["Mark McGwire","Sammy Sosa","Ken Griffey"]"#)
    }

    /// 2.2 Mapping Scalars to Scalars (typed stats + trailing comments).
    @Test func example_2_02_mappingScalarsToScalars() throws {
        try agree(StatsRBI.self,
            yaml: #"""
            hr:  65    # Home runs
            avg: 0.278 # Batting average
            rbi: 147   # Runs Batted In
            """#,
            json: #"{"hr":65,"avg":0.278,"rbi":147}"#)
    }

    /// 2.3 Mapping Scalars to Sequences (key → list).
    @Test func example_2_03_mappingScalarsToSequences() throws {
        try agree(Teams.self,
            yaml: #"""
            american:
              - Boston Red Sox
              - Detroit Tigers
              - New York Yankees
            national:
              - New York Mets
              - Chicago Cubs
              - Atlanta Braves
            """#,
            json: #"{"american":["Boston Red Sox","Detroit Tigers","New York Yankees"],"national":["New York Mets","Chicago Cubs","Atlanta Braves"]}"#)
    }

    /// 2.4 Sequence of Mappings (list of records).
    @Test func example_2_04_sequenceOfMappings() throws {
        try agree([Player].self,
            yaml: #"""
            -
              name: Mark McGwire
              hr:   65
              avg:  0.278
            -
              name: Sammy Sosa
              hr:   63
              avg:  0.288
            """#,
            json: #"[{"name":"Mark McGwire","hr":65,"avg":0.278},{"name":"Sammy Sosa","hr":63,"avg":0.288}]"#)
    }

    /// 2.5 Sequence of Sequences (flow rows of mixed types). Decoded cell-by-cell
    /// as text (`[[String]]`): a heterogeneous row isn't expressible as one typed
    /// Swift value, so reading every cell as its source text is the faithful choice.
    @Test func example_2_05_sequenceOfSequences() throws {
        try agree([[String]].self,
            yaml: #"""
            - [name        , hr, avg  ]
            - [Mark McGwire, 65, 0.278]
            - [Sammy Sosa  , 63, 0.288]
            """#,
            json: #"[["name","hr","avg"],["Mark McGwire","65","0.278"],["Sammy Sosa","63","0.288"]]"#)
    }

    /// 2.6 Mapping of Mappings (flow maps as values, spanning lines).
    @Test func example_2_06_mappingOfMappings() throws {
        try agree([String: Stats].self,
            yaml: #"""
            Mark McGwire: {hr: 65, avg: 0.278}
            Sammy Sosa: {
                hr: 63,
                avg: 0.288,
              }
            """#,
            json: #"{"Mark McGwire":{"hr":65,"avg":0.278},"Sammy Sosa":{"hr":63,"avg":0.288}}"#)
    }

    /// 2.9 Single Document with Two Comments (`---`, comments, block sequences).
    @Test func example_2_09_twoComments() throws {
        try agree(Rankings.self,
            yaml: #"""
            ---
            hr: # 1998 hr ranking
              - Mark McGwire
              - Sammy Sosa
            rbi:
              # 1998 rbi ranking
              - Sammy Sosa
              - Ken Griffey
            """#,
            json: #"{"hr":["Mark McGwire","Sammy Sosa"],"rbi":["Sammy Sosa","Ken Griffey"]}"#)
    }

    /// 2.10 Node Anchors and References — the aliased node (`*SS`) expands to the
    /// anchored value (`&SS Sammy Sosa`) on decode.
    @Test func example_2_10_anchorsAndReferences() throws {
        try agree(Rankings.self,
            yaml: #"""
            ---
            hr:
            - Mark McGwire
            # Following node labeled SS
            - &SS Sammy Sosa
            rbi:
            - *SS # Subsequent occurrence
            - Ken Griffey
            """#,
            json: #"{"hr":["Mark McGwire","Sammy Sosa"],"rbi":["Sammy Sosa","Ken Griffey"]}"#)
    }

    /// 2.12 Compact Nested Mapping (list of single-line records).
    @Test func example_2_12_compactNestedMapping() throws {
        try agree([Item].self,
            yaml: #"""
            ---
            # Products purchased
            - item    : Super Hoop
              quantity: 1
            - item    : Basketball
              quantity: 4
            - item    : Big Shoes
              quantity: 1
            """#,
            json: #"[{"item":"Super Hoop","quantity":1},{"item":"Basketball","quantity":4},{"item":"Big Shoes","quantity":1}]"#)
    }

    /// 2.19 Integers — canonical/decimal/`0o` octal/`0x` hex all resolve (yaml-cpp
    /// 0.6.2 honors YAML-1.2 `0o` octal: `0o14` → 12, `0xC` → 12).
    @Test func example_2_19_integers() throws {
        try agree([String: Int].self,
            yaml: #"""
            canonical: 12345
            decimal: +12345
            octal: 0o14
            hexadecimal: 0xC
            """#,
            json: #"{"canonical":12345,"decimal":12345,"octal":12,"hexadecimal":12}"#)
    }

    /// 2.21 Miscellaneous — booleans and a leading-zero string (the `null:` key,
    /// whose value is null, is not part of the model and is ignored).
    @Test func example_2_21_miscellaneous() throws {
        try agree(Misc.self,
            yaml: #"""
            null:
            booleans: [ true, false ]
            string: 012345
            """#,
            json: #"{"booleans":[true,false],"string":"012345"}"#)
    }

    /// 2.25 Unordered Sets — `!!set` is, per the spec, "a mapping where each key is
    /// associated with a null value"; that is exactly `[String: String?]` with nils.
    @Test func example_2_25_unorderedSets() throws {
        try agree([String: String?].self,
            yaml: #"""
            --- !!set
            ? Mark McGwire
            ? Sammy Sosa
            ? Ken Griffey
            """#,
            json: #"{"Mark McGwire":null,"Sammy Sosa":null,"Ken Griffey":null}"#)
    }

    /// 2.26 Ordered Mappings — `!!omap` is, per the spec, "a sequence of mappings,
    /// each having one key"; that is exactly `[[String: Int]]`.
    @Test func example_2_26_orderedMappings() throws {
        try agree([[String: Int]].self,
            yaml: #"""
            --- !!omap
            - Mark McGwire: 65
            - Sammy Sosa: 63
            - Ken Griffey: 58
            """#,
            json: #"[{"Mark McGwire":65},{"Sammy Sosa":63},{"Ken Griffey":58}]"#)
    }

    // MARK: - Clean — scalars, block & flow styles (hand-written expected values;
    //         no clean JSON twin — root scalars, non-JSON floats, tags, dates)

    /// 2.13 Literal block scalar (`|`) at document root — newlines are preserved.
    @Test func example_2_13_literalBlockScalar() throws {
        let s = try decode(String.self, #"""
        # ASCII Art
        --- |
          \//||\/||
          // ||  ||__
        """#)
        #expect(s == "\\//||\\/||\n// ||  ||__")
    }

    /// 2.14 Folded scalar (`>`) at document root — newlines fold to spaces.
    @Test func example_2_14_foldedScalar() throws {
        let s = try decode(String.self, #"""
        --- >
          Mark McGwire's
          year was crippled
          by a knee injury.
        """#)
        #expect(s == "Mark McGwire's year was crippled by a knee injury.")
    }

    /// 2.15 Folded scalar — more-indented and blank lines keep their newlines.
    @Test func example_2_15_foldedNewlinesPreserved() throws {
        let s = try decode(String.self, #"""
        --- >
         Sammy Sosa completed another
         fine season with great stats.

           63 Home Runs
           0.288 Batting Average

         What a year!
        """#)
        #expect(s == "Sammy Sosa completed another fine season with great stats.\n\n  63 Home Runs\n  0.288 Batting Average\n\nWhat a year!")
    }

    /// 2.16 Indentation determines scope — a plain scalar beside folded (`>`) and
    /// literal (`|`) block-scalar values.
    @Test func example_2_16_indentationScope() throws {
        let v = try decode(Scoped.self, #"""
        name: Mark McGwire
        accomplishment: >
          Mark set a major league
          home run record in 1998.
        stats: |
          65 Home Runs
          0.278 Batting Average
        """#)
        #expect(v.name == "Mark McGwire")
        #expect(v.accomplishment == "Mark set a major league home run record in 1998.\n")
        #expect(v.stats == "65 Home Runs\n0.278 Batting Average")
    }

    /// 2.17 Quoted Scalars — single/double quotes with escapes; the `''` escape and
    /// an embedded `#` are handled.
    @Test func example_2_17_quotedScalars() throws {
        let v = try decode([String: String].self, #"""
        unicode: "Sosa did fine.☺"
        control: "\b1998\t1999\t2000\n"
        hex esc: "\x0d\x0a is \r\n"

        single: '"Howdy!" he cried.'
        quoted: ' # Not a ''comment''.'
        tie-fighter: '|\-*-/|'
        """#)
        #expect(v["single"] == "\"Howdy!\" he cried.")
        #expect(v["quoted"] == " # Not a 'comment'.")
        #expect(v["tie-fighter"] == "|\\-*-/|")
        #expect(v["unicode"] == "Sosa did fine.\u{263A}")
    }

    /// 2.18 Multi-line Flow Scalars — a plain and a double-quoted scalar each
    /// spanning several lines (line breaks fold to spaces).
    @Test func example_2_18_multiLineFlowScalars() throws {
        let v = try decode(Flow2.self, #"""
        plain:
          This unquoted scalar
          spans many lines.

        quoted: "So does this
          quoted scalar.\n"
        """#)
        #expect(v.plain == "This unquoted scalar spans many lines.")
        #expect(v.quoted == "So does this quoted scalar.\n")
    }

    /// 2.20 Floating Point — including `-.inf` and `.nan`, which the default decoder
    /// resolves (and which have no JSON equivalent, so no JSON twin).
    @Test func example_2_20_floatingPoint() throws {
        let v = try decode([String: Double].self, #"""
        canonical: 1.23015e+3
        exponential: 12.3015e+02
        fixed: 1230.15
        negative infinity: -.inf
        not a number: .nan
        """#)
        #expect(v["canonical"] == 1230.15)
        #expect(v["exponential"] == 1230.15)
        #expect(v["fixed"] == 1230.15)
        #expect(v["negative infinity"] == -.infinity)
        #expect(v["not a number"]?.isNaN == true)
    }

    /// 2.22 Timestamps — read as their source text. YAML 1.2's core schema resolves
    /// timestamps as strings; native `Date` typing is a separate future feature.
    @Test func example_2_22_timestampsAsCoreSchemaStrings() throws {
        let v = try decode([String: String].self, #"""
        canonical: 2001-12-15T02:59:43.1Z
        iso8601: 2001-12-14t21:59:43.10-05:00
        spaced: 2001-12-14 21:59:43.10 -5
        date: 2002-12-14
        """#)
        #expect(v["canonical"] == "2001-12-15T02:59:43.1Z")
        #expect(v["date"] == "2002-12-14")
        #expect(v["spaced"] == "2001-12-14 21:59:43.10 -5")
    }

    /// 2.24 Global Tags — `%TAG`/local tags (`!shape`, `!circle`, …) are ignored on
    /// decode; anchors (`&ORIGIN`/`*ORIGIN`) expand; the structure decodes cleanly.
    @Test func example_2_24_globalTags() throws {
        let s = try decode([Shape].self, #"""
        %TAG ! tag:clarkevans.com,2002:
        --- !shape
        - !circle
          center: &ORIGIN {x: 73, y: 129}
          radius: 7
        - !line
          start: *ORIGIN
          finish: { x: 89, y: 102 }
        - !label
          start: *ORIGIN
          color: 0xFFEEBB
          text: Center
        """#)
        #expect(s.count == 3)
        #expect(s[0].center == Point(x: 73, y: 129))
        #expect(s[0].radius == 7)
        #expect(s[1].start == Point(x: 73, y: 129))          // *ORIGIN alias expanded
        #expect(s[1].finish == Point(x: 89, y: 102))
        #expect(s[2].color == 0xFFEEBB)
        #expect(s[2].text == "Center")
    }

    /// 2.27 Invoice — a rich realistic document: root tag ignored, an anchored
    /// address (`&id001`) reused via `*id001`, nested records, a literal block.
    @Test func example_2_27_invoice() throws {
        let v = try decode(Invoice.self, #"""
        --- !<tag:clarkevans.com,2002:invoice>
        invoice: 34843
        date   : 2001-01-23
        bill-to: &id001
            given  : Chris
            family : Dumars
            address:
                lines: |
                    458 Walkman Dr.
                    Suite #292
                city    : Royal Oak
                state   : MI
                postal  : 48046
        ship-to: *id001
        product:
            - sku         : BL394D
              quantity    : 4
              description : Basketball
              price       : 450.00
            - sku         : BL4438H
              quantity    : 1
              description : Super Hooper
              price       : 2392.00
        tax  : 251.42
        total: 4443.52
        comments:
            Late afternoon is best.
            Backup contact is Nancy
            Billsmer @ 338-4338.
        """#)
        #expect(v.invoice == 34843)
        #expect(v.date == "2001-01-23")
        #expect(v.billTo.given == "Chris")
        #expect(v.shipTo.address.city == "Royal Oak")        // *id001 alias expanded
        #expect(v.product.count == 2)
        #expect(v.product[0].price == 450.00)
        #expect(v.total == 4443.52)
    }

    // MARK: - Intended behavior — first-document-only (multi-document streams)
    //
    // `YAMLDecoder.decode` reads only the first document of a `---`-separated
    // stream (a documented v1 contract; a decode-all entry point is future work).
    // These assert that first-document value — a characterization of intended
    // behavior, recorded in the plan's deviation manifest.

    /// 2.7 Two Documents in a Stream — only the first (the home-run ranking) decodes.
    @Test func example_2_07_twoDocumentsFirstOnly() throws {
        let v = try decode([String].self, #"""
        # Ranking of 1998 home runs
        ---
        - Mark McGwire
        - Sammy Sosa
        - Ken Griffey

        # Team ranking
        ---
        - Chicago Cubs
        - St Louis Cardinals
        """#)
        #expect(v == ["Mark McGwire", "Sammy Sosa", "Ken Griffey"])   // first document only
    }

    /// 2.8 Play-by-Play Feed — only the first play decodes; the rest are ignored.
    @Test func example_2_08_playByPlayFirstOnly() throws {
        let v = try decode(PBP.self, #"""
        ---
        time: 20:03:20
        player: Sammy Sosa
        action: strike (miss)
        ...
        ---
        time: 20:03:47
        player: Sammy Sosa
        action: grand slam
        ...
        """#)
        #expect(v == PBP(time: "20:03:20", player: "Sammy Sosa", action: "strike (miss)"))   // first document only
    }

    /// 2.28 Log File — only the first log entry decodes.
    @Test func example_2_28_logFileFirstOnly() throws {
        let v = try decode(Log.self, #"""
        ---
        Time: 2001-11-23 15:01:42 -5
        User: ed
        Warning:
          This is an error message
          for the log file
        ---
        Time: 2001-11-23 15:02:31 -5
        User: ed
        Warning:
          A slightly different error
          message.
        """#)
        #expect(v == Log(Time: "2001-11-23 15:01:42 -5", User: "ed", Warning: "This is an error message for the log file"))
    }

    // MARK: - Known gaps / limitations (strict `withKnownIssue` — flags if fixed)

    /// 2.11 Mapping between Sequences — the spec keys a mapping by *sequences*
    /// (`? [Detroit Tigers, Chicago cubs]`). `Codable` requires string keys, so the
    /// overlay collapses a non-string key to `""` (data loss). The string-typed part
    /// of the value still decodes; the key limitation is the known gap.
    @Test func example_2_11_sequenceKeysAreUnrepresentable() throws {
        withKnownIssue("2.11: sequence-valued mapping keys are not representable through Codable; the overlay collapses the key to \"\" (see plan §5.1)") {
            let v = try decode([String: [String]].self, #"""
            ? - Detroit Tigers
              - Chicago cubs
            : - 2001-07-23
            """#)
            #expect(v.keys.contains { !$0.isEmpty })   // expects the real key to survive — it does not
        }
    }

    /// 2.23 Various Explicit Tags — `!!str` and a custom `!local` tag decode as
    /// strings (clean); the multi-line `!!binary` value is the known gap: its
    /// base64 spans lines, which the strict `Data` decoder rejects.
    @Test func example_2_23_explicitTags() throws {
        let v = try decode(StrTags.self, #"""
        ---
        not-date: !!str 2002-04-28

        application specific tag: !something |
         The semantics of the tag
         above may be different for
         different documents.
        """#)
        #expect(v.notDate == "2002-04-28")                                   // !!str forces string, clean
        #expect(v.appTag.hasPrefix("The semantics of the tag"))             // custom tag body, clean

        withKnownIssue("2.23: multi-line !!binary content is not base64-decoded into Data — the strict decoder rejects the embedded line breaks (see plan §5.1)") {
            let p = try decode(Pic.self, #"""
            ---
            picture: !!binary |
             R0lGODlhDAAMAIQAAP//9/X
             17unp5WZmZgAAAOfn515eXv
             Pz7Y6OjuDg4J+fn5OTk6enp
             56enmleECcgggoBADs=
            """#)
            #expect(p.picture.count > 0)
        }
    }
}

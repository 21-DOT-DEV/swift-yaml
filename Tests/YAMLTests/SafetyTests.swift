import Testing
import YAML

// Each safe default declared in the proposal is proven here: a matching hostile
// input is rejected or bounded — never a hang, OOM, or crash.
@Suite struct Safety {

    // MARK: Alias-expansion ("billion laughs") bomb

    @Test func aliasBombIsRejectedByNodeBudget() throws {
        // Classic exponential alias expansion. yaml-cpp keeps the aliases shared,
        // so the budget trips while our walk materializes them — bounded work.
        let bomb = """
            a: &a ["lol","lol","lol","lol","lol","lol","lol","lol","lol","lol"]
            b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a,*a]
            c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b,*b]
            d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c,*c]
            e: &e [*d,*d,*d,*d,*d,*d,*d,*d,*d,*d]
            f: &f [*e,*e,*e,*e,*e,*e,*e,*e,*e,*e]
            g: [*f,*f,*f,*f,*f,*f,*f,*f,*f,*f]
            """
        let decoder = YAMLDecoder()
        decoder.documentLimits = YAMLDecoder.DocumentLimits(maxDepth: 512, maxNodeCount: 100_000, maxInputBytes: -1)
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode([String: [String]].self, from: bomb)
        }
    }

    @Test func aliasBombSurfacesDocumentTooComplex() throws {
        let bomb = """
            a: &a [x,x,x,x,x,x,x,x,x,x]
            b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a,*a]
            c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b,*b]
            d: [*c,*c,*c,*c,*c,*c,*c,*c,*c,*c]
            """
        let decoder = YAMLDecoder()
        decoder.documentLimits = YAMLDecoder.DocumentLimits(maxDepth: 512, maxNodeCount: 5_000, maxInputBytes: -1)
        do {
            _ = try decoder.decode([String: [String]].self, from: bomb)
            Issue.record("expected the alias bomb to be rejected")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.underlyingError is YAMLError)
        }
    }

    // MARK: Deep nesting (parser-stack DoS)

    @Test func deepFlowNestingIsRejectedBeforeParsing() throws {
        let depth = 5_000
        let deep = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let decoder = YAMLDecoder()  // default maxDepth 512
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode([String].self, from: deep)
        }
    }

    @Test func nestingWithinLimitIsAccepted() throws {
        let deep = String(repeating: "[", count: 10) + "1" + String(repeating: "]", count: 10)
        // 10 nested single-element arrays ending in 1.
        let decoder = YAMLDecoder()
        let value = try decoder.decode([[[[[[[[[[Int]]]]]]]]]].self, from: deep)
        #expect(value[0][0][0][0][0][0][0][0][0][0] == 1)
    }

    // MARK: Oversized input

    @Test func oversizedInputIsRejected() throws {
        let big = "key: " + String(repeating: "x", count: 1_000)
        let decoder = YAMLDecoder()
        decoder.documentLimits = YAMLDecoder.DocumentLimits(maxDepth: 512, maxNodeCount: -1, maxInputBytes: 100)
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode([String: String].self, from: big)
        }
    }

    // MARK: Malformed input → typed error with position

    @Test func malformedInputThrowsDataCorruptedWithPosition() throws {
        let decoder = YAMLDecoder()
        do {
            _ = try decoder.decode([String: String].self, from: "key: [unterminated")
            Issue.record("expected malformed YAML to throw")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.underlyingError is YAMLError)
            if case let .parse(_, line, _)? = context.underlyingError as? YAMLError {
                #expect(line >= 1)
            }
        }
    }

    @Test func unboundedLimitsAcceptWhatStrictBudgetRejects() throws {
        // Opt-out works: a wide document a low node budget rejects is accepted
        // under .unbounded. (Proven with node count, not deep nesting — feeding
        // genuinely choking input would be testing yaml-cpp's limits, not ours.)
        let wide = (0..<3_000).map { "- \($0)" }.joined(separator: "\n")

        let strict = YAMLDecoder()
        strict.documentLimits = YAMLDecoder.DocumentLimits(maxDepth: 128, maxNodeCount: 500, maxInputBytes: -1)
        #expect(throws: DecodingError.self) {
            _ = try strict.decode([Int].self, from: wide)
        }

        let lenient = YAMLDecoder()
        lenient.documentLimits = .unbounded
        #expect(try lenient.decode([Int].self, from: wide).count == 3_000)
    }
}

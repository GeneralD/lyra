import Dependencies
import Domain
import Testing

@testable import HealthHandler

@Suite("HealthHandlerImpl", .serialized)
struct HealthHandlerImplTests {
    // MARK: - Normal Behavior

    @Suite("normal behavior")
    struct NormalBehavior {
        @Test("all checkers pass → success with all entries")
        func allPass() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .pass),
                StubChecker(name: "B", status: .pass),
            ])
            guard case .success(let passed) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(passed.entries.count == 2)
        }

        @Test("all checkers fail → failure with all entries")
        func allFail() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .fail),
                StubChecker(name: "B", status: .fail),
            ])
            guard case .failure(let failed) = result else {
                Issue.record("Expected failure")
                return
            }
            #expect(failed.entries.count == 2)
            #expect(failed.failedCount == 2)
        }

        @Test("pass and fail mixed → failure")
        func mixed() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .pass),
                StubChecker(name: "B", status: .fail),
                StubChecker(name: "C", status: .pass),
            ])
            guard case .failure(let failed) = result else {
                Issue.record("Expected failure")
                return
            }
            #expect(failed.entries.count == 3)
            #expect(failed.failedCount == 1)
        }
    }

    // MARK: - Boundary Conditions

    @Suite("boundary conditions")
    struct BoundaryConditions {
        @Test("zero checkers → success with empty entries")
        func zeroCheckers() async {
            let result = await checkWith([])
            guard case .success(let passed) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(passed.entries.isEmpty)
        }

        @Test("single checker pass → success")
        func singlePass() async {
            let result = await checkWith([StubChecker(name: "A", status: .pass)])
            #expect((try? result.get()) != nil)
        }

        @Test("single checker fail → failure")
        func singleFail() async {
            let result = await checkWith([StubChecker(name: "A", status: .fail)])
            guard case .failure = result else {
                Issue.record("Expected failure")
                return
            }
        }

        @Test("skip only → success")
        func skipOnly() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .skip),
                StubChecker(name: "B", status: .skip),
            ])
            #expect((try? result.get()) != nil)
        }

        @Test("pass and skip mixed → success")
        func passAndSkip() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .pass),
                StubChecker(name: "B", status: .skip),
            ])
            #expect((try? result.get()) != nil)
        }
    }

    // MARK: - Invariants

    @Suite("invariants")
    struct Invariants {
        @Test("entries count equals checker count")
        func entriesCount() async {
            let checkers = (0..<5).map { StubChecker(name: "C\($0)", status: .pass) }
            let result = await checkWith(checkers)
            let entries: [HealthReportEntry]
            switch result {
            case .success(let p): entries = p.entries
            case .failure(let f): entries = f.entries
            }
            #expect(entries.count == 5)
        }

        @Test("entries preserve checker registration order")
        func entriesOrder() async {
            let names = ["Alpha", "Beta", "Gamma", "Delta"]
            let checkers = names.map { StubChecker(name: $0, status: .pass) }
            let result = await checkWith(checkers)
            guard case .success(let passed) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(passed.entries.map(\.serviceName) == names)
        }

        @Test("success entries contain no fail status")
        func successHasNoFail() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .pass),
                StubChecker(name: "B", status: .skip),
            ])
            guard case .success(let passed) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(passed.entries.allSatisfy { $0.result.status != .fail })
        }

        @Test("failure entries contain at least one fail status")
        func failureHasAtLeastOneFail() async {
            let result = await checkWith([
                StubChecker(name: "A", status: .pass),
                StubChecker(name: "B", status: .fail),
            ])
            guard case .failure(let failed) = result else {
                Issue.record("Expected failure")
                return
            }
            #expect(failed.entries.contains { $0.result.status == .fail })
        }
    }
}

// MARK: - Helpers

private struct StubChecker: HealthCheckable {
    let name: String
    let status: HealthCheckResult.Status

    var serviceName: String { name }
    func healthCheck() async -> HealthCheckResult {
        HealthCheckResult(status: status, detail: "\(name) detail")
    }
}

private func checkWith(_ checkers: [StubChecker]) async -> HealthCheckReport {
    await withDependencies {
        $0.healthCheckers = checkers
    } operation: {
        await HealthHandlerImpl().check()
    }
}

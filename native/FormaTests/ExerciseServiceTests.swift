import XCTest
@testable import Forma

final class ExerciseServiceTests: XCTestCase {
    private let catalog: [Exercise] = [
        Exercise(
            id: "push-up", name: "Push-Up", category: .strength,
            primaryMuscles: [.chest], secondaryMuscles: [.arms],
            equipment: [.bodyweight], difficulty: .beginner,
            instructions: [], cues: [], mistakes: [], alternatives: ["incline-push-up"],
            isUnilateral: false
        ),
        Exercise(
            id: "incline-push-up", name: "Incline Push-Up", category: .strength,
            primaryMuscles: [.chest], secondaryMuscles: [.arms],
            equipment: [.bench], difficulty: .beginner,
            instructions: [], cues: [], mistakes: [], alternatives: [],
            isUnilateral: false
        ),
        Exercise(
            id: "cable-row", name: "Cable Row", category: .strength,
            primaryMuscles: [.back], secondaryMuscles: [.arms],
            equipment: [.cable], difficulty: .intermediate,
            instructions: [], cues: [], mistakes: [], alternatives: [],
            isUnilateral: false
        ),
        Exercise(
            id: "hip-mobility", name: "90/90 Hip Switch", category: .mobility,
            primaryMuscles: [.hips], secondaryMuscles: [],
            equipment: [.bodyweight], difficulty: .beginner,
            instructions: [], cues: [], mistakes: [], alternatives: [],
            isUnilateral: true
        )
    ]

    func testSearchMatchesNamesCaseInsensitively() {
        let page = ExerciseService.search(catalog, filters: ExerciseFilters(query: "PUSH"))
        XCTAssertEqual(Set(page.items.map(\.id)), ["push-up", "incline-push-up"])
    }

    func testSearchMatchesMuscleAndEquipment() {
        let byMuscle = ExerciseService.search(catalog, filters: ExerciseFilters(query: "back"))
        XCTAssertEqual(byMuscle.items.map(\.id), ["cable-row"])
        let byEquipment = ExerciseService.search(catalog, filters: ExerciseFilters(query: "cable"))
        XCTAssertEqual(byEquipment.items.map(\.id), ["cable-row"])
    }

    func testCategoryAndMuscleFilters() {
        let mobility = ExerciseService.search(catalog, filters: ExerciseFilters(category: .mobility))
        XCTAssertEqual(mobility.total, 1)
        let chest = ExerciseService.search(catalog, filters: ExerciseFilters(muscle: .chest))
        XCTAssertEqual(chest.total, 2)
    }

    func testFavoritesFilter() {
        let page = ExerciseService.search(
            catalog,
            filters: ExerciseFilters(onlyFavorites: true, favoriteIDs: ["cable-row"])
        )
        XCTAssertEqual(page.items.map(\.id), ["cable-row"])
    }

    func testPaginationReportsTotalsAndHasMore() {
        let first = ExerciseService.search(catalog, filters: ExerciseFilters(), limit: 2)
        XCTAssertEqual(first.items.count, 2)
        XCTAssertEqual(first.total, 4)
        XCTAssertTrue(first.hasMore)

        let second = ExerciseService.search(catalog, filters: ExerciseFilters(), offset: 2, limit: 2)
        XCTAssertEqual(second.items.count, 2)
        XCTAssertFalse(second.hasMore)

        let empty = ExerciseService.search(catalog, filters: ExerciseFilters(), offset: 99)
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testEquipmentFilterKeepsBodyweightAccessible() {
        let benchOnly = ExerciseService.search(
            catalog,
            filters: ExerciseFilters(equipment: [.bench])
        )
        XCTAssertEqual(Set(benchOnly.items.map(\.id)), ["push-up", "incline-push-up", "hip-mobility"])
    }

    func testAlternativesResolveAgainstCatalog() {
        let exercise = catalog[0]
        XCTAssertEqual(ExerciseService.alternatives(for: exercise, in: catalog).map(\.id), ["incline-push-up"])
    }

    func testVerifiedIDsOnlyContainsCatalogEntries() {
        XCTAssertTrue(ExerciseService.isVerified("push-up", in: catalog))
        XCTAssertFalse(ExerciseService.isVerified("made-up-movement", in: catalog))
    }
}

import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
struct DataExportTests {
    let container: ModelContainer
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    private func water(_ ml: Int, deleted: Bool = false) {
        let entry = WaterEntry(id: UUID(), userID: userID, consumedOn: Day(now, timeZone: .gmt), amountMl: ml, updatedAt: now)
        if deleted { entry.deletedAt = now }
        context.insert(entry)
    }

    private func product(_ name: String, owner: UUID?) {
        context.insert(Product(id: UUID(), ownerID: owner, source: owner == nil ? "off" : "user", name: LocalizedText(["nl": name]), quantityUnit: "g", updatedAt: now))
    }

    private func table(_ name: String, in tables: [DataExport.Table]) -> DataExport.Table? {
        tables.first { $0.name == name }
    }

    @Test func exportsTheRowsOfTheSyncedTables() throws {
        water(250)
        water(500)
        try context.save()
        let tables = DataExport.tables(in: context)
        let rows = try #require(table("water_entries", in: tables)).rows
        #expect(rows.count == 2)
        #expect(Set(rows.compactMap { $0["amount_ml"] as? Int }) == [250, 500])
        #expect(rows.allSatisfy { $0["user_id"] as? String == userID.uuidString.lowercased() || $0["user_id"] as? String == userID.uuidString })
    }

    @Test func leavesOutDeletedRows() throws {
        water(250)
        water(500, deleted: true)
        try context.save()
        let rows = try #require(table("water_entries", in: DataExport.tables(in: context))).rows
        #expect(rows.compactMap { $0["amount_ml"] as? Int } == [250])
    }

    @Test func leavesOutSharedRowsOfTablesWithAnOwner() throws {
        product("Eigen granola", owner: userID)
        product("Halfvolle melk", owner: nil)
        try context.save()
        let rows = try #require(table("products", in: DataExport.tables(in: context))).rows
        #expect(rows.count == 1)
        #expect((rows.first?["name"] as? [String: String])?["nl"] == "Eigen granola")
    }

    @Test func leavesOutTablesWithoutRows() {
        #expect(DataExport.tables(in: context).isEmpty)
    }

    @Test func jsonHoldsTheExportDateAndEveryTable() throws {
        water(250)
        try context.save()
        let data = try DataExport.json(DataExport.tables(in: context), exportedAt: now)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["exported_at"] as? String == "2026-11-18T11:06:40Z")
        let tables = try #require(object["tables"] as? [String: Any])
        #expect((tables["water_entries"] as? [Any])?.count == 1)
    }

    @Test func csvHasOneHeaderAndQuotesWhatNeedsQuoting() {
        let table = DataExport.Table(name: "x", rows: [
            ["b": "say \"hi\"", "a": "1,2", "c": NSNull()],
            ["a": "line\nbreak", "d": 3, "e": ["nl": "melk"]],
        ])
        #expect(DataExport.csv(table) == """
        a,b,c,d,e\r
        "1,2","say ""hi""",,,\r
        "line
        break",,,3,"{""nl"":""melk""}"\r

        """)
    }

    @Test func writesOneJSONFileAndOneCSVPerTable() throws {
        water(250)
        product("Eigen granola", owner: userID)
        try context.save()
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let files = try DataExport.write(DataExport.tables(in: context), to: folder, exportedAt: now)
        #expect(files.map(\.lastPathComponent).sorted() == ["fitling-export.json", "products.csv", "water_entries.csv"])
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}

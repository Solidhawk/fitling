import Foundation
import SwiftData

/// All of the user's own data, as one JSON file and one CSV file per table (TASKS 7.3). The rows are
/// the same records that sync with the server, so the export covers every synced table and uses
/// the column names of the database. Deleted rows and shared rows (the product cache, the
/// built-in exercises and recipes) are left out.
@MainActor
enum DataExport {
    struct Table {
        let name: String
        /// One JSON object per row, as JSONSerialization gives it.
        let rows: [[String: Any]]
    }

    static let jsonFileName = "fitling-export.json"

    static func tables(in context: ModelContext) -> [Table] {
        SyncTables.all.compactMap { $0.export(in: context, encoder: encoder) }.filter { !$0.rows.isEmpty }
    }

    static func json(_ tables: [Table], exportedAt: Date) throws -> Data {
        var byName: [String: Any] = [:]
        for table in tables { byName[table.name] = table.rows }
        let object: [String: Any] = ["exported_at": exportedAt.formatted(.iso8601), "tables": byName]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// RFC 4180: a header with every column of the table, CRLF line ends, and quotes around a value
    /// with a comma, a quote or a line break. Nested values (a name in several languages) are JSON text.
    static func csv(_ table: Table) -> String {
        let columns = Set(table.rows.flatMap(\.keys)).sorted()
        var lines = [columns.map(field).joined(separator: ",")]
        for row in table.rows {
            lines.append(columns.map { field(text(row[$0])) }.joined(separator: ","))
        }
        return lines.map { $0 + "\r\n" }.joined()
    }

    /// Writes the JSON file and the CSV files into `folder` (made if needed) and returns them.
    static func write(_ tables: [Table], to folder: URL, exportedAt: Date) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jsonURL = folder.appending(path: jsonFileName)
        try json(tables, exportedAt: exportedAt).write(to: jsonURL, options: .atomic)
        var files = [jsonURL]
        for table in tables {
            let url = folder.appending(path: "\(table.name).csv")
            try Data(csv(table).utf8).write(to: url, options: .atomic)
            files.append(url)
        }
        return files
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func text(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: ""
        case let string as String: string
        case let number as NSNumber: number.stringValue
        case let nested?:
            (try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension ModelTable {
    func export(in context: ModelContext, encoder: JSONEncoder) -> DataExport.Table? {
        let models = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        let rows: [[String: Any]] = models.compactMap { model in
            guard model.deletedAt == nil,
                  let data = try? encoder.encode(model.record),
                  let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            if let owner = Model.ownerColumn, row[owner] == nil || row[owner] is NSNull { return nil }
            return row
        }
        return DataExport.Table(name: Model.tableName, rows: rows)
    }
}

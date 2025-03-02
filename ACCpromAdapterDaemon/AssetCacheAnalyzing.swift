//
//  AssetCacheAnalyzer.swift
//  ACCpromAdapterDaemon
//
//  Created by Christian Strube on 02.03.25.
//

import Foundation
import os
import SQLite3

protocol AssetCacheAnalyzing {
    func analyzeMetrics() -> Result<String, Error>
}

enum AssetCacheAnalyzerError: Error, LocalizedError {
    case fileNotReadable(String)
    case dbOpenError(String)
    case prepareError(String)
    case noData
    case noColumns
    
    var errorDescription: String? {
        switch self {
        case .fileNotReadable(let msg):
            return "Datei nicht lesbar: \(msg)"
        case .dbOpenError(let msg):
            return "Fehler beim Öffnen der Datenbank: \(msg)"
        case .prepareError(let msg):
            return "Fehler beim Vorbereiten des Statements: \(msg)"
        case .noData:
            return "Keine Daten in der Tabelle gefunden."
        case .noColumns:
            return "Keine Spalten in der Tabelle gefunden."
        }
    }
}

class AssetCacheAnalyzer: AssetCacheAnalyzing {
    private let logger: Logger
    
    // Fester Pfad zur Metrics.db – für den LaunchDaemon
    private let filePath = "/Library/Application Support/Apple/AssetCache/Metrics/Metrics.db"
    
    init(logger: Logger = Logger(subsystem: "de.cstrube.ACCpromAdapterDaemon", category: "AssetCacheAnalyzer")) {
        self.logger = logger
    }
    
    func analyzeMetrics() -> Result<String, Error> {
        logger.log("Starte Lesevorgang der Metrics.db")
        
        // Überprüfe, ob die Datei existiert und lesbar ist
        if !FileManager.default.isReadableFile(atPath: filePath) {
            logger.error("Datei \(self.filePath, privacy: .public) ist NICHT lesbar.")
            return .failure(AssetCacheAnalyzerError.fileNotReadable("Pfad: \(filePath)"))
        }
        logger.log("Datei \(self.filePath, privacy: .public) ist lesbar.")
        
        var db: OpaquePointer?
        if sqlite3_open(filePath, &db) != SQLITE_OK {
            let errMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unbekannter Fehler"
            logger.error("Fehler beim Öffnen der DB: \(errMsg, privacy: .public)")
            return .failure(AssetCacheAnalyzerError.dbOpenError(errMsg))
        }
        defer {
            sqlite3_close(db)
        }
        
        // Hole die Spaltennamen aus der Tabelle ZMETRIC per PRAGMA
        var pragmaStmt: OpaquePointer?
        let pragmaQuery = "PRAGMA table_info(ZMETRIC)"
        guard sqlite3_prepare_v2(db, pragmaQuery, -1, &pragmaStmt, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            logger.error("Fehler beim Vorbereiten des PRAGMA: \(errorMsg, privacy: .public)")
            sqlite3_close(db)
            return .failure(AssetCacheAnalyzerError.prepareError(errorMsg))
        }
        
        var columns = [String]()
        while sqlite3_step(pragmaStmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(pragmaStmt, 1) {
                let colName = String(cString: cString)
                columns.append(colName)
            }
        }
        sqlite3_finalize(pragmaStmt)
        
        guard !columns.isEmpty else {
            logger.error("Keine Spalten in der Tabelle gefunden.")
            return .failure(AssetCacheAnalyzerError.noColumns)
        }
        
        // Lese den neuesten Datensatz (basierend auf ZCREATIONDATE)
        let query = "SELECT " + columns.joined(separator: ", ") + " FROM ZMETRIC ORDER BY ZCREATIONDATE DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            logger.error("Fehler beim Vorbereiten des SELECT-Statements: \(errorMsg, privacy: .public)")
            sqlite3_close(db)
            return .failure(AssetCacheAnalyzerError.prepareError(errorMsg))
        }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            logger.error("Keine Daten in der Tabelle gefunden.")
            return .failure(AssetCacheAnalyzerError.noData)
        }
        
        // Erzeuge den vollständigen Prometheus-Output (inklusive HELP/TYPE Zeilen)
        var metricsLines = [String]()
        for (index, colName) in columns.enumerated() {
            let colType = sqlite3_column_type(stmt, Int32(index))
            var valueText = ""
            switch colType {
            case SQLITE_INTEGER:
                let intValue = sqlite3_column_int64(stmt, Int32(index))
                valueText = "\(intValue)"
            case SQLITE_FLOAT:
                let doubleValue = sqlite3_column_double(stmt, Int32(index))
                valueText = "\(doubleValue)"
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(stmt, Int32(index)) {
                    valueText = String(cString: text)
                }
            case SQLITE_NULL:
                valueText = "NaN"
            default:
                valueText = "NaN"
            }
            
            let trimmedKey = colName.trimmingCharacters(in: .whitespaces)
            let metricName = "acc_\(trimmedKey.lowercased().replacingOccurrences(of: " ", with: "_"))"
            let tokens = valueText.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let numericValue = tokens.first.map { String($0) } ?? valueText
            let unit = tokens.count >= 2 ? String(tokens[1]) : ""
            let helpText = unit.isEmpty ? trimmedKey : "\(trimmedKey) (Einheit: \(unit))"
            
            // Für boolesche Werte: true/false -> 1/0
            let finalValue: String
            if valueText.lowercased() == "true" {
                finalValue = "1"
            } else if valueText.lowercased() == "false" {
                finalValue = "0"
            } else {
                finalValue = numericValue
            }
            
            metricsLines.append("# HELP \(metricName) Metrik \(helpText)")
            metricsLines.append("# TYPE \(metricName) gauge")
            metricsLines.append("\(metricName) \(finalValue)")
        }
        
        sqlite3_finalize(stmt)
        let metrics = metricsLines.joined(separator: "\n")
        logger.log("Metriken aktualisiert")
        logger.log("Erzeugter Output: \(metrics, privacy: .public)")
        return .success(metrics)
    }
}

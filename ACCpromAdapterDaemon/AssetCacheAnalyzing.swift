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
    private let errorLogger: FileHandle?
    
    private let filePath = "/Library/Application Support/Apple/AssetCache/Metrics/Metrics.db"
    private let errorLogPath = "/var/log/ACCpromAdapterDaemon.err.log"
    
    init(logger: Logger = Logger(subsystem: "de.cstrube.ACCpromAdapterDaemon", category: "AssetCacheAnalyzer")) {
        self.logger = logger
        self.errorLogger = FileHandle(forWritingAtPath: errorLogPath)
    }
    
    func analyzeMetrics() -> Result<String, Error> {
        logger.log("Starte Lesevorgang der Metrics.db")
        
        if !FileManager.default.isReadableFile(atPath: filePath) {
            let error = "Datei \(filePath) ist NICHT lesbar."
            logError(error)
            return .failure(AssetCacheAnalyzerError.fileNotReadable(error))
        }
        logger.log("Datei \(self.filePath, privacy: .public) ist lesbar.")
        
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        
        if sqlite3_open(filePath, &db) != SQLITE_OK {
            let errMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unbekannter Fehler"
            logError("Fehler beim Öffnen der DB: \(errMsg)")
            return .failure(AssetCacheAnalyzerError.dbOpenError(errMsg))
        }
        
        var columns = [String]()
        do {
            columns = try fetchColumnNames(db: db)
        } catch {
            logError("Fehler beim Abrufen der Spalten: \(error.localizedDescription)")
            return .failure(error)
        }
        
        do {
            let metrics = try fetchLatestMetrics(db: db, columns: columns)
            logger.log("Metriken erfolgreich aktualisiert.")
            return .success(metrics)
        } catch {
            logError("Fehler beim Abrufen der Metriken: \(error.localizedDescription)")
            return .failure(error)
        }
    }
    
    private func fetchColumnNames(db: OpaquePointer?) throws -> [String] {
        var stmt: OpaquePointer?
        let query = "PRAGMA table_info(ZMETRIC)"
        
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw AssetCacheAnalyzerError.prepareError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        var columns = [String]()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let columnName = sqlite3_column_text(stmt, 1) {
                columns.append(String(cString: columnName))
            }
        }
        
        if columns.isEmpty {
            throw AssetCacheAnalyzerError.noColumns
        }
        return columns
    }
    
    private func fetchLatestMetrics(db: OpaquePointer?, columns: [String]) throws -> String {
        let query = "SELECT " + columns.joined(separator: ", ") + " FROM ZMETRIC ORDER BY ZCREATIONDATE DESC LIMIT 1"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw AssetCacheAnalyzerError.prepareError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw AssetCacheAnalyzerError.noData
        }
        
        var metricsLines = [String]()
        for (index, colName) in columns.enumerated() {
            let colType = sqlite3_column_type(stmt, Int32(index))
            var valueText = "NaN"
            
            switch colType {
            case SQLITE_INTEGER:
                valueText = "\(sqlite3_column_int64(stmt, Int32(index)))"
            case SQLITE_FLOAT:
                valueText = "\(sqlite3_column_double(stmt, Int32(index)))"
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(stmt, Int32(index)) {
                    valueText = String(cString: text)
                }
            case SQLITE_NULL:
                valueText = "NaN"
            default:
                valueText = "NaN"
            }
            
            let metricName = "acc_\(colName.lowercased().replacingOccurrences(of: " ", with: "_"))"
            metricsLines.append("# HELP \(metricName) \(colName)")
            metricsLines.append("# TYPE \(metricName) gauge")
            metricsLines.append("\(metricName) \(valueText)")
        }
        
        return metricsLines.joined(separator: "\n")
    }
    
    private func logError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        let logMessage = "\(Date()): \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            errorLogger?.seekToEndOfFile()
            errorLogger?.write(data)
        }
    }
}

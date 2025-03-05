//
//  PrometheusServer.swift
//  ACCpromAdapter
//
//  Created by Christian Strube on 01.03.25.
//

import Foundation
import NIO
import NIOHTTP1
import os

class PrometheusServer {
    static let shared = PrometheusServer(analyzer: AssetCacheAnalyzer())

    private let logger: Logger
    private let errorLogger: FileHandle?
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var isRunning = false
    private let analyzer: AssetCacheAnalyzing
    
    private let errorLogPath = "/var/log/ACCpromAdapterDaemon.err.log"

    init(analyzer: AssetCacheAnalyzing,
         logger: Logger = Logger(subsystem: "de.cstrube.ACCpromAdapterDaemon", category: "PrometheusServer")) {
        self.analyzer = analyzer
        self.logger = logger
        self.errorLogger = FileHandle(forWritingAtPath: errorLogPath)
    }

    func start(on port: Int = 9200) {
        guard !isRunning else {
            logger.log("Server läuft bereits.")
            return
        }

        logger.log("Starte Prometheus-Server auf Port \(port, privacy: .public)")
        isRunning = true
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        let bootstrap = ServerBootstrap(group: group!)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(logger: self.logger))
                }
            }
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            logger.log("Prometheus-Server läuft auf: \(String(describing: self.channel?.localAddress), privacy: .public)")
            try channel?.closeFuture.wait()
        } catch {
            logError("Fehler beim Starten des Servers: \(error.localizedDescription)")
            restartServer()
        }
    }

    func stop() {
        do {
            try channel?.close().wait()
            try group?.syncShutdownGracefully()
            isRunning = false
            logger.log("Prometheus-Server gestoppt.")
        } catch {
            logError("Fehler beim Stoppen des Servers: \(error.localizedDescription)")
        }
    }

    private func restartServer() {
        logError("Unerwarteter Absturz. Versuche Neustart in 5 Sekunden...")
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            self.start()
        }
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

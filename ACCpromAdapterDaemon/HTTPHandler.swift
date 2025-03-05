//
//  HTTPHandler.swift
//  ACCpromAdapterDaemon
//
//  Created by Christian Strube on 05.03.25.
//

import Foundation
import NIO
import NIOHTTP1
import os

final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let logger: Logger
    private var requestTimestamps: [String: Date] = [:] // Rate Limiting pro IP

    init(logger: Logger) {
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = unwrapInboundIn(data)
        switch reqPart {
        case .head(let request):
            guard request.method == .GET else {
                sendResponse(context: context, status: .methodNotAllowed, body: "405 Method Not Allowed")
                logSecurityIncident("Nicht erlaubte Methode: \(request.method)")
                return
            }

            if request.uri != "/metrics" {
                sendNotFound(context: context, request: request)
                return
            }

            if isRateLimited(request: request) {
                sendResponse(context: context, status: .tooManyRequests, body: "429 Too Many Requests")
                logSecurityIncident("Rate Limit erreicht für: \(request.headers["Host"].first ?? "Unbekannt")")
                return
            }

        case .body:
            break
        case .end:
            logger.log("Erhalte Anfrage für /metrics – starte direkte DB-Abfrage")
            let result = AssetCacheAnalyzer().analyzeMetrics()
            let (status, responseString): (HTTPResponseStatus, String)

            switch result {
            case .success(let output):
                status = .ok
                responseString = output
            case .failure:
                status = .internalServerError
                responseString = "Fehler beim Abrufen der Daten."
                logSecurityIncident("Datenbankzugriff fehlgeschlagen.")
            }

            sendResponse(context: context, status: status, body: responseString)
        }
    }

    private func sendNotFound(context: ChannelHandlerContext, request: HTTPRequestHead) {
        sendResponse(context: context, status: .notFound, body: "404 Not Found")
        logSecurityIncident("Unbekannte URL aufgerufen: \(request.uri)")
    }

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func isRateLimited(request: HTTPRequestHead) -> Bool {
        let ip = request.headers["Host"].first ?? "Unbekannt"
        let now = Date()

        if let lastRequest = requestTimestamps[ip], now.timeIntervalSince(lastRequest) < 1 {
            return true
        }

        requestTimestamps[ip] = now
        return false
    }

    private func logSecurityIncident(_ message: String) {
        logger.error("Sicherheitswarnung: \(message, privacy: .public)")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("HTTPHandler Fehler: \(error.localizedDescription, privacy: .public)")
        context.close(promise: nil)
    }
}

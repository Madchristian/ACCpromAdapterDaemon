//
//  main.swift
//  ACCpromAdapterDaemon
//
//  Created by Christian Strube on 02.03.25.
//

import Foundation
import os

// Erstelle einen Logger für den Daemon
let logger = Logger(subsystem: "de.cstrube.ACCpromAdapter", category: "LaunchDaemon")

logger.log("LaunchDaemon startet den PrometheusServer...")

// Starte den Prometheus-Server auf Port 9200
PrometheusServer.shared.start(on: 9200)

// Da der Server im aktuellen Thread blockiert (closeFuture.wait()),
// erreichst du hier normalerweise keinen Code. Falls du noch Aufräumarbeiten durchführen möchtest,
// kannst du diese nach dem Server-Stopp platzieren.

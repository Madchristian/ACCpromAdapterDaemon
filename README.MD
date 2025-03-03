# ACCpromAdapterDaemon

**ACCPromAdapterDaemon** is a headless macOS daemon that monitors Apple Content Cache metrics by reading the `Metrics.db` file and exposes the data via an HTTP endpoint in Prometheus format. This allows system administrators and DevOps teams to integrate cache monitoring into their dashboards (e.g. using Grafana) without requiring a user to be logged in.

## Features

- **Automated Monitoring:** Continuously reads metrics from the Apple Content Cache database.
- **Prometheus-Compatible Output:** Exposes metrics in a format that can be scraped by Prometheus.
- **Headless Operation:** Designed for environments without user interaction (e.g. headless Mac minis or servers).
- **Robust Logging:** Detailed logging using Apple’s os.Logger for easy debugging and monitoring.

## Technical Overview

- **Language:** Swift
- **Frameworks:** Swift Concurrency (`async/await`), Combine, SwiftNIO for the HTTP server, SQLite3 for database access.
- **Architecture:** The daemon checks for and reads the local `Metrics.db` file, parses the data into Prometheus metric format, and serves it on a configurable HTTP port (default is 9200).

## Installation

### Build

1. Open the Xcode project for ACCpromAdapterDaemon.
2. Select the **Release** build configuration.
3. Build the project. The resulting binary should be located in the **Products** directory.

### Packaging

An installation package (`.pkg`) can be generated using the provided shell script. For example:

```bash
./generatePackage.zsh
```

This script will:
    •    Create a staging directory.
    •    Copy the daemon binary to a designated installation folder (e.g. /usr/local/bin).
    •    Copy the LaunchDaemon property list to /Library/LaunchDaemons.
    •    Build a signed installer package (ACCpromAdapterDaemon.pkg).

Installation on a macOS System
    1.    Install the Package:
    •    Double-click the generated ACCpromAdapterDaemon.pkg to launch the Installer.
    •    Follow the on-screen instructions to install the daemon.
    2.    Load the Daemon:
    •    Open Terminal and run:

```bash
sudo launchctl load /Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist
sudo launchctl start de.cstrube.ACCpromAdapterDaemon
```

3.    Uninstallation:
    •    To remove the daemon, use:

```bash
sudo launchctl unload /Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist
sudo rm /Library/LaunchDaemons/de.cstrube.ACCpromAdapterDaemon.plist
sudo rm /usr/local/bin/ACCpromAdapterDaemon
```

or use the install_daemon.sh and uninstall_daemon.sh scripts provided in the release section

### Configuration
    •    HTTP Port: The daemon listens on port 9200 by default. This can be modified in the source code if needed.
    •    Metrics Database Path: The daemon expects the Metrics database to be located at:

/Library/Application Support/Apple/AssetCache/Metrics/Metrics.db

Ensure that this file is accessible by the daemon.

Usage

Once installed and running, the daemon will serve Prometheus-formatted metrics at:

http://localhost:9200/metrics

You can verify by opening this URL in your browser or configuring a Prometheus scraper to collect the metrics.

Logging and Debugging

The daemon uses Apple’s os.Logger to log important events and errors. These logs can be viewed using the Console.app:
    •    Look for logs under the subsystem de.cstrube.ACCpromAdapterDaemon.
    •    Common log messages include startup, successful metric updates, and error messages if the Metrics.db cannot be read.
```bash
log stream --predicate 'subsystem == "de.cstrube.ACCpromAdapterDaemon"' --info
```

or
```bash
log stream --predicate 'subsystem == "de.cstrube.ACCpromAdapterDaemon" AND eventType == logEvent' --debug
```

Troubleshooting
    •    No Metrics Output: Verify that the Metrics.db file exists and is readable by the daemon.
    •    Port Conflicts: If port 9200 is already in use, either free the port or change the listening port in the source code.
    •    Permissions Issues: Ensure that the daemon is running with the necessary permissions to read /Library/Application Support/Apple/AssetCache/Metrics/Metrics.db.

Contributing

Contributions are welcome! Please fork this repository and submit your pull requests with detailed descriptions of your changes.

License

This project is licensed under the MIT License. See the LICENSE file for details.

For any issues or feature requests, please open an issue on GitHub.

Happy Monitoring!

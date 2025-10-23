# MicAssignBridge

`MicAssignBridge` is a lightweight Swift command-line utility that polls Shure QLXD, ULXD, and Axient receivers for channel telemetry and forwards the data to [micassign.com](https://micassign.com) for display on mic boards.

## Features

- Polls one or more receivers on the local network by IP address.
- Extracts channel name, RF level, and battery details from the receiver JSON telemetry endpoints.
- Batches the collected data and forwards it to the micassign.com ingestion endpoint.
- Minimal footprint and no external dependencies beyond the Swift runtime.

## Building

```bash
swift build -c release --product MicAssignBridge
```

The resulting binary is located at `.build/release/MicAssignBridge` and can be distributed directly to macOS users.

## Usage

```bash
MicAssignBridge --ips 192.168.1.100,192.168.1.101 \
  --micassign-url https://micassign.com/api/integrations/shure \
  --api-key YOUR_TOKEN \
  --interval 5
```

### Command-line flags

| Flag | Description |
| --- | --- |
| `--ips` | Comma-separated list of receiver IP addresses. Required. |
| `--micassign-url` | Optional override of the ingestion endpoint. Falls back to the `MICASSIGN_API_URL` environment variable or `https://micassign.com/api/integrations/shure`. |
| `--api-key` | Optional API key header value (or `MICASSIGN_API_KEY` environment variable). |
| `--interval` | Poll frequency in seconds. Default: `5`. |
| `--timeout` | Timeout in seconds for each receiver HTTP request. Default: `3`. |

### Environment variables

- `MICASSIGN_API_URL` – Default ingestion endpoint.
- `MICASSIGN_API_KEY` – API key header value.

### Example launch agent

To keep the bridge running on macOS, create a LaunchAgent file (`~/Library/LaunchAgents/com.micassign.bridge.plist`) with contents similar to:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.micassign.bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/MicAssignBridge</string>
        <string>--ips</string>
        <string>192.168.1.100,192.168.1.101</string>
        <string>--interval</string>
        <string>5</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>MICASSIGN_API_KEY</key>
        <string>YOUR_TOKEN</string>
        <key>MICASSIGN_API_URL</key>
        <string>https://micassign.com/api/integrations/shure</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Load the agent with:

```bash
launchctl load ~/Library/LaunchAgents/com.micassign.bridge.plist
```

This approach provides a hands-off installation for end users.

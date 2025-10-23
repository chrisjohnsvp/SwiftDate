import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Dispatch
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct MicAssignBridge {
    static func main() async {
        do {
            let arguments = CommandLine.arguments.dropFirst()
            let configuration = try AppConfigurationParser().parse(arguments: Array(arguments))
            let runner = BridgeRunner(configuration: configuration)
            try await runner.run()
        } catch let error as ConfigurationError {
            fputs("Configuration error: \(error.description)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        } catch {
            fputs("Unexpected error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

struct AppConfiguration {
    let receiverIPs: [String]
    let micAssignURL: URL
    let apiKey: String?
    let pollInterval: TimeInterval
    let timeout: TimeInterval
}

final class AppConfigurationParser {
    func parse(arguments: [String]) throws -> AppConfiguration {
        var ips: [String] = []
        var micAssignURL: URL?
        var apiKey: String? = ProcessInfo.processInfo.environment["MICASSIGN_API_KEY"]
        var pollInterval: TimeInterval = 5
        var timeout: TimeInterval = 3

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--ips":
                guard let value = iterator.next() else { throw ConfigurationError.missingValue(flag: "--ips") }
                ips = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            case "--micassign-url":
                guard let value = iterator.next() else { throw ConfigurationError.missingValue(flag: "--micassign-url") }
                micAssignURL = URL(string: value)
            case "--api-key":
                guard let value = iterator.next() else { throw ConfigurationError.missingValue(flag: "--api-key") }
                apiKey = value
            case "--interval":
                guard let value = iterator.next(), let parsed = TimeInterval(value) else {
                    throw ConfigurationError.invalidNumber(flag: "--interval")
                }
                pollInterval = parsed
            case "--timeout":
                guard let value = iterator.next(), let parsed = TimeInterval(value) else {
                    throw ConfigurationError.invalidNumber(flag: "--timeout")
                }
                timeout = parsed
            case "--help", "-h":
                print(AppConfigurationParser.helpText)
                Foundation.exit(EXIT_SUCCESS)
            default:
                throw ConfigurationError.unknownFlag(argument)
            }
        }

        if ips.isEmpty {
            throw ConfigurationError.missingReceivers
        }

        let resolvedMicAssignURL: URL
        if let explicitURL = micAssignURL {
            resolvedMicAssignURL = explicitURL
        } else if let environmentURL = ProcessInfo.processInfo.environment["MICASSIGN_API_URL"], let url = URL(string: environmentURL) {
            resolvedMicAssignURL = url
        } else if let url = URL(string: "https://micassign.com/api/integrations/shure") {
            resolvedMicAssignURL = url
        } else {
            throw ConfigurationError.invalidURL("https://micassign.com/api/integrations/shure")
        }

        return AppConfiguration(
            receiverIPs: ips,
            micAssignURL: resolvedMicAssignURL,
            apiKey: apiKey,
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    static var helpText: String {
        """
        MicAssignBridge
        ----------------
        Bridge Shure receiver telemetry to micassign.com.

        Usage:
          MicAssignBridge --ips 192.168.1.10,192.168.1.12 [options]

        Options:
          --micassign-url <url>   Destination endpoint (defaults to MICASSIGN_API_URL env or https://micassign.com/api/integrations/shure)
          --api-key <key>         API key header value (or MICASSIGN_API_KEY env)
          --interval <seconds>    Poll interval in seconds (default: 5)
          --timeout <seconds>     HTTP timeout for device queries (default: 3)
          -h, --help              Show this help message
        """
    }
}

enum ConfigurationError: Error {
    case missingReceivers
    case missingValue(flag: String)
    case invalidNumber(flag: String)
    case invalidURL(String)
    case unknownFlag(String)

    var description: String {
        switch self {
        case .missingReceivers:
            return "Provide at least one IP address via --ips."
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidNumber(let flag):
            return "Invalid numeric value supplied to \(flag)."
        case .invalidURL(let urlString):
            return "Unable to construct URL from \(urlString)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag)."
        }
    }
}

final class BridgeRunner {
    private let configuration: AppConfiguration
    private let session: URLSession
    private let micAssignSender: MicAssignSender

    init(configuration: AppConfiguration) {
        self.configuration = configuration

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
        sessionConfiguration.timeoutIntervalForResource = configuration.timeout
#if !os(Linux)
        sessionConfiguration.waitsForConnectivity = true
#endif
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: sessionConfiguration)
        self.micAssignSender = MicAssignSender(endpoint: configuration.micAssignURL, apiKey: configuration.apiKey, session: session)
    }

    func run() async throws {
        let cancellationHandler = CancellationHandler()
        cancellationHandler.trapSignals()

        await withTaskGroup(of: Void.self) { group in
            for ip in configuration.receiverIPs {
                group.addTask {
                    let client = ShureReceiverClient(ipAddress: ip, session: self.session)
                    let poller = ReceiverPoller(client: client, sender: self.micAssignSender, pollInterval: self.configuration.pollInterval)
                    await poller.start()
                }
            }
        }
    }
}

final class CancellationHandler {
    private var signalSources: [DispatchSourceSignal] = []

    func trapSignals() {
        let signals: [Int32] = [SIGINT, SIGTERM]
        for sig in signals {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                print("Received termination signal. Exiting…")
                Foundation.exit(EXIT_SUCCESS)
            }
            signal(sig, SIG_IGN)
            source.resume()
            signalSources.append(source)
        }
    }
}

final class ReceiverPoller {
    private let client: ShureReceiverClient
    private let sender: MicAssignSender
    private let pollInterval: TimeInterval

    init(client: ShureReceiverClient, sender: MicAssignSender, pollInterval: TimeInterval) {
        self.client = client
        self.sender = sender
        self.pollInterval = pollInterval
    }

    func start() async {
        while true {
            do {
                let reports = try await client.fetchChannelReports()
                if !reports.isEmpty {
                    try await sender.send(reports: reports)
                }
            } catch {
                fputs("Polling error for \(client.ipAddress): \(error.localizedDescription)\n", stderr)
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                return
            }
        }
    }
}

struct MicAssignSender {
    let endpoint: URL
    let apiKey: String?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let dateFormatter: ISO8601DateFormatter

    init(endpoint: URL, apiKey: String?, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder
        self.dateFormatter = ISO8601DateFormatter()
    }

    func send(reports: [ChannelReport]) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let payload = MicAssignPayload(timestamp: dateFormatter.string(from: Date()), receivers: reports.groupedByReceiver())
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw MicAssignSendError.invalidStatusCode(httpResponse.statusCode)
        }
    }
}

enum MicAssignSendError: Error {
    case invalidStatusCode(Int)
}

struct MicAssignPayload: Encodable {
    let timestamp: String
    let receivers: [Receiver]

    struct Receiver: Encodable {
        let name: String
        let channels: [Channel]
    }

    struct Channel: Encodable {
        let channelName: String
        let rfLevel: Double?
        let batteryPercentage: Double?
        let batteryMinutes: Int?
    }
}

extension Array where Element == ChannelReport {
    func groupedByReceiver() -> [MicAssignPayload.Receiver] {
        let grouped = Dictionary(grouping: self, by: { $0.receiverName })
        return grouped.map { receiverName, reports in
            let channels = reports.map { report in
                MicAssignPayload.Channel(
                    channelName: report.channelName,
                    rfLevel: report.rfLevel,
                    batteryPercentage: report.batteryPercentage,
                    batteryMinutes: report.batteryMinutes
                )
            }
            return MicAssignPayload.Receiver(name: receiverName, channels: channels)
        }.sorted { $0.name < $1.name }
    }
}

struct ChannelReport: Hashable {
    let receiverName: String
    let channelName: String
    let rfLevel: Double?
    let batteryPercentage: Double?
    let batteryMinutes: Int?
}

final class ShureReceiverClient {
    let ipAddress: String
    private let session: URLSession

    init(ipAddress: String, session: URLSession) {
        self.ipAddress = ipAddress
        self.session = session
    }

    func fetchChannelReports() async throws -> [ChannelReport] {
        let possibleEndpoints = ["status.json", "channel_status.json", "data/status.json"]
        for endpoint in possibleEndpoints {
            do {
                let statusURL = URL(string: "http://\(ipAddress)/\(endpoint)")!
                var request = URLRequest(url: statusURL)
                request.httpMethod = "GET"
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                    continue
                }
                let reports = try ShureStatusParser.parse(data: data, fallbackReceiverName: ipAddress)
                if !reports.isEmpty {
                    return reports
                }
            } catch {
                continue
            }
        }
        return []
    }
}

enum ShureStatusParserError: Error {
    case invalidPayload
}

enum ShureStatusParser {
    static func parse(data: Data, fallbackReceiverName: String) throws -> [ChannelReport] {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

        if let dictionary = jsonObject as? [String: Any] {
            if let channels = dictionary["channels"] as? [[String: Any]] {
                return parseChannelArray(channels, fallbackReceiverName: fallbackReceiverName)
            }

            if let channelDict = dictionary["channelStatus"] as? [String: Any] {
                return parseChannelDictionary(channelDict, fallbackReceiverName: fallbackReceiverName)
            }

            // Some receivers expose numbered keys at the root (e.g. ch1, ch2)
            let channelCandidates = dictionary.filter { key, value in
                key.lowercased().hasPrefix("ch") && value is [String: Any]
            }

            if !channelCandidates.isEmpty {
                let sorted = channelCandidates.sorted { lhs, rhs in lhs.key < rhs.key }
                let array = sorted.compactMap { $0.value as? [String: Any] }
                return parseChannelArray(array, fallbackReceiverName: fallbackReceiverName)
            }
        }

        if let array = jsonObject as? [[String: Any]] {
            return parseChannelArray(array, fallbackReceiverName: fallbackReceiverName)
        }

        throw ShureStatusParserError.invalidPayload
    }

    private static func parseChannelArray(_ array: [[String: Any]], fallbackReceiverName: String) -> [ChannelReport] {
        array.compactMap { element -> ChannelReport? in
            let channelName = string(from: element, keys: ["name", "channelName", "chan_name", "channel"])
            let receiverName = string(from: element, keys: ["receiver", "receiverName"]) ?? fallbackReceiverName
            let rfLevel = double(from: element, keys: ["rf", "rfLevel", "rf_strength", "rfStrength", "rssi"])
            let batteryPercentage = double(from: element, keys: ["battery", "batteryPercentage", "battery_percent"]) ?? double(from: element, nestedKeys: ["battery", "percentage"])
            let batteryMinutes = int(from: element, keys: ["batteryMinutes"]) ?? int(from: element, nestedKeys: ["battery", "minutes"])

            let fallbackChannelName: String? = {
                if let channelName {
                    return channelName
                }
                if let index = element["index"] as? Int {
                    return "Ch\(index)"
                }
                if let indexString = element["index"] as? String, !indexString.isEmpty {
                    return indexString
                }
                if let identifier = element["id"] as? String, !identifier.isEmpty {
                    return identifier
                }
                return nil
            }()

            guard let name = fallbackChannelName else {
                return nil
            }

            return ChannelReport(
                receiverName: receiverName,
                channelName: name,
                rfLevel: rfLevel,
                batteryPercentage: batteryPercentage,
                batteryMinutes: batteryMinutes
            )
        }
    }

    private static func parseChannelDictionary(_ dictionary: [String: Any], fallbackReceiverName: String) -> [ChannelReport] {
        let values = dictionary.values.compactMap { $0 as? [String: Any] }
        return parseChannelArray(values, fallbackReceiverName: fallbackReceiverName)
    }

    private static func string(from dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func double(from dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }

    private static func int(from dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String, let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    private static func double(from dictionary: [String: Any], nestedKeys: [String]) -> Double? {
        guard let lastKey = nestedKeys.last else { return nil }
        var current: Any? = dictionary
        for key in nestedKeys.dropLast() {
            if let dict = current as? [String: Any] {
                current = dict[key]
            } else {
                current = nil
                break
            }
        }

        if let nestedDict = current as? [String: Any] {
            return double(from: nestedDict, keys: [lastKey])
        }
        return nil
    }

    private static func int(from dictionary: [String: Any], nestedKeys: [String]) -> Int? {
        guard let lastKey = nestedKeys.last else { return nil }
        var current: Any? = dictionary
        for key in nestedKeys.dropLast() {
            if let dict = current as? [String: Any] {
                current = dict[key]
            } else {
                current = nil
                break
            }
        }

        if let nestedDict = current as? [String: Any] {
            return int(from: nestedDict, keys: [lastKey])
        }
        return nil
    }
}

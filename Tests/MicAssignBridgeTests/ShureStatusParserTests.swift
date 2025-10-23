import XCTest
@testable import MicAssignBridge

final class ShureStatusParserTests: XCTestCase {
    func testParsesChannelArrayPayload() throws {
        let json = """
        {
          "channels": [
            {
              "name": "Pastor",
              "receiver": "QLXD-Rack",
              "rfLevel": -44.5,
              "battery": {
                "percentage": 87.5,
                "minutes": 112
              }
            },
            {
              "channelName": "Lectern",
              "receiverName": "QLXD-Rack",
              "rf": -55,
              "batteryMinutes": 90
            }
          ]
        }
        """.data(using: .utf8)!

        let reports = try ShureStatusParser.parse(data: json, fallbackReceiverName: "Fallback")
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.first?.channelName, "Pastor")
        XCTAssertEqual(reports.first?.receiverName, "QLXD-Rack")
        XCTAssertEqual(reports.first?.rfLevel, -44.5)
        XCTAssertEqual(reports.first?.batteryPercentage, 87.5)
        XCTAssertEqual(reports.first?.batteryMinutes, 112)
        XCTAssertEqual(reports.last?.channelName, "Lectern")
        XCTAssertEqual(reports.last?.rfLevel, -55)
        XCTAssertEqual(reports.last?.batteryMinutes, 90)
    }

    func testParsesRootChannelDictionary() throws {
        let json = """
        {
          "channelStatus": {
            "ch1": {
              "channel": "MicA",
              "rfStrength": "-40.2",
              "battery_percent": "95"
            },
            "ch2": {
              "channel": "MicB",
              "rssi": -52,
              "battery": {
                "percentage": "76.5",
                "minutes": "105"
              }
            }
          }
        }
        """.data(using: .utf8)!

        let reports = try ShureStatusParser.parse(data: json, fallbackReceiverName: "AxientRack")
        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports.contains(where: { $0.channelName == "MicA" && $0.rfLevel == -40.2 }))
        XCTAssertTrue(reports.contains(where: { $0.channelName == "MicB" && $0.batteryMinutes == 105 }))
    }

    func testParsesArrayPayload() throws {
        let json = """
        [
          {
            "id": "A",
            "receiver": "ULXD",
            "rfLevel": -38.4
          },
          {
            "index": 2,
            "receiver": "ULXD",
            "battery": {
              "percentage": 50
            }
          }
        ]
        """.data(using: .utf8)!

        let reports = try ShureStatusParser.parse(data: json, fallbackReceiverName: "ULXD")
        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports.contains(where: { $0.channelName == "A" }))
        XCTAssertTrue(reports.contains(where: { $0.channelName == "Ch2" }))
    }
}

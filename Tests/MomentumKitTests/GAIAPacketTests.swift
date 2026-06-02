import Testing
@testable import MomentumKit

struct GAIAPacketTests {

    @Test func encodeNoPayload() {
        let packet = GAIAPacket(vendorID: 0x0495, commandID: 0x1A05)
        #expect(packet.encoded() == [0xFF, 0x03, 0x00, 0x00, 0x04, 0x95, 0x1A, 0x05])
    }

    @Test func encodeWithPayload() {
        let packet = GAIAPacket(vendorID: 0x0495, commandID: 0x1A02, payload: [0x0A])
        #expect(packet.encoded() == [0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1A, 0x02, 0x0A])
    }

    @Test func parseSingle() {
        // ANC_Status response (ANC on), observed live.
        let bytes: [UInt8] = [0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1B, 0x05, 0x01]
        let result = GAIAPacket.parse(bytes)
        #expect(result?.consumed == 9)
        #expect(result?.packet.commandID == 0x1B05)
        #expect(result?.packet.payload == [0x01])
    }

    @Test func splitGluedPackets() {
        // Two responses glued into one RFCOMM read, exactly as captured from the M4.
        let bytes: [UInt8] = [
            0xFF, 0x03, 0x00, 0x06, 0x04, 0x95, 0x1B, 0x01, 0x01, 0x02, 0x02, 0x00, 0x03, 0x00,
            0xFF, 0x03, 0x00, 0x0D, 0x04, 0x95, 0x13, 0x06,
            0x4D, 0x34, 0x41, 0x45, 0x42, 0x54, 0x20, 0x42, 0x6C, 0x61, 0x63, 0x6B, 0x00,
        ]
        let (packets, remainder) = GAIAPacket.split(bytes)
        #expect(packets.count == 2)
        #expect(remainder.isEmpty)
        #expect(packets[0].commandID == 0x1B01)
        #expect(packets[0].payload == [0x01, 0x02, 0x02, 0x00, 0x03, 0x00])
        #expect(packets[1].commandID == 0x1306)
        #expect(String(bytes: packets[1].payload.prefix { $0 != 0 }, encoding: .utf8) == "M4AEBT Black")
    }

    @Test func splitKeepsTrailingPartial() {
        let full: [UInt8] = [0xFF, 0x03, 0x00, 0x01, 0x04, 0x95, 0x1B, 0x05, 0x01]
        let partial: [UInt8] = [0xFF, 0x03, 0x00, 0x04, 0x04, 0x95]   // claims 4 payload bytes, none present yet
        let (packets, remainder) = GAIAPacket.split(full + partial)
        #expect(packets.count == 1)
        #expect(remainder == partial)
    }

    @Test func noiseControlPercentages() {
        // 0 = max ANC, 50 = neutral, 100 = full transparency.
        #expect(NoiseControl.ancPercent(0) == 100)
        #expect(NoiseControl.ancPercent(50) == 0)
        #expect(NoiseControl.transparencyPercent(50) == 0)
        #expect(NoiseControl.transparencyPercent(100) == 100)
        #expect(NoiseControl.ancPercent(100) == 0)         // no ANC on the transparency side
        #expect(NoiseControl.transparencyPercent(0) == 0)  // no transparency on the ANC side
        #expect(NoiseControl.clamp(200) == 100)
        #expect(NoiseControl.clamp(-5) == 0)
        #expect(NoiseMode.allCases.count == 3)
    }
}

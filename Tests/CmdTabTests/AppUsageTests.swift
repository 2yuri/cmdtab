import Darwin
import Foundation
import Testing
@testable import CmdTab

struct AppUsageTests {
    @Test func snapshotCountsThisProcess() {
        let me = getpid()
        let snapshot = AppUsage.snapshot(apps: [.init(pid: me, name: "Me")])
        #expect((snapshot.memory[me] ?? 0) > 1_000_000)
        #expect((snapshot.cpuTime[me] ?? 0) > 0)
    }

    @Test func sharesAreOfTheWholeMac() {
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        let second: UInt64 = 1_000_000_000
        let earlier = AppUsage.Snapshot(apps: [], cpuTime: [1: 0, 2: 0], memory: [:], taken: 0)
        let later = AppUsage.Snapshot(apps: [], cpuTime: [1: second, 2: second / 2, 3: 9 * second], memory: [:], taken: second)
        let shares = AppUsage.cpuShares(from: earlier, to: later)
        #expect(abs(shares[1]! - 1 / cores) < 0.0001)
        #expect(abs(shares[2]! - 0.5 / cores) < 0.0001)
        #expect(shares[3] == nil)
    }

    @Test func topKeepsTheHeaviestFive() {
        let values: [pid_t: Double] = [1: 0.1, 2: 0.5, 3: 0, 4: 0.3, 5: 0.2, 6: 0.05, 7: 0.4]
        #expect(AppUsage.top(values).map(\.key) == [2, 7, 4, 5, 1])
    }

    @Test func memoryStaysInBytes() {
        #expect(AppUsage.bytes([1: 1_073_741_824])[1] == 1_073_741_824)
    }
}

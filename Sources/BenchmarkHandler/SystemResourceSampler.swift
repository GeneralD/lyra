import Darwin
import Domain

public struct SystemResourceSampler {
    public init() {}
}

extension SystemResourceSampler: ResourceSampler {
    public var current: ResourceSnapshot {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return ResourceSnapshot(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0)
        }

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        return ResourceSnapshot(
            cpuUser: usage.ru_utime.seconds,
            cpuSystem: usage.ru_stime.seconds,
            peakRSS: Int64(usage.ru_maxrss),
            currentRSS: kr == KERN_SUCCESS ? Int64(info.resident_size) : 0
        )
    }
}

extension timeval {
    fileprivate var seconds: Double {
        Double(tv_sec) + Double(tv_usec) / 1_000_000
    }
}

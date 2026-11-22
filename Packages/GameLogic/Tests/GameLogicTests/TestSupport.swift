import Foundation

/// CPU time consumed by the current thread, in seconds. Use for speed assertions:
/// unlike wall time it isn't inflated when parallel test suites compete for cores.
func threadCPUTime() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

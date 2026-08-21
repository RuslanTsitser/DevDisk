import Darwin
import Foundation

struct ProbeResult: Codable {
    let pid: Int32
    let name: String
    let taskInfoBytes: Int32
    let taskInfoErrno: Int32
    let rusageResult: Int32
    let rusageErrno: Int32
    let residentBytes: UInt64
    let physicalFootprintBytes: UInt64
}

struct InterfaceResult: Codable {
    let name: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

func nanoseconds(_ value: timespec) -> UInt64 {
    UInt64(value.tv_sec) * 1_000_000_000 + UInt64(value.tv_nsec)
}

func sampleAllProcesses() -> Int {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return 0 }
    var sampledPIDs = [pid_t](repeating: 0, count: Int(count))
    let bytes = proc_listallpids(&sampledPIDs, Int32(sampledPIDs.count * MemoryLayout<pid_t>.size))
    let sampledCount = max(Int(bytes) / MemoryLayout<pid_t>.size, 0)
    var successCount = 0
    for pid in sampledPIDs.prefix(sampledCount) where pid > 0 {
        var taskInfo = proc_taskinfo()
        let taskBytes = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, Int32(MemoryLayout<proc_taskinfo>.size))
        }
        var usage = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        if taskBytes == MemoryLayout<proc_taskinfo>.size, usageResult == 0 {
            successCount += 1
        }
    }
    return successCount
}

if CommandLine.arguments.contains("--benchmark") {
    let iterations = 1_000
    var wallStart = timespec()
    var wallEnd = timespec()
    var cpuStart = timespec()
    var cpuEnd = timespec()
    clock_gettime(CLOCK_MONOTONIC_RAW, &wallStart)
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpuStart)
    var totalSuccessfulSamples = 0
    for _ in 0..<iterations {
        totalSuccessfulSamples += sampleAllProcesses()
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &cpuEnd)
    clock_gettime(CLOCK_MONOTONIC_RAW, &wallEnd)
    let wallNanoseconds = nanoseconds(wallEnd) - nanoseconds(wallStart)
    let cpuNanoseconds = nanoseconds(cpuEnd) - nanoseconds(cpuStart)
    let report: [String: Any] = [
        "iterations": iterations,
        "successfulProcessSamples": totalSuccessfulSamples,
        "wallMilliseconds": Double(wallNanoseconds) / 1_000_000,
        "cpuMilliseconds": Double(cpuNanoseconds) / 1_000_000,
        "cpuMillisecondsPerPass": Double(cpuNanoseconds) / 1_000_000 / Double(iterations)
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
    exit(0)
}

let requiredTaskInfoBytes = Int32(MemoryLayout<proc_taskinfo>.size)
let pidCount = proc_listallpids(nil, 0)
var pids = [pid_t](repeating: 0, count: max(Int(pidCount), 0))
let listedBytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
let listedCount = max(Int(listedBytes) / MemoryLayout<pid_t>.size, 0)

let listedPIDs = pids.prefix(listedCount).filter { $0 > 0 }
let candidatePIDs = Array(Set(listedPIDs + [getpid(), getppid(), 1])).sorted()
let results = candidatePIDs.map { pid -> ProbeResult in
    var nameBytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    _ = proc_name(pid, &nameBytes, UInt32(nameBytes.count))
    let name = nameBytes.withUnsafeBufferPointer { buffer in
        String(cString: buffer.baseAddress!)
    }

    errno = 0
    var taskInfo = proc_taskinfo()
    let taskInfoBytes = withUnsafeMutablePointer(to: &taskInfo) { pointer in
        proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, requiredTaskInfoBytes)
    }
    let taskInfoErrno = taskInfoBytes == requiredTaskInfoBytes ? 0 : errno

    errno = 0
    var usage = rusage_info_v4()
    let rusageResult = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { rebound in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
        }
    }
    let rusageErrno = rusageResult == 0 ? 0 : errno

    return ProbeResult(
        pid: pid,
        name: name,
        taskInfoBytes: taskInfoBytes,
        taskInfoErrno: taskInfoErrno,
        rusageResult: rusageResult,
        rusageErrno: rusageErrno,
        residentBytes: taskInfoBytes == requiredTaskInfoBytes ? taskInfo.pti_resident_size : 0,
        physicalFootprintBytes: rusageResult == 0 ? usage.ri_phys_footprint : 0
    )
}

var cpuLoad = host_cpu_load_info_data_t()
var cpuLoadCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
let cpuLoadResult = withUnsafeMutablePointer(to: &cpuLoad) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuLoadCount)) { rebound in
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &cpuLoadCount)
    }
}

var vmStatistics = vm_statistics64_data_t()
var vmStatisticsCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
let vmStatisticsResult = withUnsafeMutablePointer(to: &vmStatistics) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmStatisticsCount)) { rebound in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &vmStatisticsCount)
    }
}

var interfacePointer: UnsafeMutablePointer<ifaddrs>?
var interfaces: [InterfaceResult] = []
let interfacesResult = getifaddrs(&interfacePointer)
if interfacesResult == 0 {
    var cursor = interfacePointer
    while let entry = cursor?.pointee {
        if entry.ifa_addr.pointee.sa_family == UInt8(AF_LINK), let rawData = entry.ifa_data {
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            interfaces.append(InterfaceResult(
                name: String(cString: entry.ifa_name),
                receivedBytes: UInt64(data.ifi_ibytes),
                sentBytes: UInt64(data.ifi_obytes)
            ))
        }
        cursor = entry.ifa_next
    }
    freeifaddrs(interfacePointer)
}

let report: [String: Any] = [
    "selfPID": getpid(),
    "parentPID": getppid(),
    "pidListCount": listedCount,
    "taskInfoSuccessCount": results.filter { $0.taskInfoBytes == requiredTaskInfoBytes }.count,
    "rusageSuccessCount": results.filter { $0.rusageResult == 0 }.count,
    "foreignTaskInfoSuccessCount": results.filter { $0.pid != getpid() && $0.taskInfoBytes == requiredTaskInfoBytes }.count,
    "foreignRusageSuccessCount": results.filter { $0.pid != getpid() && $0.rusageResult == 0 }.count,
    "explicitPIDResults": results.filter { [getpid(), getppid(), 1].contains($0.pid) }.map {
        ["pid": $0.pid, "name": $0.name, "taskInfoErrno": $0.taskInfoErrno, "rusageErrno": $0.rusageErrno,
         "residentBytes": $0.residentBytes, "physicalFootprintBytes": $0.physicalFootprintBytes]
    },
    "hostCPULoadResult": cpuLoadResult,
    "hostVMStatisticsResult": vmStatisticsResult,
    "interfaceStatisticsResult": interfacesResult,
    "interfaces": interfaces.map { ["name": $0.name, "receivedBytes": $0.receivedBytes, "sentBytes": $0.sentBytes] },
    "sampleFailures": results.filter { $0.taskInfoErrno != 0 || $0.rusageErrno != 0 }.prefix(10).map {
        ["pid": $0.pid, "name": $0.name, "taskInfoErrno": $0.taskInfoErrno, "rusageErrno": $0.rusageErrno]
    }
]

let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))

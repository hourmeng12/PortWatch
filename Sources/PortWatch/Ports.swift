import Foundation

struct Port: Identifiable, Hashable {
    let port: Int
    let pid: Int32
    let command: String
    var id: String { "\(pid):\(port)" }
}

/// Parses `lsof -F pcn` output: `p<pid>`, `c<command>`, `n<addr>:<port>` lines.
func parseLsof(_ out: String) -> [Port] {
    var found = Set<Port>()  // a Set folds the IPv4 + IPv6 sockets of one process into one row
    var pid: Int32 = 0, cmd = ""
    for line in out.split(separator: "\n") {
        guard let tag = line.first else { continue }
        let val = line.dropFirst()
        switch tag {
        case "p": pid = Int32(val) ?? 0; cmd = ""
        case "c": cmd = String(val)
        case "n":
            if let colon = val.lastIndex(of: ":"), let port = Int(val[val.index(after: colon)...]) {
                found.insert(Port(port: port, pid: pid, command: cmd))
            }
        default: break
        }
    }
    return found.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
}

func scanPorts() -> [Port] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    p.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()  // lsof exits 1 when nothing listens; output is still valid
    return parseLsof(String(decoding: data, as: UTF8.self))
}

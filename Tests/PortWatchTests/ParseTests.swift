import XCTest
@testable import PortWatch

final class ParseTests: XCTestCase {
    func testParseLsof() {
        let out = """
        p456
        cpostgres
        f5
        n127.0.0.1:5432
        p123
        cnode
        f22
        n*:3000
        f23
        n[::1]:3000
        p9
        cweird
        f1
        nnot-a-port

        """
        XCTAssertEqual(parseLsof(out), [
            Port(port: 3000, pid: 123, command: "node"),
            Port(port: 5432, pid: 456, command: "postgres"),
        ])
    }
}

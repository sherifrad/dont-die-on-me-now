import XCTest
@testable import DontDieOnMeNow

final class ProcessRunnerTests: XCTestCase {
    func testRunnerHandlesLargeStdoutAndStderr() throws {
        let script = """
        i=0
        while [ "$i" -lt 20000 ]; do
          echo "stdout-$i"
          echo "stderr-$i" >&2
          i=$((i + 1))
        done
        """

        let result = try FoundationProcessRunner().run("/bin/sh", arguments: ["-c", script])

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.stdout.contains("stdout-19999"))
        XCTAssertTrue(result.stderr.contains("stderr-19999"))
    }
}

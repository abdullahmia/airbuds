// The tiny check harness: sections, pass/fail counts and hex helpers.

import Foundation

var failures = 0
var passes = 0

func section(_ name: String) { print("== \(name)") }

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}

func bytes(_ s: String) -> [UInt8] { hex(s.replacingOccurrences(of: " ", with: "")) }

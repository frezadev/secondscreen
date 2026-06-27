// Log.swift
// Logger ringan. Set Log.verbose = true untuk debug detail.

import Foundation

enum Log {
    static var verbose = false

    static func info(_ msg: String) {
        FileHandle.standardError.write("[info] \(msg)\n".data(using: .utf8)!)
    }

    static func debug(_ msg: String) {
        guard verbose else { return }
        FileHandle.standardError.write("[debug] \(msg)\n".data(using: .utf8)!)
    }

    static func error(_ msg: String) {
        FileHandle.standardError.write("[error] \(msg)\n".data(using: .utf8)!)
    }
}

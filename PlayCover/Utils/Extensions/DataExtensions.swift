//
//  DataExtensions.swift
//  PlayCover
//

import Foundation

extension String {
    init(data: Data, offset: Int, commandSize: Int, loadCommandString: lc_str) {
        let loadCommandStringOffset = Int(loadCommandString.offset)
        guard offset >= data.startIndex, commandSize >= 0,
              offset <= data.endIndex, commandSize <= data.endIndex - offset,
              loadCommandStringOffset < commandSize else {
            self = ""
            return
        }
        let stringOffset = offset + loadCommandStringOffset
        let length = commandSize - loadCommandStringOffset
        let rawData = data[stringOffset..<(stringOffset + length)]
        let endIndex = rawData.firstIndex(of: 0x00) ?? rawData.endIndex
        self = String(data: data[stringOffset..<endIndex], encoding: .utf8) ?? ""
    }
}

extension Data {
    func extract<T>(_ type: T.Type, offset: Int = 0,
                    swap: ((UnsafeMutablePointer<T>, NXByteOrder) -> Void)? = nil) -> T {
        let data = self[offset..<offset + MemoryLayout<T>.size]
        var result = data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        swap?(&result, NXHostByteOrder())
        return result
    }
}

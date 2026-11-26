#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingWeb

// The three functions JavaScript calls (web/src/core/fitlingCore.ts). Memory for requests and answers
// is handed out here and given back by JavaScript with fitling_free. Only in the WebAssembly build: on
// the build machine this target is just compiled along with the tests.
#if arch(wasm32)
@_expose(wasm, "fitling_alloc")
@_cdecl("fitling_alloc")
func fitlingAlloc(_ size: Int32) -> Int32 {
    Int32(Int(bitPattern: UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), 1), alignment: 1)))
}

@_expose(wasm, "fitling_free")
@_cdecl("fitling_free")
func fitlingFree(_ pointer: Int32, _ size: Int32) {
    UnsafeMutableRawPointer(bitPattern: Int(pointer))?.deallocate()
}

/// The answer's address in the upper 32 bits, its length in the lower 32.
@_expose(wasm, "fitling_call")
@_cdecl("fitling_call")
func fitlingCall(_ pointer: Int32, _ length: Int32) -> Int64 {
    let request = UnsafeRawPointer(bitPattern: Int(pointer)).map { Data(bytes: $0, count: Int(length)) } ?? Data()
    let answer = handle(request)
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(answer.count, 1), alignment: 1)
    answer.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: answer.count)
    return (Int64(UInt32(bitPattern: Int32(Int(bitPattern: buffer)))) << 32) | Int64(answer.count)
}
#endif

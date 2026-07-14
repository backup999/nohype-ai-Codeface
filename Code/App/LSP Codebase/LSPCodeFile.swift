import SwiftLSP
import FoundationToolz

/**
 ⛔️ Do not change! This is part of the ".codebase" file format.
 */
final class LSPCodeFile: Codable, Sendable
{
    init(name: String,
         code: String,
         symbols: [LSPCodeSymbol]? = nil)
    {
        self.name = name
        self.code = code
        self.symbols = symbols
    }
    
    let name: String
    
    var lines: [String] { code.lines }
    let code: String
    
    let symbols: [LSPCodeSymbol]?
}

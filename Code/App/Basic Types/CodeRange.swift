extension CodeRange {
    func getCode(fromLines lines: [String]) -> String?
    {
        guard lines.isValid(index: start.line),
              lines.isValid(index: end.line) else { return nil }
        
        return lines[start.line ... end.line].joined(separator: "\n")
    }
}

/// Contiguous source range used by Architecture (backend-agnostic).
struct CodeRange: Hashable, Sendable, Codable
{
    init(start: CodePosition, end: CodePosition)
    {
        self.start = start
        self.end = end
    }
    
    let start: CodePosition
    let end: CodePosition
    
    /// Whether `other` lies fully inside this range (inclusive, using line + character).
    func contains(_ other: CodeRange) -> Bool
    {
        if other.start.line < start.line { return false }
        if other.start.line == start.line,
           other.start.character < start.character { return false }
        
        if other.start.line > end.line { return false }
        if other.start.line == end.line,
           other.start.character > end.character { return false }
        
        if other.end.line < start.line { return false }
        if other.end.line == start.line,
           other.end.character < start.character { return false }
        
        if other.end.line > end.line { return false }
        if other.end.line == end.line,
           other.end.character > end.character { return false }
        
        return true
    }
}

/// Zero-based source position (line + character on that line).
struct CodePosition: Hashable, Sendable, Codable
{
    init(line: Int, character: Int)
    {
        self.line = line
        self.character = character
    }
    
    let line: Int
    let character: Int
}

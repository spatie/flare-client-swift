/// A supplied frame. Source snippets and symbolication are the caller's responsibility.
public struct FlareStackFrame: Codable, Sendable, Equatable {
    public var file: String
    public var lineNumber: Int
    public var method: String?
    public var className: String?
    public var isApplicationFrame: Bool
    public var codeSnippet: [String: String]?

    public init(
        file: String,
        lineNumber: Int = 0,
        method: String? = nil,
        className: String? = nil,
        isApplicationFrame: Bool = true,
        codeSnippet: [String: String]? = nil
    ) {
        self.file = file
        self.lineNumber = lineNumber
        self.method = method
        self.className = className
        self.isApplicationFrame = isApplicationFrame
        self.codeSnippet = codeSnippet
    }

    enum CodingKeys: String, CodingKey {
        case file, lineNumber, method, isApplicationFrame, codeSnippet
        case className = "class"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        try container.encode(lineNumber, forKey: .lineNumber)
        try container.encode(method, forKey: .method)
        try container.encode(className, forKey: .className)
        try container.encode(isApplicationFrame, forKey: .isApplicationFrame)
        try container.encodeIfPresent(codeSnippet, forKey: .codeSnippet)
    }
}

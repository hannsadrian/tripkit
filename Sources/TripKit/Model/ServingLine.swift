import Foundation

public class ServingLine: NSObject, NSSecureCoding {
    
    public static var supportsSecureCoding: Bool = true
    
    /// Reference to a means of transport.
    public let line: Line
    /// Destination station of the line.
    public let destination: Location?
    
    public init(line: Line, destination: Location?) {
        self.line = line
        self.destination = destination
    }
    
    // MARK: - NSSecureCoding

    public required convenience init?(coder aDecoder: NSCoder) {
        guard let line = aDecoder.decodeObject(of: Line.self, forKey: PropertyKey.lineKey) else { return nil }
        // Use decodeObject(of:forKey:) for optionals too, it handles nil
        let destination = aDecoder.decodeObject(of: Location.self, forKey: PropertyKey.destinationKey)
        self.init(line: line, destination: destination)
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(line, forKey: PropertyKey.lineKey)
        // No need to check for nil, encode handles it correctly
        aCoder.encode(destination, forKey: PropertyKey.destinationKey)
    }

    // MARK: - Equatable (via isEqual)

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ServingLine else {
            return false
        }
        
        if self === other {
             return true
        }
        
        return self.line == other.line && self.destination == other.destination
    }

    // MARK: - Hashable (via hash)

    override public var hash: Int {
        var hasher = Hasher()
        // Ensure Line and Location conform to Hashable correctly
        hasher.combine(line)
        hasher.combine(destination) // Combine destination as well!
        return hasher.finalize()
    }

    // MARK: - PropertyKeys (can be private)

    private struct PropertyKey { // Changed to private
        static let lineKey = "line"
        static let destinationKey = "destination"
    }
    
}

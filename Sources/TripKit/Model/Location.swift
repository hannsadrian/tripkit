import Foundation
import CoreLocation
import os.log

public class Location: NSObject, NSSecureCoding {
    
    private static let NON_UNIQUE_NAMES =  ["Hauptbahnhof", "Hbf", "Hbf.", "HB", "Bahnhof", "Bf", "Bf.", "Bhf", "Bhf.", "Busbahnhof", "Omnibusbahnhof", "Südbahnhof", "ZOB", "Schiffstation", "Schiffst.", "Zentrum", "Markt", "Dorf", "Kirche", "Nord", "Ost", "Süd", "West", "Airport", "Flughafen", "Talstation", "Bus", "Flixbus"]
    
    public static var supportsSecureCoding: Bool = true
    
    /// Station, poi, coord, address or any
    public let type: LocationType
    /// Unique location id of the transit provider.
    ///
    /// May not be nil for a station.
    public let id: String?
    /// Coordinate of this location.
    public let coord: LocationPoint?
    /// Name of the locality/city.
    public let place: String?
    /// Name of the station, street or poi.
    public let name: String?
    /// Products departing from this station.
    public let products: [Product]?
    
    public var radius: Double?
    
    public var groupNumber: Int = 0
    
    public var subtitle: String?
    
    lazy var distanceFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 2
        return numberFormatter
    }()
    
    public init?(type: LocationType, id: String?, coord: LocationPoint?, place: String?, name: String?, products: [Product]?, radius: Double? = nil, subtitle: String? = nil) {
        if let id = id, id.isEmpty {
            return nil
        }
        if let _ = place, name == nil {
            return nil
        }
        if type == .any {
            if id != nil {
                return nil
            }
        } else if type == .coord && coord == nil {
            return nil
        }
        
        self.type = type
        self.id = id
        self.coord = coord
        self.place = place
        self.name = name
        self.products = products
        self.radius = radius
        self.subtitle = subtitle
    }
    
    public init(id: String) {
        self.type = .station
        self.id = id
        self.coord = nil
        self.place = nil
        self.name = nil
        self.products = nil
        self.subtitle = nil
    }
    
    public init(anyName: String?) {
        self.type = .any
        self.id = nil
        self.coord = nil
        self.place = nil
        self.name = anyName
        self.products = nil
    }
    
    public init(lat: Int, lon: Int) {
        self.type = .coord
        self.id = nil
        self.coord = LocationPoint(lat: lat, lon: lon)
        self.place = nil
        self.name = nil
        self.products = nil
    }
    
    convenience public init?(type: LocationType, id: String?, coord: LocationPoint?, place: String?, name: String?) {
        self.init(type: type, id: id, coord: coord, place: place, name: name, products: nil, subtitle: nil)
    }
    
    convenience public init?(type: LocationType, id: String) {
        self.init(type: type, id: id, coord: nil, place: nil, name: nil)
    }
    
    required convenience public init?(coder aDecoder: NSCoder) {
            guard let type = LocationType(rawValue: aDecoder.decodeInteger(forKey: PropertyKey.locationTypeKey)) else {
                os_log("failed to decode location", log: .default, type: .error)
                return nil
            }
            
            let id = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.locationIdKey) as String?
            let coord: LocationPoint?
            if aDecoder.containsValue(forKey: PropertyKey.locationLatKey) && aDecoder.containsValue(forKey: PropertyKey.locationLonKey) {
                let lat = aDecoder.decodeInteger(forKey: PropertyKey.locationLatKey)
                let lon = aDecoder.decodeInteger(forKey: PropertyKey.locationLonKey)
                coord = LocationPoint(lat: lat, lon: lon)
            } else {
                coord = nil
            }
            let place = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.locationPlaceKey) as String?
            let name = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.locationNameKey) as String?
            
            // NEU: Radius dekodieren
            let radius: Double? = aDecoder.containsValue(forKey: PropertyKey.radiusKey) ? aDecoder.decodeDouble(forKey: PropertyKey.radiusKey) : nil
        let subtitle: String? = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.subtitleKey) as String?
            
            self.init(type: type, id: id, coord: coord, place: place, name: name, products: nil, radius: radius, subtitle: subtitle)
        }

        public func encode(with aCoder: NSCoder) {
            aCoder.encode(type.rawValue, forKey: PropertyKey.locationTypeKey)
            aCoder.encode(id, forKey: PropertyKey.locationIdKey)
            if let coord = coord {
                aCoder.encode(coord.lat, forKey: PropertyKey.locationLatKey)
                aCoder.encode(coord.lon, forKey: PropertyKey.locationLonKey)
            }
            aCoder.encode(place, forKey: PropertyKey.locationPlaceKey)
            aCoder.encode(name, forKey: PropertyKey.locationNameKey)
            
            // NEU: Radius kodieren
            if let radius = radius {
                aCoder.encode(radius, forKey: PropertyKey.radiusKey)
            }
            
            if let subtitle = subtitle {
                aCoder.encode(subtitle, forKey: PropertyKey.subtitleKey)
            }
        }
    
    /// Returns true if the coordinate is non-nil.
    public func hasLocation() -> Bool {
        return coord != nil
    }
    
    /// Returns true if either a name or a place exists.
    public func hasName() -> Bool {
        return name != nil || place != nil
    }
    
    /// Returns this shortest, unambiguous name possible of this location.
    ///
    /// Locations with names like "Hbf" or "station" are not unambiguous, that's why the place is appended to the name in this case.
    /// If no name or place is specified for this location, the id, coordinate or type is returned instead.
    public func getUniqueShortName() -> String {
        if let name = self.name {
            return name
        } else if let id = self.id, id != "" {
            return id
        } else if let coord = coord {
            return "\(Double(coord.lat) / 1e6):\(Double(coord.lon) / 1e6)"
        } else {
            return type.displayName
        }
    }
    
    /// Returns the name and place of this location, if available. Otherwise, the coordinate or location type is returned.
    public func getUniqueLongName(withoutId: Bool = false) -> String {
        var result = ""
        if let name = name {
            result += name
        }
        if let place = place, !result.contains(place) {
            if !result.isEmpty {
                result += ", "
            }
            result += place
        }
        if result.isEmpty {
            if let coord = coord {
                result =  "\(Double(coord.lat) / 1e6):\(Double(coord.lon) / 1e6)"
            } else {
                result = type.displayName
            }
        }
        if let radius = radius, radius > 1 {
            result += "\(radius)"
        } else if !withoutId {
            result += "\(id)"
        }
        return result
    }
    
    /// Returns the name of the place in one line and the name of the location in a new line, if available.
    /// Otherwise, the coordinate or location type is returned.
    public func getMultilineLabel() -> String {
        var result = ""
        if let place = place {
            result += place
        }
        if let name = name {
            if !result.isEmpty {
                result += "\n"
            }
            result += name
        }
        if result.isEmpty {
            if let coord = coord {
                result =  "\(Double(coord.lat) / 1e6):\(Double(coord.lon) / 1e6)"
            } else {
                result = type.displayName
            }
        }
        return result
    }
    
    /// Returns the distance text in meters between this location and another location of the CoreLocation framework with a specified number of fraction digits.
    public func getDistanceText(_ location: CLLocation, maximumFractionDigits: Int = 2) -> String {
        let distance = getDistance(from: location)
        distanceFormatter.maximumFractionDigits = maximumFractionDigits
        if distance > 1000 {
            return "\(distanceFormatter.string(from: (distance / 1000) as NSNumber) ?? String(format: "%.2f", distance / 1000))\u{00a0}km"
        } else {
            return "\(Int(distance))\u{00a0}m"
        }
    }
    
    /// Returns the distance  in meters between this location and another location of the CoreLocation framework.
    public func getDistance(from location: CLLocation) -> CLLocationDistance {
        let distance: CLLocationDistance
        if let coord = coord {
            distance = location.distance(from: CLLocation(latitude: Double(coord.lat) / 1000000.0, longitude: Double(coord.lon) / 1000000.0))
        } else {
            distance = 0
        }
        return distance
    }
    
    /// Checks whether this location is uniquely identifiable to the transit provider.
    public func isIdentified() -> Bool {
        if type == .station {
            return id != nil && id != ""
        }
        if type == .poi {
            return true
        }
        if type == .address || type == .coord {
            return hasLocation()
        }
        
        return false
    }
    
    override public var description: String {
        return ["{type=", type.stringValue,", ",
                "id=", id ?? "",", ",
                "place=", place ?? "",", ",
                "name=", name ?? "",", ",
                "lat=", "\(Double(coord?.lat ?? 0) * pow(10, -6))",", ",
                "lng=", "\(Double(coord?.lon ?? 0) * pow(10, -6))", "}"].joined()
    }
    
    override public func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Location else { return false }
            if self === other { return true }

            // 1. Different types are never equal
            guard self.type == other.type else { return false }

            // 2. If IDs exist, they must match (primary identifier)
            if let selfId = self.id, let otherId = other.id {
                return selfId == otherId
            }
            // Handle cases where one or both IDs are nil
            if self.id != nil || other.id != nil {
                 // If one has an ID and the other doesn't, they are not equal (unless both are nil, covered below)
                 // If both had IDs, we would have returned true/false already.
                return false
            }

            // 3. If no IDs, compare coordinates if both exist
            if let selfCoord = self.coord, let otherCoord = other.coord {
                return selfCoord == otherCoord // Assumes LocationPoint is Equatable
            }
            // Handle cases where one or both coords are nil
            if self.coord != nil || other.coord != nil {
                // If one has coords and the other doesn't, they are not equal
                return false
            }

            // 4. If no IDs and no coords, compare place and name (last resort)
            //    Treat nil names/places consistently
            return self.place == other.place && self.name == other.name
        }

        override public var hash: Int {
            var hasher = Hasher()
            // Hash based on the *same logic path* as isEqual
            hasher.combine(type) // Always include type

            if let id = self.id {
                hasher.combine(id) // Prioritize ID
            } else if let coord = self.coord {
                hasher.combine(coord.lat) // Use coordinates if no ID
                hasher.combine(coord.lon)
            } else {
                hasher.combine(place) // Use place and name if no ID and no coord
                hasher.combine(name)
            }
            return hasher.finalize()
        }
    
    struct PropertyKey {
        
        static let locationTypeKey = "type"
        static let locationIdKey = "id"
        static let locationLatKey = "lat"
        static let locationLonKey = "lon"
        static let locationPlaceKey = "place"
        static let locationNameKey = "name"
        static let radiusKey = "radius"
        static let subtitleKey = "subtitle"
    }
    
    
}

public enum LocationType: Int, Codable {
    
    /** Location can represent any of the below. Mainly meant for user input. */
    case any,
    /** Location represents a station or stop. */
    station,
    /** Location represents a point of interest. */
    poi,
    /** Location represents a postal address. */
    address,
    /** Location represents a just a plain coordinate, e.g. acquired by GPS. */
    coord
    
    private static let stringValues: [LocationType: String] = [.any: "any", .station: "station", .poi: "poi", .address: "address", .coord: "coord"]
    
    public var stringValue: String {
        return LocationType.stringValues[self]!
    }
    
    public var displayName: String {
        switch self {
        case .any:
            return "Ort"
        case .station:
            return "Haltestelle"
        case .poi:
            return "Point Of Interest"
        case .address:
            return "Adresse"
        case .coord:
            return "Adresse"
        }
    }
    
    public static func from(string: String) -> LocationType? {
        return stringValues.first(where: {$1 == string})?.key
    }
    
}

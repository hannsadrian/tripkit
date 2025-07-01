import Foundation
import os.log
import SwiftyJSON
import CoreLocation // For polyline decoding if needed

// MARK: - MOTIS Specific Context Objects

public class MotisQueryTripsContext: QueryTripsContext {
    public override class var supportsSecureCoding: Bool { return true }

    let previousPageCursor: String?
    let nextPageCursor: String?
    let originalRequestUrl: String? // Store the original URL to easily query more

    // Store original query parameters for refresh/more
    let from: Location
    let via: Location?
    let to: Location
    let date: Date
    let departure: Bool
    let tripOptions: TripOptions

    public override var canQueryEarlier: Bool { return previousPageCursor != nil }
    public override var canQueryLater: Bool { return nextPageCursor != nil }

    init(previousPageCursor: String?, nextPageCursor: String?, originalRequestUrl: String?, from: Location, via: Location?, to: Location, date: Date, departure: Bool, tripOptions: TripOptions) {
        self.previousPageCursor = previousPageCursor?.nilIfEmpty
        self.nextPageCursor = nextPageCursor?.nilIfEmpty
        self.originalRequestUrl = originalRequestUrl
        self.from = from
        self.via = via
        self.to = to
        self.date = date
        self.departure = departure
        self.tripOptions = tripOptions
        super.init()
    }

    public required convenience init?(coder aDecoder: NSCoder) {
        let previousPageCursor = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.previousPageCursor) as String?
        let nextPageCursor = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.nextPageCursor) as String?
        let originalRequestUrl = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.originalRequestUrl) as String?
        guard let from = aDecoder.decodeObject(of: Location.self, forKey: PropertyKey.from),
              let to = aDecoder.decodeObject(of: Location.self, forKey: PropertyKey.to),
              let date = aDecoder.decodeObject(of: NSDate.self, forKey: PropertyKey.date) as Date?,
              let tripOptions = aDecoder.decodeObject(of: TripOptions.self, forKey: PropertyKey.tripOptions)
        else {
            os_log("Failed to decode MotisQueryTripsContext", log: .requestLogger, type: .error)
            return nil
        }
        let via = aDecoder.decodeObject(of: Location.self, forKey: PropertyKey.via)
        let departure = aDecoder.decodeBool(forKey: PropertyKey.departure)

        self.init(previousPageCursor: previousPageCursor, nextPageCursor: nextPageCursor, originalRequestUrl: originalRequestUrl, from: from, via: via, to: to, date: date, departure: departure, tripOptions: tripOptions)
    }

    public override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(previousPageCursor, forKey: PropertyKey.previousPageCursor)
        aCoder.encode(nextPageCursor, forKey: PropertyKey.nextPageCursor)
        aCoder.encode(originalRequestUrl, forKey: PropertyKey.originalRequestUrl)
        aCoder.encode(from, forKey: PropertyKey.from)
        aCoder.encode(via, forKey: PropertyKey.via)
        aCoder.encode(to, forKey: PropertyKey.to)
        aCoder.encode(date, forKey: PropertyKey.date)
        aCoder.encode(departure, forKey: PropertyKey.departure)
        aCoder.encode(tripOptions, forKey: PropertyKey.tripOptions)
    }

    struct PropertyKey {
        static let previousPageCursor = "previousPageCursor"
        static let nextPageCursor = "nextPageCursor"
        static let originalRequestUrl = "originalRequestUrl"
        static let from = "from"
        static let via = "via"
        static let to = "to"
        static let date = "date"
        static let departure = "departure"
        static let tripOptions = "tripOptions"
    }
}

public class MotisQueryJourneyDetailContext: QueryJourneyDetailContext {
    public override class var supportsSecureCoding: Bool { return true }

    let tripId: String

    init(tripId: String) {
        self.tripId = tripId
        super.init()
    }

    public required convenience init?(coder aDecoder: NSCoder) {
        guard let tripId = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.tripId) as String? else {
            os_log("Failed to decode MotisQueryJourneyDetailContext", log: .requestLogger, type: .error)
            return nil
        }
        self.init(tripId: tripId)
    }

    public override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(tripId, forKey: PropertyKey.tripId)
    }
    
    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MotisQueryJourneyDetailContext else { return false }
        if self === other { return true }
        // Compare based on the value of tripId
        return self.tripId == other.tripId
    }

    override public var hash: Int {
        // Hash based on the value of tripId
        return tripId.hashValue
    }

    struct PropertyKey {
        static let tripId = "tripId"
    }

     public override var description: String {
        return "MotisQueryJourneyDetailContext(tripId: \(tripId))"
    }
}

// Assuming RefreshTrip might just re-query the specific trip ID
public class MotisRefreshTripContext: RefreshTripContext {
     public override class var supportsSecureCoding: Bool { return true }

    let tripId: String // Or potentially more context if needed for a plan request

    init(tripId: String) {
        self.tripId = tripId
        super.init()
    }

    public required convenience init?(coder aDecoder: NSCoder) {
        guard let tripId = aDecoder.decodeObject(of: NSString.self, forKey: PropertyKey.tripId) as String? else {
             os_log("Failed to decode MotisRefreshTripContext", log: .requestLogger, type: .error)
            return nil
        }
        self.init(tripId: tripId)
    }

    public override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(tripId, forKey: PropertyKey.tripId)
    }

    struct PropertyKey {
        static let tripId = "tripId"
    }
}


// MARK: - AbstractMotisProvider Implementation

public class AbstractMotisProvider: AbstractNetworkProvider {

    let apiBaseUrl: String
    let apiKey: String? // Add if MOTIS instance requires an API key header/param
    internal let isoFormatter = ISO8601DateFormatter()

    // --- Initialization ---

    public init(networkId: NetworkId, apiBaseUrl: String, apiKey: String? = nil) {
        self.apiBaseUrl = apiBaseUrl
        self.apiKey = apiKey
        super.init(networkId: networkId)
        self.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current // MOTIS often uses CET/CEST
        self.isoFormatter.formatOptions = [.withInternetDateTime] // Adjust if needed based on API response
        self.isoFormatter.timeZone = self.timeZone // Ensure formatter uses the correct timezone for encoding/decoding
    }

    // --- Provider Configuration ---

    public override var supportedQueryTraits: Set<QueryTrait> {
        return [
            .maxChanges,        // Supported via maxTransfers
            .minChangeTime,     // Supported via minTransferTime, additionalTransferTime, transferTimeFactor
            .maxFootpathTime,   // Supported via maxPreTransitTime, maxPostTransitTime, maxDirectTime (implicitly)
            // .maxFootpathDist is *not* directly supported by max time parameters.
            // .tariffClass, .tariffTravelerType, .tariffReductions are potentially supported via experimental parameters (`passengers`, `withFares`) but not standard TripOptions yet.
        ]
    }

    // MOTIS API seems language-agnostic in responses, but geocoding might support it.
    // Check /geocode endpoint spec for 'language' parameter.
    public override var supportedLanguages: Set<String> { ["en", "de"] } // Assume English and German based on common usage

    // --- Date Formatting ---
     private func formatLocationForQuery(_ location: Location) -> String? {
        if let stationId = location.id, !stationId.isEmpty {
            return stationId
        } else if let coord = location.coord {
            // Format: latitude,longitude,level (level is optional, default to 0)
            // Use high precision for coordinates
            let lat = Double(coord.lat) / 1_000_000.0
            let lon = Double(coord.lon) / 1_000_000.0
            return String(format: "%.7f,%.7f,0", lat, lon) // Assuming level 0
        }
        return nil
    }

    private func formatModesForQuery(_ products: [Product]?) -> [String]? {
        guard let products = products, !products.isEmpty else {
             return ["TRANSIT"] // Default MOTIS behavior if nothing specified
        }
        // MOTIS uses specific strings. Map TripKit Product enums.
        let modeStrings = products.compactMap { product -> String? in
            switch product {
            case .highSpeedTrain: return "HIGHSPEED_RAIL" // Or maybe "RAIL" or specific types
            case .regionalTrain: return "REGIONAL_RAIL,REGIONAL_FAST_RAIL" // Or maybe "RAIL"
            case .suburbanTrain: return "METRO" // MOTIS seems to group S-Bahn under regional
            case .subway: return "SUBWAY"
            case .tram: return "TRAM"
            case .bus: return "BUS" // Excludes COACH
            case .ferry: return "FERRY"
            case .onDemand: return "ODM" // MOTIS might have 'ODM' or specific rental modes
            case .cablecar: return "OTHER" // Or specific if MOTIS supports it
            // Add mappings for other MOTIS modes if needed (AIRPLANE, COACH, METRO, etc.)
            }
        }
        // Use TRANSIT if the mapping results in a mix that TRANSIT covers, or if empty?
        // Or return the specific list. Let's return the specific list.
        return modeStrings.isEmpty ? ["TRANSIT"] : modeStrings.uniqued()
    }

     private func mapAccessibilityToProfile(_ accessibility: Accessibility?) -> String? {
        switch accessibility {
        case .barrierFree, .limited: // Map both limited and barrierFree to WHEELCHAIR for simplicity? Or only barrierFree?
            return "WHEELCHAIR"
        case .neutral, .none:
            return "FOOT" // Default
        }
    }

    // --- API Call Implementations ---

    public override func suggestLocations(constraint: String, types: [LocationType]?, maxLocations: Int, completion: @escaping (HttpRequest, SuggestLocationsResult) -> Void) -> AsyncRequest {
        let urlBuilder = UrlBuilder(path: apiBaseUrl + "/api/v1/geocode", encoding: .utf8)
        urlBuilder.addParameter(key: "text", value: constraint)
        urlBuilder.addParameter(key: "language", value: queryLanguage ?? defaultLanguage)

        // Map LocationType to MOTIS LocationType enum string
        if let types = types, !types.isEmpty {
            let motisTypes = types.compactMap { type -> String? in
                switch type {
                case .station: return "STOP"
                case .poi: return "PLACE"
                case .address: return "ADDRESS"
                case .coord, .any: return nil // COORD not directly supported, ANY is implicit
                }
            }
            // MOTIS /geocode doesn't seem to support multiple types directly in the spec shown.
            // If it does, format appropriately (e.g., comma-separated).
            // For now, let's just take the first one if available, or omit if mixed/unsupported.
             if motisTypes.count == 1 {
                 urlBuilder.addParameter(key: "type", value: motisTypes.first!)
             } else if !motisTypes.isEmpty {
                 os_log("MOTIS provider suggestLocations currently only supports filtering by a single type.", log: .requestLogger, type: .info)
                 // urlBuilder.addParameter(key: "type", value: motisTypes.joined(separator: ",")) // Example if comma-separated
             }
        }
         // maxLocations is not directly supported by MOTIS /geocode. The API returns its own ranked list.

        let httpRequest = HttpRequest(urlBuilder: urlBuilder)
        // Add API Key header if necessary
        // if let apiKey = apiKey { httpRequest.headers = ["X-API-Key": apiKey] }

        return makeRequest(httpRequest, parseHandler: { [weak self] in
            try self?.suggestLocationsParsing(request: httpRequest, constraint: constraint, types: types, maxLocations: maxLocations, completion: completion)
        }, errorHandler: { error in
            completion(httpRequest, .failure(error))
        })
    }

    public override func queryNearbyLocations(location: Location, types: [LocationType]?, maxDistance: Int, maxLocations: Int, completion: @escaping (HttpRequest, NearbyLocationsResult) -> Void) -> AsyncRequest {
            guard let centerCoord = location.coord else {
                os_log("queryNearbyLocations requires input location with coordinates.", log: .requestLogger, type: .error)
                completion(HttpRequest(urlBuilder: UrlBuilder()), .invalidId)
                return AsyncRequest(task: nil)
            }

            // If types are specified and don't include .station, return empty because /map/stops only returns stations.
            if let types = types, !types.isEmpty, !types.contains(.station) {
                 os_log("/map/stops endpoint only returns stations. Returning empty list for non-station type filter.", log: .requestLogger, type: .info)
                completion(HttpRequest(urlBuilder: UrlBuilder()), .success(locations: []))
                return AsyncRequest(task: nil)
            }

            // Calculate bounding box based on maxDistance
            let radius = maxDistance > 0 ? Double(maxDistance) : 1000.0 // Default radius if maxDistance not specified or zero
            guard let (minCoord, maxCoord) = calculateBoundingBox(center: centerCoord, radiusMeters: radius) else {
                 os_log("Failed to calculate bounding box for queryNearbyLocations.", log: .requestLogger, type: .error)
                completion(HttpRequest(urlBuilder: UrlBuilder()), .failure(ParseError(reason: "Failed to calculate bounding box")))
                 return AsyncRequest(task: nil)
            }


            let urlBuilder = UrlBuilder(path: apiBaseUrl + "/api/v1/map/stops", encoding: .utf8)
            // min = bottom-right (minLat, maxLon)
            // max = top-left (maxLat, minLon)
            urlBuilder.addParameter(key: "min", value: String(format: "%.7f,%.7f", minCoord.0, maxCoord.1))
            urlBuilder.addParameter(key: "max", value: String(format: "%.7f,%.7f", maxCoord.0, minCoord.1))

            let httpRequest = HttpRequest(urlBuilder: urlBuilder)
            // Add API Key header if necessary
            // if let apiKey = apiKey { httpRequest.headers = ["X-API-Key": apiKey] }

            return makeRequest(httpRequest, parseHandler: { [weak self] in
                try self?.motisQueryNearbyLocationsParsing(request: httpRequest, centerLocation: location, maxDistance: maxDistance, maxLocations: maxLocations, completion: completion)
            }, errorHandler: { error in
                completion(httpRequest, .failure(error))
            })
        }

    public override func queryDepartures(stationId: String, departures: Bool, time: Date?, maxDepartures: Int, radius: Int?, completion: @escaping (HttpRequest, QueryDeparturesResult) -> Void) -> AsyncRequest {
        
        func performRequest(currentRadius: Int?, isRetry: Bool) -> AsyncRequest {
            let urlBuilder = UrlBuilder(path: apiBaseUrl + "/api/v1/stoptimes", encoding: .utf8)
            urlBuilder.addParameter(key: "stopId", value: stationId)
            urlBuilder.addParameter(key: "n", value: maxDepartures) // 'n' parameter for number of events
            urlBuilder.addParameter(key: "arriveBy", value: !departures)
            if let time = time {
                urlBuilder.addParameter(key: "time", value: isoFormatter.string(from: time), percentCoded: false)
            }
            
            if let radius = currentRadius {
                 urlBuilder.addParameter(key: "radius", value: radius)
            }
            // Optional: Filter by mode?
            // urlBuilder.addParameter(key: "mode", value: ["BUS", "TRAM"].joined(separator: ","))
            
            let httpRequest = HttpRequest(urlBuilder: urlBuilder)
            // Add API Key header if necessary
            // if let apiKey = apiKey { httpRequest.headers = ["X-API-Key": apiKey] }
            
            return makeRequest(httpRequest, parseHandler: { [weak self] in
                try self?.queryDeparturesParsing(request: httpRequest, stationId: stationId, departures: departures, time: time, maxDepartures: maxDepartures, radius: radius, completion: { request, parsedDepartures in
                    switch parsedDepartures {
                    case .success(departures: let deps):
                        if !isRetry && radius == 0 && deps.isEmpty {
                            print("Radius 0 returned no results, trying with radius 1...")
                            // Perform the second request with radius=1
                            // IMPORTANT: We don't call the completion handler here.
                            // The second request's completion/error handler will call it.
                            // We need to ensure the AsyncRequest handle from the *second* call
                            // is somehow managed, but for simplicity, we launch it.
                            // The original function technically returns the handle for the *first* request.
                             _ = performRequest(currentRadius: 1, isRetry: true) // Make the retry request
                        } else {
                            completion(request, parsedDepartures)
                        }
                    default:
                        completion(request, parsedDepartures)
                    }
                    
                })
                
                
            }, errorHandler: { error in
                completion(httpRequest, .failure(error))
            })
        }
        
        // Determine the radius for the *first* request based on `equivs`
        return performRequest(currentRadius: radius, isRetry: false)
    }

    // The public signature remains the same.
    public override func queryTrips(from: Location, via: Location?, to: Location, date: Date, departure: Bool, tripOptions: TripOptions, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) -> AsyncRequest {
        // We call our internal method which handles the retry logic.
        return self.queryTrips(from: from, via: via, to: to, date: date, departure: departure, tripOptions: tripOptions, isRetry: false, completion: completion)
    }

    // This is the new internal implementation that supports retries.
    // The pagination-based queryTrips method remains unchanged.
    private func queryTrips(from: Location, via: Location?, to: Location, date: Date, departure: Bool, tripOptions: TripOptions, isRetry: Bool, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) -> AsyncRequest {
        let urlBuilder = UrlBuilder(path: apiBaseUrl + "/api/v1/plan", encoding: .utf8)

        guard let fromPlace = formatLocationForQuery(from) else {
            completion(HttpRequest(urlBuilder: urlBuilder), .unknownFrom)
            return AsyncRequest(task: nil)
        }
        guard let toPlace = formatLocationForQuery(to) else {
            completion(HttpRequest(urlBuilder: urlBuilder), .unknownTo)
            return AsyncRequest(task: nil)
        }

        urlBuilder.addParameter(key: "fromPlace", value: fromPlace)
        urlBuilder.addParameter(key: "toPlace", value: toPlace)
        urlBuilder.addParameter(key: "time", value: isoFormatter.string(from: date))
        urlBuilder.addParameter(key: "arriveBy", value: !departure)
        urlBuilder.addParameter(key: "detailedTransfers", value: true)
        urlBuilder.addParameter(key: "maxPreTransitTime", value: 1800)
        urlBuilder.addParameter(key: "maxPostTransitTime", value: 1800)
        urlBuilder.addParameter(key: "maxDirectTime", value: 3600)
        
        if let additionalTransferTime = tripOptions.additionalTransferTime {
            urlBuilder.addParameter(key: "minTransferTime", value: additionalTransferTime/2)
            urlBuilder.addParameter(key: "transferTimeFactor", value: 2)
        }
        
        // Only add the timetableView parameter if the .timed option is present
        if tripOptions.options?.contains(.timed) ?? false {
            urlBuilder.addParameter(key: "timetableView", value: false)
        } else {
            urlBuilder.addParameter(key: "timetableView", value: true)
        }

        if let viaLocation = via {
            if let viaId = viaLocation.id, !viaId.isEmpty {
                urlBuilder.addParameter(key: "via", value: [viaId].joined(separator: ","))
            } else {
                os_log("MOTIS provider only supports 'via' with stop IDs.", log: .requestLogger, type: .fault)
            }
        }

        if var modes = formatModesForQuery(tripOptions.products) {
            if tripOptions.options?.contains(.bike) ?? false {
                modes.append("BIKE")
            }
            if tripOptions.options?.contains(.rental) ?? false {
                modes.append("RENTAL")
            }
            urlBuilder.addParameter(key: "transitModes", value: modes.joined(separator: ","))
        }

        if let maxFootTime = tripOptions.maxFootpathTime {
            let maxTimeSeconds = maxFootTime * 60
            urlBuilder.addParameter(key: "maxPreTransitTime", value: maxTimeSeconds)
            urlBuilder.addParameter(key: "maxPostTransitTime", value: maxTimeSeconds)
            urlBuilder.addParameter(key: "maxDirectTime", value: maxTimeSeconds)
        }
        if let maxChanges = tripOptions.maxChanges, maxChanges >= 0 {
            urlBuilder.addParameter(key: "maxTransfers", value: maxChanges)
        }
        if let minTime = tripOptions.minChangeTime, minTime >= 0 {
            urlBuilder.addParameter(key: "minTransferTime", value: minTime)
        }
        if let profile = mapAccessibilityToProfile(tripOptions.accessibility) {
            urlBuilder.addParameter(key: "pedestrianProfile", value: profile)
        }
        if tripOptions.options?.contains(.bike) ?? false {
            urlBuilder.addParameter(key: "preTransitModes", value: "BIKE,WALK")
            urlBuilder.addParameter(key: "postTransitModes", value: "BIKE,WALK")
            urlBuilder.addParameter(key: "directModes", value: "BIKE,WALK")
            urlBuilder.removeParameter(key: "maxDirectTime")
            urlBuilder.addParameter(key: "maxDirectTime", value: 14400)
        }
        if tripOptions.options?.contains(.rental) ?? false {
            urlBuilder.addParameter(key: "preTransitModes", value: "RENTAL,WALK")
            urlBuilder.addParameter(key: "postTransitModes", value: "RENTAL,WALK")
            urlBuilder.addParameter(key: "directModes", value: "RENTAL,WALK")
            urlBuilder.removeParameter(key: "maxDirectTime")
            urlBuilder.addParameter(key: "maxDirectTime", value: 14400)
        }
         

        let finalUrlString = urlBuilder.build()?.absoluteString
        let httpRequest = HttpRequest(urlBuilder: urlBuilder)

        return makeRequest(httpRequest, parseHandler: { [weak self] in
            // Pass a special completion block to the parsing function
            try self?.queryTripsParsing(request: httpRequest, from: from, via: via, to: to, date: date, departure: departure, tripOptions: tripOptions, previousContext: nil, later: departure, urlString: finalUrlString, completion: { request, result in
                
                // --- START: RETRY LOGIC ---
                let requestedWithTimed = tripOptions.options?.contains(.timed) ?? false
                
                // Condition: No trips found, this was the first attempt (not a retry), and it was a `.timed` request.
                if case .noTrips = result, !isRetry, requestedWithTimed {
                    os_log("Timed trip query returned no results, retrying without .timed option.", log: .requestLogger, type: .info)
                    
                    // Create new trip options without .timed
                    var newTripOptions = tripOptions
                    newTripOptions.options = newTripOptions.options?.filter({ $0 != .timed })
                    
                    // Perform the request again with the new options.
                    // The original completion handler is passed along to be called by the second request.
                    // The AsyncRequest handle of this retry is not returned, which is fine for this fallback pattern.
                    _ = self?.queryTrips(from: from, via: via, to: to, date: date, departure: departure, tripOptions: newTripOptions, isRetry: true, completion: completion)
                } else {
                    // In all other cases (success, failure, or retry already happened), just forward the result.
                    completion(request, result)
                }
                // --- END: RETRY LOGIC ---
            })
        }, errorHandler: { error in
            if case HttpError.invalidStatusCode(let code, _) = error, code == 400 {
                completion(httpRequest, .failure(ParseError(reason: "Bad Request - check input parameters (\(code))")))
                return
            }
            completion(httpRequest, .failure(error))
        })
    }

    // The pagination based queryTrips method can be simplified as it should not contain the request-building logic.
    // It is kept as-is from your original code.
    private func queryTrips(from: Location, via: Location?, to: Location, date: Date, departure: Bool, tripOptions: TripOptions, previousContext: MotisQueryTripsContext?, later: Bool, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) -> AsyncRequest {

        let urlBuilder: UrlBuilder
        let pageCursor: String?

        if let context = previousContext, let originalUrl = context.originalRequestUrl {
            urlBuilder = UrlBuilder(path: originalUrl, encoding: .utf8)
            pageCursor = later ? context.nextPageCursor : context.previousPageCursor
            if let cursor = pageCursor {
                urlBuilder.setParameter(key: "pageCursor", value: cursor)
            } else {
                completion(HttpRequest(urlBuilder: UrlBuilder()), .noTrips)
                return AsyncRequest(task: nil)
            }
        } else {
            // This case should now be handled by the other queryTrips method.
            // For safety, we can log an error or forward to the correct method.
            os_log("Pagination queryTrips called without a context. This should not happen.", log: .requestLogger, type: .error)
            return self.queryTrips(from: from, via: via, to: to, date: date, departure: departure, tripOptions: tripOptions, completion: completion)
        }

        let finalUrlString = urlBuilder.build()?.absoluteString
        let httpRequest = HttpRequest(urlBuilder: urlBuilder)

        return makeRequest(httpRequest, parseHandler: { [weak self] in
            try self?.queryTripsParsing(request: httpRequest, from: from, via: via, to: to, date: date, departure: departure, tripOptions: tripOptions, previousContext: previousContext, later: later, urlString: finalUrlString, completion: completion)
        }, errorHandler: { error in
             if case HttpError.invalidStatusCode(let code, _) = error, code == 400 {
                 completion(httpRequest, .failure(ParseError(reason: "Bad Request - check input parameters (\(code))")))
                 return
             }
            completion(httpRequest, .failure(error))
        })
    }


    public override func queryMoreTrips(context: QueryTripsContext, later: Bool, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) -> AsyncRequest {
         guard let motisContext = context as? MotisQueryTripsContext else {
            completion(HttpRequest(urlBuilder: UrlBuilder()), .sessionExpired)
            return AsyncRequest(task: nil)
        }

         // Check if querying in the requested direction is possible
         if later && !motisContext.canQueryLater {
             completion(HttpRequest(urlBuilder: UrlBuilder()), .noTrips) // No more trips in this direction
             return AsyncRequest(task: nil)
         }
         if !later && !motisContext.canQueryEarlier {
             completion(HttpRequest(urlBuilder: UrlBuilder()), .noTrips) // No more trips in this direction
             return AsyncRequest(task: nil)
         }

         // Use the internal queryTrips method with the context
        return queryTrips(from: motisContext.from, via: motisContext.via, to: motisContext.to, date: motisContext.date, departure: motisContext.departure, tripOptions: motisContext.tripOptions, previousContext: motisContext, later: later, completion: completion)
    }

    public override func refreshTrip(context: RefreshTripContext, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) -> AsyncRequest {
        // MOTIS doesn't have a dedicated refresh endpoint.
        // We need to re-request the trip using the /trip endpoint or re-run the /plan query.
        // Using /trip is simpler if we only need that specific trip's current state.
         guard let motisContext = context as? MotisRefreshTripContext else {
            completion(HttpRequest(urlBuilder: UrlBuilder()), .sessionExpired)
            return AsyncRequest(task: nil)
        }

        let urlBuilder = UrlBuilder(path: apiBaseUrl + "/api/v1/trip", encoding: .utf8)
        urlBuilder.addParameter(key: "tripId", value: motisContext.tripId)

        let httpRequest = HttpRequest(urlBuilder: urlBuilder)
        // Add API Key header if necessary
        // if let apiKey = apiKey { httpRequest.headers = ["X-API-Key": apiKey] }

        return makeRequest(httpRequest, parseHandler: { [weak self] in
            try self?.refreshTripParsing(request: httpRequest, context: context, completion: completion)
        }, errorHandler: { error in
            completion(httpRequest, .failure(error))
        })
    }

    public override func queryJourneyDetail(context: QueryJourneyDetailContext, completion: @escaping (HttpRequest, QueryJourneyDetailResult) -> Void) -> AsyncRequest {
        guard let motisContext = context as? MotisQueryJourneyDetailContext else {
            completion(HttpRequest(urlBuilder: UrlBuilder()), .invalidId)
            return AsyncRequest(task: nil)
        }

        let urlBuilder = UrlBuilder(path: apiBaseUrl + "/api/v1/trip", encoding: .utf8)
        urlBuilder.addParameter(key: "tripId", value: motisContext.tripId)

        let httpRequest = HttpRequest(urlBuilder: urlBuilder)
        // Add API Key header if necessary
        // if let apiKey = apiKey { httpRequest.headers = ["X-API-Key": apiKey] }

        return makeRequest(httpRequest, parseHandler: { [weak self] in
            try self?.queryJourneyDetailParsing(request: httpRequest, context: context, completion: completion)
        }, errorHandler: { error in
            completion(httpRequest, .failure(error))
        })
    }

     // MOTIS does not seem to have a wagon sequence endpoint in the provided spec.
     public override func queryWagonSequence(context: QueryWagonSequenceContext, completion: @escaping (HttpRequest, QueryWagonSequenceResult) -> Void) -> AsyncRequest {
         os_log("MOTIS provider does not support queryWagonSequence.", log: .requestLogger, type: .info)
         completion(HttpRequest(urlBuilder: UrlBuilder()), .invalidId) // Or .failure(UnsupportedOperationError())
         return AsyncRequest(task: nil)
     }

    // MARK: - Parsing Methods

    override func suggestLocationsParsing(request: HttpRequest, constraint: String, types: [LocationType]?, maxLocations: Int, completion: @escaping (HttpRequest, SuggestLocationsResult) -> Void) throws {
        let json = try getResponse(from: request)
        var suggestions: [SuggestedLocation] = []

        let motisTypes = types?.compactMap { type -> String? in
            switch type {
            case .station: return "STOP"
            case .poi: return "PLACE"
            case .address: return "ADDRESS"
            case .coord, .any: return nil // COORD not directly supported, ANY is implicit
            }
        }
        
        for item in json.arrayValue {
            if let location = parseLocation(fromMatch: item) {
                let priority = item["score"].intValue // Use MOTIS score as priority
                
                if motisTypes != nil && !motisTypes!.contains(where: { $0 == item["type"].stringValue }) {
                    continue
                }
                suggestions.append(SuggestedLocation(location: location, priority: priority))
            }
        }

         // MOTIS already sorts by score, but we could re-sort if needed
         // suggestions.sort { $0.priority > $1.priority }

        completion(request, .success(locations: suggestions))
    }

    func motisQueryNearbyLocationsParsing(request: HttpRequest, centerLocation: Location, maxDistance: Int, maxLocations: Int, completion: @escaping (HttpRequest, NearbyLocationsResult) -> Void) throws {
            let json = try getResponse(from: request) // Response is an array of Place objects
            var nearbyLocations: [Location] = []
            let centerCLLocation = CLLocation(latitude: Double(centerLocation.coord!.lat) / 1_000_000.0, longitude: Double(centerLocation.coord!.lon) / 1_000_000.0)

            for placeJson in json.arrayValue {
                if let parsedLocation = parseLocation(fromPlace: placeJson) {
                     // Ensure it's a station (redundant check as endpoint guarantees it, but safe)
                     guard parsedLocation.type == .station else { continue }

                    // Client-side distance filtering
                    let distance = parsedLocation.getDistance(from: centerCLLocation)
                    if maxDistance <= 0 || distance <= Double(maxDistance) {
                        nearbyLocations.append(parsedLocation)
                    }
                }
            }

            // Sort by distance
            nearbyLocations.sort { loc1, loc2 in
                loc1.getDistance(from: centerCLLocation) < loc2.getDistance(from: centerCLLocation)
            }

            // Apply maxLocations limit
            if maxLocations > 0 && nearbyLocations.count > maxLocations {
                nearbyLocations = Array(nearbyLocations.prefix(maxLocations))
            }

            completion(request, .success(locations: nearbyLocations))
        }


    override func queryDeparturesParsing(request: HttpRequest, stationId: String, departures: Bool, time: Date?, maxDepartures: Int, radius: Int?, completion: @escaping (HttpRequest, QueryDeparturesResult) -> Void) throws {
        let json = try getResponse(from: request)

        // The response contains stopTimes directly under `stopTimes` key.
        // We need to group them by station if equivs=true was simulated (e.g., by radius or default behavior).
        // For simplicity here, assume all returned stopTimes belong to the requested stationId or its equivalents.
        // We'll create one StationDepartures object.

        var uniqueDepartures = Set<Departure>()
        var servingLines = Set<ServingLine>()

        for item in json["stopTimes"].arrayValue {
            guard let placeJson = item["place"].dictionary,
                  let stopLocation = parseLocation(fromPlace: JSON(rawValue: placeJson) ?? ""), // Stop location for this event
                  let departureTime = parseDate(item["place"]["departure"].string), // Use departure time for Departure object
                  let plannedDepartureTime = parseDate(item["place"]["scheduledDeparture"].string)
            else {
                 os_log("Could not parse mandatory fields for StopTime: %@", log: .requestLogger, type: .debug, item.rawString() ?? "nil")
                continue
            }

            let predictedDepartureTime = parseDate(item["place"]["departure"].string) // MOTIS departure IS the predicted time
            let plannedPlatform = placeJson["scheduledTrack"]?.string
            let predictedPlatform = placeJson["track"]?.string
            let isCancelled = item["cancelled"].boolValue

            guard let line = parseLine(item) else {
                 os_log("Could not parse line for StopTime: %@", log: .requestLogger, type: .debug, item.rawString() ?? "nil")
                continue
            }

            // Determine destination from headsign or trip info? MOTIS stoptime doesn't directly list final destination.
            // We might need to parse the headsign or leave it nil.
            let destinationName = item["headsign"].string // Use headsign as destination name proxy
            let destination = destinationName != nil ? Location(anyName: destinationName) : nil // Simple name-based location

            let journeyContext = MotisQueryJourneyDetailContext(tripId: item["tripId"].stringValue)

            // MOTIS stoptime doesn't have wagon sequence context
            let wagonSequenceContext: URL? = nil
            // MOTIS stoptime doesn't have load factor
            
            let realtime = item["realTime"].bool

            let departure = Departure(
                plannedTime: plannedDepartureTime,
                predictedTime: (realtime == true) ? predictedDepartureTime : nil, // Only set predicted if different
                line: line,
                position: predictedPlatform,
                plannedPosition: plannedPlatform,
                cancelled: isCancelled,
                destination: destination,
                capacity: nil, // Not available
                message: nil, // Not directly available in StopTime, maybe on Trip later?
                journeyContext: journeyContext,
                wagonSequenceContext: wagonSequenceContext,
                loadFactor: nil // Not available
            )
            let (inserted, _) = uniqueDepartures.insert(departure)
            if !inserted {
                os_log("Duplicate departure detected and ignored: %@", log: .default, type: .debug, departure.description)
            }


            // Add serving line (Set handles duplicates automatically)
            if let dest = destination { // Only add if destination is known? Adjust as needed
                let servingLine = ServingLine(line: line, destination: dest)
                servingLines.insert(servingLine)
            }
        }

        // Create the StationDepartures object
        // Need the primary station location. Query /reverse-geocode or /geocode first?
        // Or just use the location from the *first* departure event?
        guard let firstStopTimePlace = json["stopTimes"].arrayValue.first?["place"],
              let stationLocation = parseLocation(fromPlace: firstStopTimePlace) else {
            // Fallback or error if we can't determine the main station location
            // If stationId was provided, we might already have the Location object?
            // For now, throw error if no departures found or first place invalid
            if uniqueDepartures.isEmpty {
                 completion(request, .success(departures: [])) // No departures found
                 return
            } else {
                 throw ParseError(reason: "Could not determine station location from departures response")
            }
        }

        let stationDepartures = StationDepartures(
            stopLocation: stationLocation, // Use location from first event as primary
            departures: Array(uniqueDepartures),
            lines: Array(servingLines)
        )

        completion(request, .success(departures: [stationDepartures])) // Return as array even if only one
    }


    func queryTripsParsing(request: HttpRequest, from: Location, via: Location?, to: Location, date: Date, departure: Bool, tripOptions: TripOptions, previousContext: QueryTripsContext?, later: Bool, urlString: String?, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) throws {
        let json = try getResponse(from: request)

        var trips: [Trip] = []
        var messages: [InfoText] = [] // MOTIS plan response doesn't seem to have top-level messages

        // Parse direct connections. A "direct" trip is any non-public-transport journey
        // returned by the API in this array. We trust the API and parse it as a valid trip
        // without checking its leg count.
        for item in json["direct"].arrayValue {
             if let trip = parseTrip(fromItinerary: item) {
                 trips.append(trip)
             } else {
                 os_log("Failed to parse a 'direct' itinerary from the response.", log: .requestLogger, type: .fault)
             }
        }

        // Parse transit itineraries
        for item in json["itineraries"].arrayValue {
            if let trip = parseTrip(fromItinerary: item) {
                trips.append(trip)
            }
        }

        if trips.isEmpty && json["itineraries"].arrayValue.isEmpty && json["direct"].arrayValue.isEmpty {
            completion(request, .noTrips)
            return
        }

        // Create context for queryMoreTrips
        let context = MotisQueryTripsContext(
            previousPageCursor: json["previousPageCursor"].string,
            nextPageCursor: json["nextPageCursor"].string,
            originalRequestUrl: previousContext == nil ? urlString : (previousContext as? MotisQueryTripsContext)?.originalRequestUrl, // Pass along original URL
             from: from, // Pass original request parameters for context
             via: via,
             to: to,
             date: date,
             departure: departure,
             tripOptions: tripOptions
        )

        // Parse the resolved 'from' and 'to' locations from the response
        let resolvedFrom = parseLocation(fromPlace: json["from"])
        let resolvedTo = parseLocation(fromPlace: json["to"])

        completion(request, .success(context: context, from: resolvedFrom ?? from, via: via, to: resolvedTo ?? to, trips: trips, messages: messages))
    }

    override func refreshTripParsing(request: HttpRequest, context: RefreshTripContext, completion: @escaping (HttpRequest, QueryTripsResult) -> Void) throws {
        let json = try getResponse(from: request)

        // The /trip endpoint returns a single Itinerary object.
        guard let trip = parseTrip(fromItinerary: json) else {
            throw ParseError(reason: "Failed to parse itinerary from /trip response")
        }

        // Refresh context usually doesn't allow querying more, so context is nil.
        // Messages are also not typically part of a single trip refresh.
        completion(request, .success(context: nil, from: trip.from, via: nil, to: trip.to, trips: [trip], messages: []))
    }

    override func queryJourneyDetailParsing(request: HttpRequest, context: QueryJourneyDetailContext, completion: @escaping (HttpRequest, QueryJourneyDetailResult) -> Void) throws {
         let json = try getResponse(from: request)

         // The /trip endpoint returns a single Itinerary object.
         guard let trip = parseTrip(fromItinerary: json) else {
             throw ParseError(reason: "Failed to parse itinerary from /trip response for journey detail")
         }

         // Find the *first* public leg in the journey detail response
         guard let publicLeg = trip.legs.first(where: { $0 is PublicLeg }) as? PublicLeg else {
             throw ParseError(reason: "Could not find a public leg in the journey detail response")
             // Or handle cases where a detail request might return non-public legs?
         }

         completion(request, .success(trip: trip, leg: publicLeg))
    }

     // MARK: - Parsing Helper Functions

    internal func parseTrip(fromItinerary json: JSON) -> Trip? {
        guard let duration = json["duration"].int, // Duration is in seconds
              let startTimeStr = json["startTime"].string,
              let endTimeStr = json["endTime"].string,
              let legsArray = json["legs"].array
        else {
            os_log("Could not parse mandatory fields for Itinerary: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
            return nil
        }

        let parsedLegs = legsArray.compactMap { parseLeg($0) }

        if parsedLegs.isEmpty {
             os_log("No valid legs parsed for Itinerary: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
            return nil
        }

        guard let departureTime = parseDate(startTimeStr),
              let arrivalTime = parseDate(endTimeStr)
        else {
             os_log("Could not parse start/end time for Itinerary: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
             return nil
        }

        let fromLocation = parsedLegs.first!.departure
        let toLocation = parsedLegs.last!.arrival

         // Fares - requires parsing FareTransfer structure, complex mapping
         let fares = parseFares(json["fareTransfers"])

         // Refresh Context - Use the tripId of the first public leg if available
         let firstPublicLegTripId = parsedLegs.first(where: { $0 is PublicLeg })
             .flatMap { ($0 as? PublicLeg)?.journeyContext as? MotisQueryJourneyDetailContext }?
             .tripId

         var refreshContext: MotisRefreshTripContext? = nil
         if let tripId = firstPublicLegTripId {
             refreshContext = MotisRefreshTripContext(tripId: tripId)
         }

        // Trip ID - MOTIS doesn't provide a single ID for an itinerary. Generate one?
        // Or use the refreshContext's tripId if available? Let TripKit generate one for now.
        let tripId = "" // TripKit will generate one based on content

        return Trip(
            id: tripId,
            from: fromLocation,
            to: toLocation,
            legs: parsedLegs,
            duration: TimeInterval(duration),
            fares: fares,
            refreshContext: refreshContext
        )
    }

    internal func parseLeg(_ json: JSON) -> Leg? {
         guard let modeStr = json["mode"].string,
               let startTimeStr = json["startTime"].string,
               let endTimeStr = json["endTime"].string,
               let fromPlaceJson = json["from"].dictionary,
               let toPlaceJson = json["to"].dictionary
         else {
             os_log("Could not parse mandatory fields for Leg: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
             return nil
         }

        guard let departure = parseStopEvent(JSON(rawValue: fromPlaceJson) ?? "", defaultTimeStr: startTimeStr, defaultScheduledTimeStr: json["scheduledStartTime"].string),
               let arrival = parseStopEvent(JSON(rawValue: toPlaceJson) ?? "", defaultTimeStr: endTimeStr, defaultScheduledTimeStr: json["scheduledEndTime"].string)
         else {
            os_log("Could not parse from/to StopEvents for Leg: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
             return nil
         }

         let path = decodePolyline(json["legGeometry"]["points"].string) ?? []
         let message = json["message"].string // Not standard in MOTIS Leg, but check just in case

         // Differentiate between Public and Individual Leg based on mode
        if let product = parseProduct(modeStr), product != .onDemand { // Treat 'WALK', 'BIKE', 'CAR', 'RENTAL' etc. as individual
             // Public Leg
             let intermediateStops = json["intermediateStops"].arrayValue.compactMap { parseStop($0) }
             let tripId = json["tripId"].string

             guard let line = parseLine(json) else {
                 os_log("Could not parse line for Public Leg: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
                 return nil
             }

             // Destination: Use headsign if available
             let destinationName = json["headsign"].string
             let destination = destinationName != nil ? Location(anyName: destinationName) : nil // Simple location from name

             // Journey Detail Context
            let journeyContext = (tripId != nil) ? MotisQueryJourneyDetailContext(tripId: tripId!) : nil

             // Wagon Sequence Context - Not available in MOTIS plan response
             let wagonSequenceContext: QueryWagonSequenceContext? = nil

             // Load Factor - Not available in MOTIS plan response
             let loadFactor: LoadFactor? = nil

             return PublicLeg(
                 line: line,
                 destination: destination,
                 departure: departure,
                 arrival: arrival,
                 intermediateStops: intermediateStops,
                 message: message,
                 path: path,
                 journeyContext: journeyContext,
                 wagonSequenceContext: wagonSequenceContext,
                 loadFactor: loadFactor
             )

         } else {
             // Individual Leg (Walk, Bike, Car, Rental, etc.)
             let type: IndividualLeg.`Type`
             switch modeStr.uppercased() {
                 case "WALK": type = .walk
                 case "BIKE": type = .bike
                 case "CAR": type = .car
                 case "RENTAL": type = .bike // Or map to specific types if needed
                 default: type = .transfer // Default for unknown or non-public modes
             }

             let departureTime = departure.time // Use actual parsed time
             let arrivalTime = arrival.time

             let distance = json["distance"].intValue // Distance in meters

             // TODO: Handle Rental details if mode == RENTAL
             // let rentalInfo = json["rental"] -> parseRental(rentalInfo)

             return IndividualLeg(
                 type: type,
                 departureTime: departureTime,
                 departure: departure.location,
                 arrival: arrival.location,
                 arrivalTime: arrivalTime,
                 distance: distance,
                 path: path
             )
         }
     }

    internal func parseStop(_ json: JSON) -> Stop? {
        // A Stop in TripKit corresponds to an intermediate stop in MOTIS leg
        // which is represented by the Place schema.
        guard let placeJson = json.dictionary,
              let location = parseLocation(fromPlace: JSON(rawValue: placeJson) ?? "") else {
             os_log("Could not parse intermediate stop Place: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
            return nil
        }

         // Intermediate stops in MOTIS response usually have arrival and departure times
        let arrivalEvent = parseStopEvent(JSON(rawValue: placeJson) ?? "", defaultTimeStr: json["arrival"].string, defaultScheduledTimeStr: json["scheduledArrival"].string)
        let departureEvent = parseStopEvent(JSON(rawValue: placeJson) ?? "", defaultTimeStr: json["departure"].string, defaultScheduledTimeStr: json["scheduledDeparture"].string)

        // Message - Not usually present on intermediate stops in MOTIS leg response
        let message: String? = nil

        // Create Stop, ensuring at least one event exists
         guard arrivalEvent != nil || departureEvent != nil else {
             os_log("Intermediate stop Place has no valid arrival or departure event: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
             return nil
         }

        return Stop(location: location, departure: departureEvent, arrival: arrivalEvent, message: message)
    }


    internal func parseStopEvent(_ json: JSON, defaultTimeStr: String?, defaultScheduledTimeStr: String?) -> StopEvent? {
        guard let location = parseLocation(fromPlace: json) else {
             os_log("Could not parse location for StopEvent: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
            return nil
        }

        // Prefer specific time fields if available, otherwise use defaults passed from Leg/StopTime
        let timeStr = json["arrival"].string ?? json["departure"].string ?? defaultTimeStr
        let scheduledTimeStr = json["scheduledArrival"].string ?? json["scheduledDeparture"].string ?? defaultScheduledTimeStr

        guard let plannedTimeStr = scheduledTimeStr,
              let plannedTime = parseDate(plannedTimeStr)
        else {
            os_log("Could not parse plannedTime for StopEvent: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
            return nil // Planned time is mandatory
        }

        let predictedTime = parseDate(timeStr ?? "") // Actual time from API is predicted time
        let plannedPlatform = json["scheduledTrack"].string
        let predictedPlatform = json["track"].string
        let cancelled = json["cancelled"].boolValue // Check if stop itself is cancelled

        // Pickup/Dropoff Type - Map to cancelled status?
        let pickupCancelled = json["pickupType"].stringValue == "NOT_ALLOWED"
        let dropoffCancelled = json["dropoffType"].stringValue == "NOT_ALLOWED"

        return StopEvent(
            location: location,
            plannedTime: plannedTime,
            predictedTime: (predictedTime != plannedTime) ? predictedTime : nil, // Only set predicted if different
            plannedPlatform: parsePosition(position: plannedPlatform), // Use helper
            predictedPlatform: parsePosition(position: predictedPlatform), // Use helper
            cancelled: cancelled // Consider pickup/dropoff restrictions as cancelled?
        )
    }

    internal func parseLocation(fromPlace json: JSON) -> Location? {
        guard let name = json["name"].string,
              let lat = json["lat"].double,
              let lon = json["lon"].double
        else {
             os_log("Could not parse mandatory fields for Place->Location: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
            return nil
        }

        let id = json["stopId"].string?.nilIfEmpty // Use stopId if present
        let coord = LocationPoint(lat: Int(lat * 1_000_000), lon: Int(lon * 1_000_000))

        // Determine type based on vertexType or presence of id
        let type: LocationType
        if let vertexType = json["vertexType"].string {
            switch vertexType.uppercased() {
            case "TRANSIT": type = .station
            case "BIKESHARE": type = .poi // Map BIKESHARE to POI?
            case "NORMAL": type = (id != nil) ? .station : .coord // If NORMAL has ID, treat as station? Otherwise coord.
            default: type = (id != nil) ? .station : .coord // Fallback
            }
        } else {
             type = (id != nil) ? .station : .coord // Infer from ID presence
        }
        
        var place: String? = nil
        if type == .station && id != nil {
            var splits = id!.split(separator: ":")
            if splits.count > 2 {
                place = String(splits.last ?? "")
            }
        }
        if let track = json["track"].string ?? json["scheduledTrack"].string {
            place = track
        }
        if place?.isEmpty ?? false {
            place = nil
        }

         // MOTIS Place doesn't distinguish between 'place' (city) and 'name' (station/street) well.
         // Use the single 'name' field for TripKit's 'name'. 'place' remains nil unless we can infer it.
         return Location(type: type, id: id, coord: coord, place: place, name: name)
    }

     internal func parseLocation(fromMatch json: JSON) -> Location? {
         // Used for /geocode and /reverse-geocode results (Match schema)
         guard let typeStr = json["type"].string,
               let name = json["name"].string,
               let lat = json["lat"].double,
               let lon = json["lon"].double
         else {
             os_log("Could not parse mandatory fields for Match->Location: %@", log: .requestLogger, type: .debug, json.rawString() ?? "nil")
             return nil
         }

         let id = json["id"].string // Use ID from match

         let type: LocationType
         switch typeStr.uppercased() {
             case "ADDRESS": type = .address
             case "PLACE": type = .poi
             case "STOP": type = .station
             default: return nil // Unknown type
         }

         let coord = LocationPoint(lat: Int(lat * 1_000_000), lon: Int(lon * 1_000_000))

         // Try to extract place (city/area) from the 'areas' array
         // Find the area with adminLevel closest to 7 (heuristic for city) or the one marked 'default'
         var placeName: String? = nil
         if let areas = json["areas"].array, !areas.isEmpty {
             let defaultArea = areas.first(where: { $0["default"].boolValue })
             if let area = defaultArea {
                 placeName = area["name"].string
             } else {
                 // Find closest to admin level 7
                 let sortedAreas = areas.sorted { abs($0["adminLevel"].intValue - 7) < abs($1["adminLevel"].intValue - 7) }
                 placeName = sortedAreas.first?["name"].string
             }
         }

         // Extract street, house number, zip if available (mainly for addresses)
         let street = json["street"].string
         let houseNumber = json["houseNumber"].string
         let zipCode = json["zip"].string

         // Construct a potentially richer name for addresses
         var finalName = name
         if type == .address {
             var addressParts: [String] = []
             if let street = street { addressParts.append(street) }
             if let houseNumber = houseNumber { addressParts.append(houseNumber) }
             if !addressParts.isEmpty {
                 finalName = addressParts.joined(separator: " ")
             }
             // Optionally append zip/place if not already in name/placeName
             // ... logic to combine parts intelligently ...
         }

         return Location(type: type, id: id, coord: coord, place: placeName, name: finalName)
     }

    internal func parseLine(_ json: JSON) -> Line? {
        // Can be called from Leg or StopTime
        let modeStr = json["mode"].string
        let network = json["agencyName"].string?.nilIfEmpty // agencyName maps to network
        let label = json["routeShortName"].string?.nilIfEmpty // routeShortName maps to label
        let name = json["headsign"].string?.nilIfEmpty // Use headsign as line name? Or routeLongName if available?
        let id = json["tripId"].string // Use tripId as line id?

        let product = parseProduct(modeStr ?? "")

        // Attributes - MOTIS doesn't seem to provide these directly in plan/stoptimes
        let attr: [Line.Attr]? = nil
        // Message - Not directly available per line here
        let message: String? = nil

        let style = lineStyle(network: network, product: product, label: label)

        return Line(
            id: id,
            network: network,
            product: product,
            label: label,
            name: name,
            number: nil, // Not available
            vehicleNumber: nil, // Not available
            style: style,
            attr: attr,
            message: message,
            direction: nil // Not available
        )
    }

     internal func parseProduct(_ modeStr: String) -> Product? {
         // Map MOTIS Mode strings to TripKit Product enums
         switch modeStr.uppercased() {
         // Transit types
         case "TRAM": return .tram
         case "SUBWAY": return .subway
         case "FERRY": return .ferry
         case "BUS": return .bus
         case "METRO": return .suburbanTrain
         case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL": return .regionalTrain // Group various rail types?
         case "HIGHSPEED_RAIL", "LONG_DISTANCE": return .highSpeedTrain
         case "NIGHT_RAIL": return .highSpeedTrain // Group night trains with high speed? Or regional?
         case "COACH": return .bus // Group long distance coach with bus?
         case "AIRPLANE": return nil // TripKit doesn't have an airplane product

         // Street types (return nil as they are handled by IndividualLeg)
         case "WALK", "BIKE", "CAR", "RENTAL", "CAR_PARKING", "ODM": return nil

         // Special types
         case "TRANSIT": return nil // Represents 'all', not a specific product
         case "OTHER": return nil // Map 'OTHER' if necessary, e.g., to .cablecar?

         default:
             os_log("Unknown MOTIS mode string encountered: %@", log: .requestLogger, type: .info, modeStr)
             return nil
         }
     }

     internal func parseFares(_ json: JSON) -> [Fare] {
         // TODO: Implement parsing of MOTIS FareTransfer structure to TripKit Fare array.
         // This is complex due to rules (A_AB, A_AB_B, AB) and nested product options.
         // Requires careful interpretation of effectiveFareLegProducts and transferProduct.
         // For now, return empty.
         os_log("MOTIS fare parsing not yet implemented.", log: .requestLogger, type: .info)
         return []
     }

     internal func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        // Try parsing with the configured ISO8601 formatter
        if let date = isoFormatter.date(from: dateString) {
            return date
        } else {
            // Add fallbacks if needed (e.g., different date formats)
            os_log("Could not parse date string: %@", log: .requestLogger, type: .debug, dateString)
            return nil
        }
    }

    // MARK: - Polyline Decoding

    /**
     Decodes a polyline string into an array of LocationPoint.
     This implementation correctly handles the precision conversion from MOTIS (1e7)
     to TripKit's LocationPoint (1e6).
     - Parameter encodedString: The polyline string to decode.
     - Returns: An array of `LocationPoint` or `nil` if the string is invalid or empty.
    */
    internal func decodePolyline(_ encodedString: String?) -> [LocationPoint]? {
        guard let encodedString = encodedString, !encodedString.isEmpty else { return nil }

        let bytes = Array(encodedString.utf8)
        var index = 0
        var points: [LocationPoint] = []
        
        var lat: Int32 = 0
        var lon: Int32 = 0

        while index < bytes.count {
            // Decode latitude delta from polyline (raw precision 7 value)
            let (latDelta, newIndexAfterLat) = decodeSingleValue(from: bytes, at: index)
            lat += latDelta
            index = newIndexAfterLat

            guard index < bytes.count else { break }

            // Decode longitude delta from polyline (raw precision 7 value)
            let (lonDelta, newIndexAfterLon) = decodeSingleValue(from: bytes, at: index)
            lon += lonDelta
            index = newIndexAfterLon

            // --- THIS IS THE FIX ---
            
            // 1. Scale the raw precision 7 integers down to precision 6 by dividing by 10.
            let scaledLat = Int(round(Double(lat) / 10.0))
            let scaledLon = Int(round(Double(lon) / 10.0))
            
            // 2. Create the LocationPoint without swapping the coordinates.
            // Pass the scaled latitude to the `lat` parameter and longitude to the `lon` parameter.
            points.append(LocationPoint(lat: scaledLat, lon: scaledLon))
        }

        return points.isEmpty ? nil : points
    }

    // The helper function `decodeSingleValue` remains unchanged as it is correct.
    private func decodeSingleValue(from bytes: [UInt8], at index: Int) -> (delta: Int32, newIndex: Int) {
        var currentIndex = index
        var result: Int32 = 0
        var shift: UInt = 0

        while currentIndex < bytes.count {
            let byte = bytes[currentIndex]
            let value = Int32(byte) - 63
            result |= (value & 0x1F) << shift
            shift += 5
            currentIndex += 1
            if (value & 0x20) == 0 {
                break
            }
        }
        
        let delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        return (delta, currentIndex)
    }
    
    // MARK: - Utility Functions

        private func calculateBoundingBox(center: LocationPoint, radiusMeters: Double) -> ((Double, Double), (Double, Double))? {
            let centerLatDeg = Double(center.lat) / 1_000_000.0
            let centerLonDeg = Double(center.lon) / 1_000_000.0

            // Approximate conversions - good enough for typical nearby searches
            let metersPerDegreeLat = 111132.954
            let metersPerDegreeLon = metersPerDegreeLat * cos(centerLatDeg * .pi / 180.0)

            guard metersPerDegreeLon > 0 else { return nil } // Avoid division by zero at poles

            let deltaLat = radiusMeters / metersPerDegreeLat
            let deltaLon = radiusMeters / metersPerDegreeLon

            let minLat = centerLatDeg - deltaLat
            let maxLat = centerLatDeg + deltaLat
            let minLon = centerLonDeg - deltaLon
            let maxLon = centerLonDeg + deltaLon

            // Return ((minLat, minLon), (maxLat, maxLon))
            return ((minLat, minLon), (maxLat, maxLon))
        }
}

// Helper extension for nilIfEmpty
extension String {
    var nilIfEmpty: String? {
        return self.isEmpty ? nil : self
    }
}

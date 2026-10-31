import Foundation
import FoundationXML

/// Parses GPX trkpt/rtept coordinates. It never guesses a trail between POIs.
/// Elevation uses the GPX values, or GSI DEM where GPX has no elevation.
enum GPXRouteImporter {
    static func convert(_ data: Data, terrain: Terrain) throws -> Data {
        guard data.count <= 10_000_000 else { throw ImportedRouteError.tooLarge }
        let parser = GPXPointParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldResolveExternalEntities = false
        guard xml.parse(), !parser.invalid, parser.segments <= 1, parser.points.count >= 2,
              parser.points.count <= 100_000 else {
            throw xml.parserError ?? ImportedRouteError.invalid
        }

        let originals = parser.points
        // Gaps are not rendered as invented paths. Multi-segment tracks are rejected.
        for index in 1..<originals.count {
            let a = originals[index-1], b = originals[index]
            let distance = Fix(date: .distantPast, latitude: a.latitude,
                               longitude: a.longitude, altitude: nil, accuracy: 0)
                .distance(to: Fix(date: .distantPast, latitude: b.latitude,
                                  longitude: b.longitude, altitude: nil, accuracy: 0))
            guard distance <= 400 else { throw ImportedRouteError.invalid }
        }
        let strideSize = max(1,Int(ceil(Double(originals.count)/1600)))
        var selected = Swift.stride(from:0,to:originals.count,by:strideSize).map { originals[$0] }
        if let final=originals.last, selected.last?.latitude != final.latitude ||
                                     selected.last?.longitude != final.longitude {
            selected.append(final)
        }
        var points:[[String:Any]] = []
        points.reserveCapacity(selected.count)
        for value in selected {
            guard let grid = terrain.grid(latitude:value.latitude,longitude:value.longitude),
                  let ground = terrain.height(x:grid.x,y:grid.y) else {
                throw ImportedRouteError.outOfRegion
            }
            let elevation = value.elevation ?? ground
            points.append(["latitude":value.latitude,"longitude":value.longitude,
                           "altitude":elevation])
        }

        let fixes=selected.map { value in Fix(date:.distantPast,latitude:value.latitude,
                                             longitude:value.longitude,altitude:nil,accuracy:0) }
        var landmarks:[[String:Any]]=[]
        for landmark in HannoLandmarks.ordered {
            let target=Fix(date:.distantPast,latitude:landmark.latitude,
                           longitude:landmark.longitude,altitude:nil,accuracy:0)
            guard let best=fixes.indices.min(by:{
                fixes[$0].distance(to:target)<fixes[$1].distance(to:target)
            }), fixes[best].distance(to:target)<=400 else {continue}
            let ground = terrain.grid(latitude: landmark.latitude,
                                      longitude: landmark.longitude).flatMap {
                terrain.height(x: $0.x, y: $0.y)
            }
            let h = ground ?? (points[best]["altitude"] as? Double ?? 0)
            landmarks.append(["name":landmark.name,"pointIndex":best,
                              "position":["latitude":landmark.latitude,
                                          "longitude":landmark.longitude,
                                          "altitude":h]])
        }
        landmarks.sort { ($0["pointIndex"] as? Int ?? 0) < ($1["pointIndex"] as? Int ?? 0) }

        let payload:[String:Any]=[
            "id":ImportedRouteStore.id,
            "name":"飯能コース（読み込んだGPX）",
            "points":points,
            "landmarks":landmarks
        ]
        let output=try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys])
        _ = try ImportedRouteStore.validate(output)
        return output
    }
}

private struct ParsedGPXPoint {
    let latitude:Double
    let longitude:Double
    var elevation:Double?
}

private final class GPXPointParser:NSObject,XMLParserDelegate {
    var points:[ParsedGPXPoint]=[]
    var invalid=false
    var segments=0
    private var active:ParsedGPXPoint?
    private var inElevation=false
    private var characters=""

    func parser(_ parser:XMLParser,didStartElement elementName:String,
                namespaceURI:String?,qualifiedName qName:String?,
                attributes attributeDict:[String:String]) {
        let name=elementName.components(separatedBy:":").last ?? elementName
        if name=="trkseg" {segments+=1}
        if name=="trkpt" || name=="rtept" {
            guard let latText=attributeDict["lat"],let lonText=attributeDict["lon"],
                  let latitude=Double(latText),let longitude=Double(lonText),
                  latitude.isFinite,longitude.isFinite,abs(latitude)<=90,abs(longitude)<=180
            else {invalid=true;return}
            active=ParsedGPXPoint(latitude:latitude,longitude:longitude,elevation:nil)
        }
        if name=="ele", active != nil {inElevation=true;characters=""}
    }

    func parser(_ parser:XMLParser,foundCharacters string:String) {
        if inElevation {characters+=string}
    }

    func parser(_ parser:XMLParser,didEndElement elementName:String,
                namespaceURI:String?,qualifiedName qName:String?) {
        let name=elementName.components(separatedBy:":").last ?? elementName
        if name=="ele",inElevation {
            if let value=Double(characters.trimmingCharacters(in:.whitespacesAndNewlines)),
               value.isFinite {
                active?.elevation=value
            }
            inElevation=false
        }
        if name=="trkpt" || name=="rtept" {
            if let active {points.append(active)}
            self.active=nil
        }
    }
}

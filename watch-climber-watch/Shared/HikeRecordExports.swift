import Foundation

/// Lossless formats for taking an iPhone/Watch recorded hike to a PC.
/// Nothing here mutates an original hike record. No artificial edges are added.
enum HikeRecordExports {
    private static func iso(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }

    private static func segments(_ record: HikeRecord) -> [[HikeRecord.Point]] {
        var output: [[HikeRecord.Point]] = []
        var current: [HikeRecord.Point] = []
        for point in record.points {
            guard point.fix.usable else {
                if !current.isEmpty { output.append(current) }
                current = []
                continue
            }
            if point.breakBefore && !current.isEmpty {
                output.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { output.append(current) }
        return output
    }

    static func gpx(_ record: HikeRecord) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Watch Climber" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "<trk><name>Watch Climber recorded hike</name>"
        ]
        for segment in segments(record) {
            lines.append("<trkseg>")
            for point in segment {
                let fix = point.fix
                lines.append(String(format: #"<trkpt lat="%.8f" lon="%.8f">"#,
                                    fix.latitude, fix.longitude))
                if let altitude = fix.altitude, altitude.isFinite {
                    lines.append(String(format: "<ele>%.2f</ele>", altitude))
                }
                lines.append("<time>\(iso(fix.date))</time></trkpt>")
            }
            lines.append("</trkseg>")
        }
        lines.append("</trk></gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func csv(_ record: HikeRecord) -> String {
        var lines = ["timestamp_utc,latitude,longitude,altitude_m,gps_accuracy_m,segment_start"]
        for point in record.points where point.fix.usable {
            let fix = point.fix
            let elevation = fix.altitude.map { String(format: "%.2f", $0) } ?? ""
            lines.append([
                iso(fix.date),
                String(format: "%.8f", fix.latitude),
                String(format: "%.8f", fix.longitude),
                elevation,
                String(format: "%.2f", fix.accuracy),
                point.breakBefore ? "true" : "false"
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func geoJSON(_ record: HikeRecord) throws -> Data {
        var features: [[String: Any]] = []
        for segment in segments(record) {
            let coordinates: [[Double]] = segment.map { point in
                let fix = point.fix
                if let altitude = fix.altitude, altitude.isFinite {
                    return [fix.longitude, fix.latitude, altitude]
                }
                return [fix.longitude, fix.latitude]
            }
            if segment.count >= 2 {
                features.append([
                    "type": "Feature",
                    "geometry": ["type": "LineString", "coordinates": coordinates],
                    "properties": ["source": "Watch Climber", "record_id": record.id.uuidString]
                ])
            } else if let coordinate = coordinates.first {
                features.append([
                    "type": "Feature",
                    "geometry": ["type": "Point", "coordinates": coordinate],
                    "properties": ["source": "Watch Climber", "record_id": record.id.uuidString]
                ])
            }
        }
        let body: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Generated copies are stored under the app's PCExports/ directory. The
    /// original current-phone-hike.json / Watch raw JSON is never rewritten.
    static func save(_ record: HikeRecord, under documents: URL) throws -> [String: URL] {
        let directory = documents.appendingPathComponent("PCExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let prefix = "watch-climber-\(record.id.uuidString.lowercased())"
        let data: [(String, Data)] = [
            ("gpx", Data(gpx(record).utf8)),
            ("csv", Data(csv(record).utf8)),
            ("geojson", try geoJSON(record))
        ]
        var result: [String: URL] = [:]
        for (extensionName, bytes) in data {
            let url = directory.appendingPathComponent("\(prefix).\(extensionName)")
            try bytes.write(to: url, options: .atomic)
            result[extensionName] = url
        }
        return result
    }
}

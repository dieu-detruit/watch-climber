import Foundation

/// Publicly mapped places for the user's Hanno itinerary.
/// These are independent POIs. Joining them with straight lines would be unsafe.
struct HannoLandmark {
    let name: String
    let shortName: String
    let latitude: Double
    let longitude: Double
}

enum HannoLandmarks {
    static let ordered: [HannoLandmark] = [
        HannoLandmark(name: "飯能駅", shortName: "飯能駅", latitude: 35.851151, longitude: 139.3188662),
        HannoLandmark(name: "吾妻峡・ドレミファ橋", shortName: "吾妻峡", latitude: 35.8592849, longitude: 139.294442),
        HannoLandmark(name: "多峯主山", shortName: "多峯主山", latitude: 35.868068, longitude: 139.298168),
        HannoLandmark(name: "天覧山", shortName: "天覧山", latitude: 35.861956, longitude: 139.308293),
        HannoLandmark(name: "宮沢湖温泉 喜楽里別邸", shortName: "宮沢湖温泉", latitude: 35.8729967, longitude: 139.3322511)
    ]
}

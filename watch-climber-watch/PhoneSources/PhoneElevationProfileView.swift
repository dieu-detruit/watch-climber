import SwiftUI

/// Touch-first counterpart to the Watch elevation profile.
/// A planned profile is shown only when a real, ordered route exists.
struct PhoneElevationProfileView: View {
    let route: PlannedRoute?
    let display: RouteDisplayContext?
    let record: HikeRecord
    let terrain: Terrain?
    @Binding var inspection: RouteInspection

    private func inspect(_ x: CGFloat, width: CGFloat, total: Double) {
        guard width > 10 else { return }
        inspection.inspect(max(0,min(1,Double(x/width)))*total,totalM:total)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing:16) {
                if let route,let display {
                    Text(route.name).font(.headline)
                    HStack {
                        Text(display.isInspecting ? "先読み" : (display.isOnCourse ? "現在付近" : "計画"))
                            .foregroundStyle(display.isInspecting ? .orange : .mint)
                        Text(String(format:"%.2f / %.2f km",display.position.distanceM/1000,route.totalM/1000))
                        Spacer()
                        Text(display.position.point.altitude.map{"\(Int($0)) m"} ?? "—")
                    }
                    if let next=route.nextLandmark(after:display.position.distanceM) {
                        Text("次の地点: \(next.name) · 残り \(Int(max(0,route.landmarkDistance(next)-display.position.distanceM))) m")
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    GeometryReader { geometry in
                        Canvas { context,size in
                            let heights=route.points.compactMap(\.altitude)
                            guard let low=heights.min(),let high=heights.max() else {return}
                            let span=max(1,high-low),top=26.0,bottom=Double(size.height)-18
                            func projected(_ distance:Double,_ h:Double)->CGPoint {
                                CGPoint(x:distance/route.totalM*Double(size.width),
                                        y:bottom-(h-low)/span*(bottom-top))
                            }
                            for h in [low,high] {
                                let y=projected(0,h).y
                                var line=Path()
                                line.move(to:CGPoint(x:0,y:y));line.addLine(to:CGPoint(x:size.width,y:y))
                                context.stroke(line,with:.color(.gray.opacity(0.5)),lineWidth:1)
                                context.draw(Text("\(Int(h))m").font(.caption2),
                                             at:CGPoint(x:30,y:y-10))
                            }
                            var path=Path(),connected=false
                            for (i,point) in route.points.enumerated() {
                                guard let h=point.altitude else {connected=false;continue}
                                let p=projected(route.distances[i],h)
                                if connected {path.addLine(to:p)}else{path.move(to:p)}
                                connected=true
                            }
                            context.stroke(path,with:.color(.primary),lineWidth:2)
                            for landmark in route.landmarks {
                                let d=route.landmarkDistance(landmark)
                                guard let h=route.position(at:d).point.altitude else {continue}
                                let p=projected(d,h)
                                context.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(.orange))
                            }
                            func marker(_ distance:Double,color:Color,guide:Bool) {
                                guard let h=route.position(at:distance).point.altitude else{return}
                                let p=projected(distance,h)
                                if guide {
                                    var line=Path();line.move(to:CGPoint(x:p.x,y:0));line.addLine(to:CGPoint(x:p.x,y:size.height))
                                    context.stroke(line,with:.color(color.opacity(0.7)),
                                                   style:StrokeStyle(lineWidth:1,dash:[4,3]))
                                }
                                context.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(color))
                            }
                            if let live=display.profileCurrentDistanceM {marker(live,color:.mint,guide:false)}
                            if display.isInspecting {marker(display.position.distanceM,color:.orange,guide:true)}
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:0)
                            .onChanged { gesture in inspect(gesture.location.x,width:geometry.size.width,total:route.totalM) })
                        .accessibilityLabel("コース標高断面。指を左右に動かして先読み")
                    }
                    .frame(height:240)
                    HStack{
                        Text("0 km")
                        Spacer()
                        Text(String(format:"%.1f km",route.totalM/1000))
                    }.font(.caption).foregroundStyle(.secondary)
                    Slider(value:Binding(
                        get:{display.position.distanceM},
                        set:{inspection.inspect($0,totalM:route.totalM)}
                    ),in:0...max(route.totalM,1))
                    HStack {
                        Button("前の地点") {jump(route:route,distance:display.position.distanceM,forward:false)}
                        Spacer()
                        Button("GPSへ"){inspection.followGPS()}
                            .disabled(!display.isInspecting)
                        Spacer()
                        Button("次の地点"){jump(route:route,distance:display.position.distanceM,forward:true)}
                    }.buttonStyle(.bordered)
                    Text("橙：先読み位置　緑：GPSのコース上推定位置")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("登山の標高断面").font(.headline)
                    Text("今回の飯能の予定ルートは、正確なGPX軌跡がまだありません。地点間を直線で結んだ偽の断面は表示しません。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if terrain?.name.hasPrefix("飯能")==true {
                        ForEach(HannoLandmarks.ordered.indices,id: \.self) { index in
                            let landmark = HannoLandmarks.ordered[index]
                            HStack {
                                Text(landmark.name)
                                Spacer()
                                if let terrain,
                                   let p=terrain.grid(latitude:landmark.latitude,longitude:landmark.longitude),
                                   let h=terrain.height(x:p.x,y:p.y) {
                                    Text("地表 \(Int(h))m").foregroundStyle(.secondary)
                                }
                            }.font(.subheadline)
                        }
                    }
                }
                RecordedElevationProfile(record:record)
            }.padding()
        }
    }

    private func jump(route:PlannedRoute,distance:Double,forward:Bool) {
        let candidates=route.landmarks.filter {
            forward ? route.landmarkDistance($0)>distance+1 : route.landmarkDistance($0)<distance-1
        }
        if let landmark=forward ? candidates.first : candidates.last {
            inspection.inspect(route.landmarkDistance(landmark),totalM:route.totalM)
        }
    }
}

private struct RecordedElevationProfile:View {
    let record:HikeRecord
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("実測GPS標高").font(.headline)
            if record.points.count<2 {
                Text("記録を開始すると、ここに標高の推移が表示されます。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                let points=record.points
                let elevations=points.compactMap { $0.fix.altitude }
                if points.count>1 && elevations.count>1 {
                    Canvas { context,size in
                        let low=elevations.min() ?? 0
                        let high=elevations.max() ?? low+1
                        let start=points[0].fix.date.timeIntervalSince1970
                        let span=max(1,points[points.count-1].fix.date.timeIntervalSince1970-start)
                        var path=Path()
                        var connected=false
                        for p in points {
                            guard let altitude=p.fix.altitude else {connected=false;continue}
                            let pt=CGPoint(x:(p.fix.date.timeIntervalSince1970-start)/span*Double(size.width),
                                           y:Double(size.height)-8-(altitude-low)/max(1,high-low)*Double(size.height-20))
                            if p.breakBefore || !connected {path.move(to:pt)}
                            else{path.addLine(to:pt)}
                            connected=true
                        }
                        context.stroke(path,with:.color(.mint),lineWidth:2)
                        context.draw(Text("\(Int(high))m").font(.caption2),at:CGPoint(x:25,y:12))
                        context.draw(Text("\(Int(low))m").font(.caption2),at:CGPoint(x:25,y:size.height-10))
                    }.frame(height:180).background(.black.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius:12))
                }
            }
        }
    }
}

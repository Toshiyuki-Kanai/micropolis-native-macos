// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CityStatusBar: View {
    let frame: CityFrame
    // Cell widths are independent of the strings. Only available width changes
    // the column count; population/funds updates never move adjacent fields.
    private let columns=[GridItem(.adaptive(minimum:144,maximum:144),spacing:8,alignment:.leading)]
    var body: some View {
        LazyVGrid(columns:columns,alignment:.leading,spacing:10) {
            field(L("資金"),value:frame.funds.formatted())
            field(L("人口"),value:frame.populationPending ? "—" : frame.population.formatted())
            field(L("年月"),value:L("%@年%@月",String(frame.year),frame.month+1))
            VStack(alignment:.leading,spacing:4) {
                heading(L("需要"))
                DemandBars(details:frame.details).frame(height:24)
            }.frame(width:144,height:68,alignment:.topLeading)
            field(L("通電 / 未通電の区域"),value:"\(frame.details.powered) / \(frame.details.unpowered)",compactHeading:true)
        }
        .padding(12)
    }
    private func heading(_ text: String, compact: Bool = false) -> some View {
        Text(text).font(.system(size:compact ? 11 : 16)).foregroundStyle(.secondary)
            .lineLimit(compact ? 1 : 2).minimumScaleFactor(compact ? 0.8 : 1).frame(height:38,alignment:.bottomLeading)
    }
    private func field(_ name: String,value: String,compactHeading: Bool = false) -> some View {
        VStack(alignment:.leading,spacing:4) {
            heading(name,compact:compactHeading)
            Text(value).font(.system(size:18,weight:.medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75).help(name+": "+value)
        }.frame(width:144,height:68,alignment:.topLeading)
    }
}

private struct DemandBars: View {
    let details: CityDetails
    var body: some View {
        Canvas { context,size in
            let values=[details.residentialDemand,details.commercialDemand,details.industrialDemand]
            let colors: [Color]=[.green,.blue,.orange]
            let center=size.height/2
            context.stroke(Path(CGRect(x:0,y:center,width:size.width,height:0)),with:.color(.secondary),lineWidth:1)
            for i in 0..<3 {
                let demand=Double(values[i])/2000
                let height=min(1,abs(demand))*center
                let rect=CGRect(x:Double(i)*12+2,y:demand>=0 ? center-height : center,width:8,height:height)
                context.fill(Path(rect),with:.color(colors[i]))
            }
        }.frame(width:36,height:28)
        .help(L("需要: 住宅 %@、商業 %@、工業 %@",details.residentialDemand,details.commercialDemand,details.industrialDemand))
        .accessibilityLabel(L("住宅・商業・工業の需要"))
    }
}

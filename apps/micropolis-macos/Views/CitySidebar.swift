// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CitySidebar: View {
    @Bindable var model: CityModel
    @Environment(\.colorScheme) private var colorScheme
    private var sidebarBackground: Color { Color(white:colorScheme == .dark ? 0.22 : 0.92) }
    @State private var overviewDrag=OverviewDrag()
    var body: some View {
        VSplitView {
            List(selection:Binding<BuildTool?>(get:{ model.tool },set:{ if let tool=$0 { model.tool=tool } })) {
                Section(L("建設ツール")) {
                    ForEach(BuildTool.allCases) { tool in
                        Label(tool.title,systemImage:tool.symbol).tag(tool)
                            .font(.system(size:13))
                            .frame(height:22)
                            .listRowInsets(EdgeInsets(top:0,leading:8,bottom:0,trailing:8))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(sidebarBackground)
            .frame(minHeight:100,idealHeight:500,maxHeight:.infinity)
            .environment(\.defaultMinListRowHeight,24)
            .controlSize(.small)
            .disabled(!model.acceptsMapInput)
            .accessibilityLabel(L("建設ツール"))
            if model.showOverview, let frame=model.frame {
                VStack(alignment:.leading,spacing:8) {
                    Text(L("概観マップ")).font(.headline)
                    GeometryReader { proxy in
                        let g=MapGeometry(size:proxy.size)
                        ZStack {
                            Color.clear
                            CivicMapCanvas(frame:frame,geometry:g,layer:model.mapLayer,values:model.overlayValues,overview:true)
                            let viewport=model.overviewViewport
                            let rect=CGRect(x:g.rect.minX+viewport.minX*g.tileSize,y:g.rect.minY+viewport.minY*g.tileSize,
                                            width:viewport.width*g.tileSize,height:viewport.height*g.tileSize)
                            Path(rect).stroke(.white,lineWidth:1.5).allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:0).onChanged { value in
                            if let point=overviewDrag.center(start:value.startLocation,current:value.location,geometry:g,viewport:model.overviewViewport) {
                                model.overviewCenter=point
                            }
                        }.onEnded { _ in overviewDrag.end() })
                    }.frame(minHeight:70,maxHeight:.infinity)
                    .accessibilityLabel(L("概観マップ。クリックまたはドラッグで表示位置を移動。"))
                }.padding(12).frame(minHeight:110,idealHeight:210,maxHeight:.infinity).background(sidebarBackground)
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(sidebarBackground)
    }
}

#if os(macOS)
import SwiftUI

struct SettingsView:View{
    @AppStorage("theme") private var theme="system"
    @AppStorage("flow") private var flow="paged"
    @AppStorage("fit") private var fit="page"
    @AppStorage("spread") private var spread=false
    @AppStorage("rtl") private var rtl=false
    @AppStorage("font") private var font="system"
    @AppStorage("fontSize") private var fontSize=17.0
    @AppStorage("lineHeight") private var lineHeight=1.6
    @AppStorage("margin") private var margin=32.0
    private var appearanceSignature:String{"\(theme)|\(font)|\(fontSize)|\(lineHeight)|\(margin)"}
    var body:some View{Form{
        Section("Appearance"){
            Picker("Theme",selection:$theme){Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}
            Picker("Default fit",selection:$fit){Text("Fit Page").tag("page");Text("Fit Width").tag("width");Text("Actual Size").tag("actual")}
        }
        Section("Reading"){
            Picker("Default layout",selection:$flow){Text("Paged").tag("paged");Text("Continuous").tag("continuous")}
            Toggle("Open in two-page mode",isOn:$spread);Toggle("Right-to-left by default",isOn:$rtl)
        }
        Section("Typography"){
            Picker("Font",selection:$font){Text("System").tag("system");Text("Serif").tag("serif");Text("Sans Serif").tag("sans-serif");Text("Monospace").tag("monospace")}
            LabeledContent("Font size"){Slider(value:$fontSize,in:10...36,step:1).frame(width:190);Text("\(Int(fontSize)) pt").monospacedDigit().frame(width:45)}
            LabeledContent("Line height"){Slider(value:$lineHeight,in:1...2.4,step:0.1).frame(width:190);Text(lineHeight,format:.number.precision(.fractionLength(1))).frame(width:30)}
            LabeledContent("Margin"){Slider(value:$margin,in:0...96,step:8).frame(width:190);Text("\(Int(margin))").monospacedDigit().frame(width:30)}
        }
    }.formStyle(.grouped).padding().frame(width:460)
      .onChange(of:appearanceSignature){_ in NotificationCenter.default.post(name:.leafAppearancePreferencesChanged,object:nil)}}
}
#endif

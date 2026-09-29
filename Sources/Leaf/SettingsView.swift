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
    var body:some View{Form{
        Picker("Theme",selection:$theme){Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}
        Picker("Default layout",selection:$flow){Text("Paged").tag("paged");Text("Continuous").tag("continuous")}
        Picker("Default fit",selection:$fit){Text("Fit Page").tag("page");Text("Fit Width").tag("width");Text("Actual Size").tag("actual")}
        Toggle("Two pages",isOn:$spread);Toggle("Right to left",isOn:$rtl)
        Divider()
        Picker("Font",selection:$font){Text("System").tag("system");Text("Serif").tag("serif");Text("Sans Serif").tag("sans-serif");Text("Monospace").tag("monospace")}
        HStack{Text("Font size");Slider(value:$fontSize,in:10...36,step:1);Text("\(Int(fontSize)) pt").monospacedDigit().frame(width:45)}
        HStack{Text("Line height");Slider(value:$lineHeight,in:1...2.4,step:0.1);Text(lineHeight,format:.number.precision(.fractionLength(1))).frame(width:30)}
        HStack{Text("Margin");Slider(value:$margin,in:0...96,step:8);Text("\(Int(margin))").monospacedDigit().frame(width:30)}
    }.formStyle(.grouped).padding().frame(width:440)}
}
#endif

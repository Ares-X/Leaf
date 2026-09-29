#if os(macOS)
import SwiftUI

struct SettingsView:View{
    @ObservedObject var state:ReaderState
    var body:some View{Form{
        Picker("Theme",selection:$state.theme){Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}.onChange(of:state.theme){state.setTheme($0)}
        Picker("Default layout",selection:$state.flow){Text("Paged").tag("paged");Text("Continuous").tag("continuous")}.onChange(of:state.flow){UserDefaults.standard.set($0,forKey:"flow")}
        Picker("Default fit",selection:$state.fit){Text("Fit Page").tag("page");Text("Fit Width").tag("width");Text("Actual Size").tag("actual")}.onChange(of:state.fit){UserDefaults.standard.set($0,forKey:"fit")}
        Toggle("Two pages",isOn:$state.spread).onChange(of:state.spread){UserDefaults.standard.set($0,forKey:"spread")};Toggle("Right to left",isOn:$state.rtl).onChange(of:state.rtl){UserDefaults.standard.set($0,forKey:"rtl")}
        Divider()
        Picker("Font",selection:$state.font){Text("System").tag("system");Text("Serif").tag("serif");Text("Sans Serif").tag("sans-serif");Text("Monospace").tag("monospace")}.onChange(of:state.font){_ in state.applyTypography()}
        HStack{Text("Font size");Slider(value:$state.fontSize,in:10...36,step:1).onChange(of:state.fontSize){_ in state.applyTypography()};Text("\(Int(state.fontSize)) pt").monospacedDigit().frame(width:45)}
        HStack{Text("Line height");Slider(value:$state.lineHeight,in:1...2.4,step:0.1).onChange(of:state.lineHeight){_ in state.applyTypography()};Text(state.lineHeight,format:.number.precision(.fractionLength(1))).frame(width:30)}
        HStack{Text("Margin");Slider(value:$state.margin,in:0...96,step:8).onChange(of:state.margin){_ in state.applyTypography()};Text("\(Int(state.margin))").monospacedDigit().frame(width:30)}
    }.formStyle(.grouped).padding().frame(width:440)}
}
#endif

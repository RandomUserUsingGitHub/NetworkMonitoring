import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var model: NetworkStateModel
    @Environment(\.dismiss) private var dismiss
    @State private var restartPending = false

    var t: AppTheme { AppTheme.named(settings.theme) }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Text("⚙️  Settings")
                            .font(.system(size:18, weight:.bold, design:.monospaced)).foregroundStyle(t.accent2)
                        Spacer()
                        Button("Close") { dismiss() }
                            .font(.system(size:12, design:.monospaced)).foregroundStyle(t.dim).buttonStyle(.plain)
                    }

                    pingSection
                    graphSection
                    ipSection
                    notifSection
                    appearSection
                    systemSection
                    applyRow
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 640)
    }

    // MARK: - Ping

    private var pingSection: some View {
        SSection(title:"PING", theme:t) {
            SRow(label:"Host", theme:t) {
                TextField("8.8.8.8", text:$settings.pingHost)
                    .textFieldStyle(.plain).font(.system(size:13,design:.monospaced)).foregroundStyle(t.text)
                    .frame(width:140).onChange(of:settings.pingHost){_ in restartPending=true}
            }
            SRow(label:"Interval (sec)", theme:t) {
                DStepper(value:$settings.pingInterval, range:0.5...60, step:0.5, fmt:"%.1f")
                    .onChange(of:settings.pingInterval){_ in restartPending=true}
            }
            SRow(label:"Timeout (sec)", theme:t) {
                DStepper(value:$settings.pingTimeout, range:0.5...30, step:0.5, fmt:"%.1f")
                    .onChange(of:settings.pingTimeout){_ in restartPending=true}
            }
            SRow(label:"Fail threshold", theme:t) {
                IStepper(value:$settings.failThreshold, range:1...20)
                    .onChange(of:settings.failThreshold){_ in restartPending=true}
            }
            SRow(label:"Packet size (bytes)", theme:t) {
                IStepper(value:$settings.packetSize, range:8...65507)
                    .onChange(of:settings.packetSize){_ in restartPending=true}
            }
            SRow(label:"History size", theme:t) {
                IStepper(value:$settings.historySize, range:10...500)
                    .onChange(of:settings.historySize){_ in restartPending=true}
            }
        }
    }

    // MARK: - Graph / color thresholds

    private var graphSection: some View {
        SSection(title:"GRAPH COLOR RANGES", theme:t) {
            // Visual legend
            HStack(spacing:0) {
                RoundedRectangle(cornerRadius:3).fill(t.graphOk) .frame(height:6)
                RoundedRectangle(cornerRadius:3).fill(t.graphMid).frame(height:6)
                RoundedRectangle(cornerRadius:3).fill(t.graphBad).frame(height:6)
            }
            .padding(.horizontal,14).padding(.top,10)

            HStack(spacing: 8) {
                Text("0ms").font(.system(size:9,design:.monospaced)).foregroundStyle(t.graphOk)
                Spacer()
                Text("Good → Warn").font(.system(size:9,design:.monospaced)).foregroundStyle(t.dim)
                Spacer()
                Text("Warn → Bad").font(.system(size:9,design:.monospaced)).foregroundStyle(t.dim)
                Spacer()
                Text("∞").font(.system(size:9,design:.monospaced)).foregroundStyle(t.graphBad)
            }
            .padding(.horizontal,14).padding(.bottom,4)

            SRow(label:"Good threshold (ms)", theme:t) {
                DStepper(value:$settings.thresholdGood, range:10...2000, step:10, fmt:"%.0f")
            }
            SRow(label:"Warn threshold (ms)", theme:t) {
                DStepper(value:$settings.thresholdWarn, range:10...2000, step:10, fmt:"%.0f")
            }
            SRow(label:"Graph width (points)", theme:t) {
                IStepper(value:$settings.graphWidth, range:20...300)
            }
        }
    }

    // MARK: - IP

    private var ipSection: some View {
        SSection(title:"IP MONITORING", theme:t) {
            SRow(label:"Check interval (sec)", theme:t) {
                DStepper(value:$settings.ipInterval, range:5...300, step:5, fmt:"%.0f")
                    .onChange(of:settings.ipInterval){_ in restartPending=true}
            }
            SRow(label:"Censor IP in notifications", theme:t) {
                Toggle("", isOn:$settings.censorIPOnChange).toggleStyle(.switch).labelsHidden()
                    .onChange(of:settings.censorIPOnChange){_ in restartPending=true}
            }
        }
    }

    // MARK: - Notifications

    private var notifSection: some View {
        SSection(title:"NOTIFICATIONS", theme:t) {
            SRow(label:"Enabled", theme:t) {
                Toggle("",isOn:$settings.notificationsEnabled).toggleStyle(.switch).labelsHidden()
            }
            SRow(label:"Sound", theme:t) {
                Picker("",selection:$settings.notificationSound) {
                    ForEach(["Basso","Blow","Bottle","Frog","Funk","Glass","Hero","Morse","Ping","Pop","Purr","Sosumi","Submarine","Tink"],id:\.self){
                        Text($0).tag($0)
                    }
                }.pickerStyle(.menu).labelsHidden().frame(width:120)
            }
            if settings.isMuted {
                SRow(label: "Outage Muted Until", theme: t) {
                    HStack {
                        Text(settings.muteOutagesUntil, style: .time)
                            .foregroundStyle(t.warn)
                            .font(.system(size: 11, weight: .bold))
                        Button("Revert") {
                            settings.muteOutagesUntil = Date.distantPast
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(t.bg2).cornerRadius(4)
                    }
                }
            } else {
                SRow(label: "Mute Outages", theme: t) {
                    HStack(spacing: 8) {
                        Button("1 Hour") { settings.muteOutagesUntil = Date().addingTimeInterval(3600) }
                            .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 3).background(t.bg2).cornerRadius(4)
                        Button("24 Hours") { settings.muteOutagesUntil = Date().addingTimeInterval(86400) }
                            .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 3).background(t.bg2).cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearSection: some View {
        SSection(title:"APPEARANCE", theme:t) {
            SRow(label: "Show Menu Bar Icon", theme: t) {
                Toggle("", isOn: $settings.showTrayIcon).toggleStyle(.switch)
            }
            if settings.showTrayIcon {
                SRow(label: "Menu Bar Format", theme: t) {
                    Picker("",selection: $settings.trayFormat) {
                        Text("Icon Only").tag("icon")
                        Text("Ping Only").tag("ping")
                        Text("Icon + Ping").tag("both")
                        Text("Status Text").tag("status")
                    }.pickerStyle(.menu).frame(width: 140)
                }
            }
            SRow(label:"Theme", theme:t) {
                Picker("",selection:$settings.theme) {
                    Text("Green").tag("green"); Text("Amber").tag("amber")
                    Text("Blue").tag("blue");   Text("Red").tag("red")
                }.pickerStyle(.segmented).frame(width:200)
            }
            SRow(label:"Event log lines", theme:t) { IStepper(value:$settings.logTailLines, range:3...20) }
            SRow(label:"Subtitle text", theme:t) {
                TextField("by Armin Hashemi", text:$settings.subtitleText)
                    .textFieldStyle(.plain).font(.system(size:13,design:.monospaced)).foregroundStyle(t.text)
                    .frame(width:180)
            }
        }
    }

    // MARK: - System

    private var systemSection: some View {
        SSection(title:"SYSTEM", theme:t) {
            SRow(label:"Start daemon at login", theme:t) {
                Toggle("",isOn:$settings.launchAtLogin).toggleStyle(.switch).labelsHidden()
            }
        }
    }

    // MARK: - Apply

    private var applyRow: some View {
        HStack {
            if restartPending {
                Text("Daemon restart required to apply ping changes")
                    .font(.system(size:10,design:.monospaced)).foregroundStyle(t.warn)
            }
            Spacer()
            Button(restartPending ? "Apply & Restart" : "Done") {
                settings.save()
                if restartPending { model.restartDaemon(); restartPending=false }
                dismiss()
            }
            .font(.system(size:13,weight:.semibold,design:.monospaced))
            .foregroundStyle(t.bg)
            .padding(.horizontal,16).padding(.vertical,7)
            .background(t.accent)
            .clipShape(RoundedRectangle(cornerRadius:8))
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Shared form components

struct SSection<Content:View>: View {
    let title:String; let theme:AppTheme; @ViewBuilder let content:()->Content
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Text(title).font(.system(size:10,weight:.semibold,design:.monospaced)).foregroundStyle(theme.dim).padding(.bottom,6)
            VStack(spacing:0){content()}.background(theme.bg2)
                .clipShape(RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(theme.border.opacity(0.25),lineWidth:1))
        }
    }
}

struct SRow<Content:View>: View {
    let label:String; let theme:AppTheme; @ViewBuilder let content:()->Content
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(label).font(.system(size:12,design:.monospaced)).foregroundStyle(theme.text)
                Spacer(); content()
            }.padding(.horizontal,14).padding(.vertical,9)
            Divider().overlay(theme.border.opacity(0.1)).padding(.horizontal,14)
        }
    }
}

struct DStepper: View {
    @Binding var value:Double; let range:ClosedRange<Double>; let step:Double; let fmt:String
    var body: some View {
        HStack(spacing:6) {
            Text(String(format:fmt,value)).font(.system(size:13,design:.monospaced)).foregroundStyle(.primary).frame(width:50,alignment:.trailing)
            Stepper("",value:$value,in:range,step:step).labelsHidden().frame(width:80)
        }
    }
}

struct IStepper: View {
    @Binding var value:Int; let range:ClosedRange<Int>
    var body: some View {
        HStack(spacing:6) {
            Text("\(value)").font(.system(size:13,design:.monospaced)).foregroundStyle(.primary).frame(width:50,alignment:.trailing)
            Stepper("",value:$value,in:range).labelsHidden().frame(width:80)
        }
    }
}

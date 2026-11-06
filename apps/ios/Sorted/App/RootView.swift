import SwiftUI

enum AppTab: Hashable {
    case today, bills, lists, settings
}

/// Four tabs, with the "Ask anything" bar pinned above the tab bar on every one.
struct RootView: View {
    @State private var selection = AppTab.today
    @State private var isCapturing = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack { TodayView() }.askBarInset(isCapturing: $isCapturing)
            }
            Tab("Bills", systemImage: "creditcard", value: AppTab.bills) {
                NavigationStack { BillsView() }.askBarInset(isCapturing: $isCapturing)
            }
            Tab("Lists", systemImage: "checklist", value: AppTab.lists) {
                NavigationStack { ListsView() }.askBarInset(isCapturing: $isCapturing)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .askBarAccessory(isCapturing: $isCapturing)
        .sheet(isPresented: $isCapturing) {
            CaptureSheet()
        }
    }
}

private extension View {
    /// iOS 26 and later: the bar is the tab view's bottom accessory.
    @ViewBuilder
    func askBarAccessory(isCapturing: Binding<Bool>) -> some View {
        if #available(iOS 26, *) {
            tabViewBottomAccessory {
                AskBar { isCapturing.wrappedValue = true }
            }
        } else {
            self
        }
    }

    /// iOS 18: an inset at the bottom of each tab, just above the tab bar.
    @ViewBuilder
    func askBarInset(isCapturing: Binding<Bool>) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            safeAreaInset(edge: .bottom) {
                AskBar { isCapturing.wrappedValue = true }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}

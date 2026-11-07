import HomePadCore
import HomePadUI
import SwiftUI

/// The top of the Home app on one compact line: the status chips, the room
/// picker and the Scenes button, so accessories start near the top as in
/// Apple Home. Where the picker would get too little room (portrait on an
/// 11-inch iPad, large text) the status chips take a line of their own.
struct HomeOverviewRow: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Binding var selectedRoom: String?
    /// The least the room picker gets beside the status chips, about three rooms.
    private let minimumPickerWidth: CGFloat = 320

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                status.fixedSize()
                picker.frame(idealWidth: minimumPickerWidth, maxWidth: .infinity, alignment: .leading)
                scenes
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ScrollView(.horizontal, showsIndicators: false) { status }
                    .scrollClipDisabled()
                HStack(spacing: Theme.Spacing.m) {
                    picker
                    scenes
                }
            }
        }
    }

    private var status: some View {
        HomeSummaryChips(accessories: service.accessories.withoutGroups)
    }

    private var picker: some View {
        RoomPicker(rooms: service.orderedRooms, selection: $selectedRoom)
    }

    @ViewBuilder
    private var scenes: some View {
        if !service.scenes.isEmpty {
            ScenesButton().fixedSize()
        }
    }
}

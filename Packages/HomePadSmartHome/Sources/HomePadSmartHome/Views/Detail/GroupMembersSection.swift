import HomePadCore
import HomePadUI
import SwiftUI

/// The accessories inside a group, under the group's controls. Each row
/// controls one member on its own, as in Apple Home.
struct GroupMembersSection: View {
    @Environment(\.detailControlMetrics) private var metrics
    let members: [HomeAccessory]

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("In This Group", systemImage: "square.stack.fill")
            LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
                ForEach(members) { member in
                    CompactAccessoryRow(accessory: member)
                        .frame(height: metrics.memberRow)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import HomePadCore
import HomePadUI
import SwiftUI

/// On an iPhone, in a HomePad's remote, once the iPhone is linked to someone
/// there: Show My Calendars. The person checks which of the iPhone's
/// calendars and reminders lists that HomePad may show while it recognizes
/// them. What they add or check off there is saved on this iPhone.
struct PhoneCalendarsCard: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    @State private var changing: Set<String> = []

    private var sharing: PhoneCalendarServer { connect.calendarSharing }
    private var member: ApprovalMember? { connect.approvals.states[peer.id]?.linkedMember }
    private var homePad: HomePadStatus? { connect.remote.status(of: peer.id) }

    var body: some View {
        if connect.link.identity.kind == .iPhone, let member, let homePad {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Show My Calendars", systemImage: "calendar")
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if homePad.supportsPhoneCalendars {
                        content(member)
                    } else {
                        Text("Update HomePad on \(peer.name) to show the calendars on this iPhone there.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                if let error = sharing.errors[peer.id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
            }
            // Calendars added on the phone since it last looked show up to check.
            .task { sharing.reload() }
        }
    }

    @ViewBuilder
    private func content(_ member: ApprovalMember) -> some View {
        Text("While \(peer.name) recognizes \(member.name), its Calendar, Up Next and Reminders show what you check here, and what you add or check off there is saved on this iPhone. It goes over your home network only, and nobody else at \(peer.name) sees it.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        section("Calendars", kind: .calendars, items: sharing.calendars, hasAccess: sharing.hasEventAccess,
                isDenied: sharing.isEventAccessDenied, choose: "Choose Calendars")
        section("Reminders", kind: .reminders, items: sharing.lists, hasAccess: sharing.hasReminderAccess,
                isDenied: sharing.isReminderAccessDenied, choose: "Choose Lists")
        if !sharing.sharedKinds(with: peer.id).isEmpty {
            if let problem = sharing.wakeProblem {
                Label(problem, systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(peer.name) wakes HomePad on this iPhone over Bluetooth when it recognizes \(member.name), to fetch your calendars and save changes made there. If you force quit HomePad or restart this iPhone, open HomePad once so \(peer.name) can reach it again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let served = sharing.lastServed[peer.id] {
                Text("Last sent \(served.formatted(.relative(presentation: .named))).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One kind: a button that asks for access first, then a switch per calendar or list.
    @ViewBuilder
    private func section(_ title: String, kind: PhoneDataKind, items: [PhoneCalendar], hasAccess: Bool,
                         isDenied: Bool, choose: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(.headline)
            if !hasAccess {
                if isDenied {
                    Text("Allow HomePad full access in Settings, Privacy & Security, \(kind == .reminders ? "Reminders" : "Calendars"), to choose.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button(choose) { Task { await sharing.requestAccess(to: kind, for: peer.id) } }
                        .buttonStyle(.bordered)
                }
            } else if items.isEmpty {
                Text(kind == .reminders ? "There are no lists on this iPhone." : "There are no calendars on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Toggle(isOn: Binding(get: { sharing.isShared(item.id, with: peer.id) }, set: { change($0, item, kind) })) {
                        HStack(spacing: Theme.Spacing.s) {
                            Circle().fill(Color(hex: item.colorHex)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title)
                                if let account = item.accountName {
                                    Text(account).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .disabled(changing.contains(item.id))
                }
            }
        }
    }

    private func change(_ isOn: Bool, _ item: PhoneCalendar, _ kind: PhoneDataKind) {
        changing.insert(item.id)
        Task {
            await sharing.setShared(isOn, item, kind: kind, with: peer.id)
            changing.remove(item.id)
        }
    }
}

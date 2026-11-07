import CommsKit
import SwiftUI

/// The tapbacks on one message, drawn like iMessage: a small round badge per kind that
/// overlaps the bubble's top corner. Give it to `.overlay` of the bubble. It sits on the
/// corner away from the screen edge, so top-trailing for received and top-leading for sent.
struct ReactionBadges: View {
    let reactions: [CommsReaction]
    let isFromMe: Bool

    var body: some View {
        HStack(spacing: -6) {
            ForEach(groups, id: \.kind) { group in
                ReactionBadge(symbol: group.symbol, count: group.count, mine: group.mine)
            }
        }
        .offset(x: isFromMe ? -10 : 10, y: -12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reactions.map(Self.spoken).joined(separator: ", "))
    }

    private struct Group {
        var kind: String
        var symbol: ReactionSymbol
        var count: Int
        var mine: Bool
    }

    /// One group per kind (and per emoji), in the order each first appeared.
    private var groups: [Group] {
        var found: [Group] = []
        for reaction in reactions {
            let kind = reaction.kind == "emoji" ? "emoji:" + (reaction.emoji ?? "") : reaction.kind
            if let index = found.firstIndex(where: { $0.kind == kind }) {
                found[index].count += 1
                found[index].mine = found[index].mine || reaction.isFromMe
            } else {
                found.append(Group(kind: kind, symbol: ReactionSymbol(reaction), count: 1, mine: reaction.isFromMe))
            }
        }
        return found
    }

    private static func spoken(_ reaction: CommsReaction) -> String {
        let who = reaction.isFromMe ? "You" : (reaction.senderName ?? reaction.sender ?? "Someone")
        return "\(who): \(reaction.emoji ?? reaction.kind)"
    }
}

/// What a badge shows inside its circle.
enum ReactionSymbol: Equatable {
    case image(String)
    case word(String)

    init(_ reaction: CommsReaction) {
        switch reaction.kind {
        case "love": self = .image("heart.fill")
        case "like": self = .image("hand.thumbsup.fill")
        case "dislike": self = .image("hand.thumbsdown.fill")
        case "laugh": self = .word("HA HA")
        case "emphasize": self = .word("!!")
        case "question": self = .word("?")
        default: self = .word(reaction.emoji ?? "?")
        }
    }
}

private struct ReactionBadge: View {
    let symbol: ReactionSymbol
    let count: Int
    let mine: Bool

    /// Hearts are pink and everything else blue, so a reaction never reads as a grey blob.
    /// Your own are a deeper blue.
    private var fill: Color {
        if symbol == .image("heart.fill") { return Color(red: 1.0, green: 0.27, blue: 0.4) }
        return mine ? Color.blue : Color(red: 0.25, green: 0.55, blue: 1.0)
    }

    var body: some View {
        HStack(spacing: 2) {
            switch symbol {
            case .image(let name): Image(systemName: name).font(.system(size: 13, weight: .semibold))
            case .word(let text): Text(text).font(.system(size: text.count > 2 ? 9 : 14, weight: .heavy)).minimumScaleFactor(0.6)
            }
            if count > 1 { Text("\(count)").font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, count > 1 ? 7 : 0)
        .frame(minWidth: 28, minHeight: 28)
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 2))
    }
}

extension View {
    /// Puts the message's tapbacks on this view's top corner, when `when` holds and there are any.
    func reactionOverlay(_ message: CommsMessage, when show: Bool = true) -> some View {
        overlay(alignment: message.isFromMe ? .topLeading : .topTrailing) {
            if show, !message.reactions.isEmpty { ReactionBadges(reactions: message.reactions, isFromMe: message.isFromMe) }
        }
    }
}

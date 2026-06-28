import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

// Quantgram: attaches the total message count (and, for groups, per-member
// counts) to the peer info screen data when the corresponding Advanced toggles
// are enabled. Uses the same mechanism as in-app search-by-sender:
// messages.search with limit 1 returns the total count.
func quantgramAttachMessageCounts(context: AccountContext, peerId: EnginePeer.Id, base: Signal<PeerInfoScreenData, NoError>) -> Signal<PeerInfoScreenData, NoError> {
    if !UserDefaults.standard.bool(forKey: "quantgram.showMessageCount") {
        return base
    }

    // Total count for the chat. Emit nil first so the screen isn't delayed by
    // the network request, then the real value.
    let totalCount: Signal<Int?, NoError> = .single(nil)
    |> then(context.engine.messages.getSearchMessageCount(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: ""))

    let lastMemberIds = Atomic<[EnginePeer.Id]>(value: [])
    let lastMemberCounts = Atomic<[EnginePeer.Id: Int]>(value: [:])

    return combineLatest(base, totalCount)
    |> mapToSignal { data, total -> Signal<PeerInfoScreenData, NoError> in
        var memberIds: [EnginePeer.Id] = []
        if UserDefaults.standard.bool(forKey: "quantgram.showPerMemberCount") {
            if let members = data.members, case let .shortList(_, memberList) = members {
                // Cap to avoid a flood of search requests on large groups.
                memberIds = Array(memberList.prefix(50)).map { $0.id }
            }
        }

        // If the member set hasn't changed, reuse cached counts (don't re-query).
        if memberIds == lastMemberIds.with({ $0 }) {
            data.messageCount = total
            let cached = lastMemberCounts.with { $0 }
            data.memberMessageCounts = cached.isEmpty ? nil : cached
            return .single(data)
        }
        let _ = lastMemberIds.swap(memberIds)

        if memberIds.isEmpty {
            let _ = lastMemberCounts.swap([:])
            data.messageCount = total
            data.memberMessageCounts = nil
            return .single(data)
        }

        let perMemberSignals: [Signal<(EnginePeer.Id, Int), NoError>] = memberIds.map { memberId in
            return context.engine.messages.getSearchMessageCount(location: .peer(peerId: peerId, fromId: memberId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "")
            |> map { count -> (EnginePeer.Id, Int) in
                return (memberId, count ?? 0)
            }
        }
        return combineLatest(perMemberSignals)
        |> map { pairs -> PeerInfoScreenData in
            var result: [EnginePeer.Id: Int] = [:]
            for (key, value) in pairs {
                result[key] = value
            }
            let _ = lastMemberCounts.swap(result)
            data.messageCount = total
            data.memberMessageCounts = result.isEmpty ? nil : result
            return data
        }
    }
}

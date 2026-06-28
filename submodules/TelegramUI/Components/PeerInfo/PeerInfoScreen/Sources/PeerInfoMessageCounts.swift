import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

// Quantgram: attaches the total message count to the peer info screen data when
// the "show message count" Advanced toggle is enabled. Uses the same mechanism
// as in-app search: messages.search with limit 1 returns the total count.
func quantgramAttachMessageCounts(context: AccountContext, peerId: EnginePeer.Id, base: Signal<PeerInfoScreenData, NoError>) -> Signal<PeerInfoScreenData, NoError> {
    if !UserDefaults.standard.bool(forKey: "quantgram.showMessageCount") {
        return base
    }

    // Total count for the chat. Emit nil first so the screen isn't delayed by
    // the network request, then the real value.
    let totalCount: Signal<Int?, NoError> = .single(nil)
    |> then(context.engine.messages.getSearchMessageCount(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: ""))

    return combineLatest(base, totalCount)
    |> map { data, total -> PeerInfoScreenData in
        data.messageCount = total
        return data
    }
}

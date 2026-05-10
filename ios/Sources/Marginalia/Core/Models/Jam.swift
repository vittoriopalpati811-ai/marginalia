import Foundation
import SwiftData

// Jam: cerchia di lettura sociale. Solo cache locale, source of truth è Supabase.
@Model
final class Jam {
    var remoteId: String          // Supabase UUID (è la PK qui, non usiamo UUID locale)
    var title: String
    var jamDescription: String?   // 'description' è parola riservata in alcuni contesti
    var bookFilter: String?
    var inviteCode: String
    var isOwner: Bool
    var memberCount: Int
    var syncedAt: Date

    init(
        remoteId: String,
        title: String,
        description: String?,
        bookFilter: String?,
        inviteCode: String,
        isOwner: Bool,
        memberCount: Int
    ) {
        self.remoteId = remoteId
        self.title = title
        self.jamDescription = description
        self.bookFilter = bookFilter
        self.inviteCode = inviteCode
        self.isOwner = isOwner
        self.memberCount = memberCount
        self.syncedAt = Date()
    }
}

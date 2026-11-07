import HomePadCore

/// Messages settings. Stored through `services.settings` like every other module's.
enum CommsSettings {
    /// When on, messages show only for a face-recognized member. Nil until someone chooses,
    /// and then it is on once the household has more than one person, so nobody reads
    /// another person's messages by picking them in People (`CommsRuntime.requiresRecognition`).
    static let requireRecognition = SettingKey<Bool?>("comms.requireRecognition", default: nil)
}

extension CommsSettings {
    /// When on, a new message on the face shows its text. Off by default, because the face
    /// is read from across the room, so it shows only who wrote and "New message".
    static let showPreviewsOnFace = SettingKey<Bool>("comms.showPreviewsOnFace", default: false)
}

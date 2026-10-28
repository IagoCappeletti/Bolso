import Carbon

final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let identifier: UInt32
    private let action: () -> Void
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | shiftKey), identifier: UInt32 = 1, action: @escaping () -> Void) throws {
        self.identifier = identifier
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            guard result == noErr, id.signature == 0x47565441, id.id == hotKey.identifier else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw Failure(status: status) }
        let registration = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x47565441, id: identifier), GetApplicationEventTarget(), 0, &hotKey)
        guard registration == noErr else {
            if let handler { RemoveEventHandler(handler); self.handler = nil }
            throw Failure(status: registration)
        }
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
    struct Failure: Error { let status: OSStatus }
}

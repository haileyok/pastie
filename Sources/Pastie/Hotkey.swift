import Carbon.HIToolbox
import Foundation

final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private let id: UInt32

    private static var registry: [UInt32: Hotkey] = [:]
    private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = Hotkey.nextID
        Hotkey.nextID += 1
        Hotkey.registry[self.id] = self

        let hotKeyID = EventHotKeyID(signature: fourCharCode("PSTE"), id: self.id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &id)
            Hotkey.registry[id.id]?.handler()
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        Hotkey.registry.removeValue(forKey: id)
    }
}

private func fourCharCode(_ s: String) -> FourCharCode {
    var result: FourCharCode = 0
    for ch in s.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(ch)
    }
    return result
}

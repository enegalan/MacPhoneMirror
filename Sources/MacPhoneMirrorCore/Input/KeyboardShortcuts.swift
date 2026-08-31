import Foundation
import AppKit

public struct KeyboardShortcutMapper: Sendable {
    public init() {}
    
    /// Translates macOS NSEvent key code into USB HID keyboard usage code
    public static func hidKeyCode(for macKeyCode: UInt16) -> UInt8? {
        switch macKeyCode {
        case 0: return 0x04   // A
        case 11: return 0x05  // B
        case 8: return 0x06   // C
        case 2: return 0x07   // D
        case 14: return 0x08  // E
        case 3: return 0x09   // F
        case 5: return 0x0A   // G
        case 4: return 0x0B   // H
        case 34: return 0x0C  // I
        case 38: return 0x0D  // J
        case 40: return 0x0E  // K
        case 37: return 0x0F  // L
        case 46: return 0x10  // M
        case 45: return 0x11  // N
        case 31: return 0x12  // O
        case 35: return 0x13  // P
        case 12: return 0x14  // Q
        case 15: return 0x15  // R
        case 1: return 0x16   // S
        case 17: return 0x17  // T
        case 32: return 0x18  // U
        case 9: return 0x19   // V
        case 13: return 0x1A  // W
        case 7: return 0x1B   // X
        case 16: return 0x1C  // Y
        case 6: return 0x1D   // Z
            
        case 18: return 0x1E  // 1
        case 19: return 0x1F  // 2
        case 20: return 0x20  // 3
        case 21: return 0x21  // 4
        case 23: return 0x22  // 5
        case 22: return 0x23  // 6
        case 26: return 0x24  // 7
        case 28: return 0x25  // 8
        case 25: return 0x26  // 9
        case 29: return 0x27  // 0
            
        case 36: return 0x28  // Return
        case 53: return 0x29  // Escape
        case 51: return 0x2A  // Delete / Backspace
        case 48: return 0x2B  // Tab
        case 49: return 0x2C  // Space
        case 123: return 0x50 // Left Arrow
        case 124: return 0x4F // Right Arrow
        case 125: return 0x51 // Down Arrow
        case 126: return 0x52 // Up Arrow
        default:
            return nil
        }
    }
    
    public static func hidModifier(from flags: NSEvent.ModifierFlags) -> UInt8 {
        var mod: UInt8 = 0
        if flags.contains(.control) {
            mod |= KeyModifier.leftControl.rawValue
        }
        if flags.contains(.shift) {
            mod |= KeyModifier.leftShift.rawValue
        }
        if flags.contains(.option) {
            mod |= KeyModifier.leftAlt.rawValue
        }
        if flags.contains(.command) {
            mod |= KeyModifier.leftGUI.rawValue
        }
        return mod
    }
}

import ApplicationServices

extension AXUIElement {
    func value<T>(of attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Reads several attributes in a single IPC round trip. Missing attributes come back as `nil`.
    func values(of attributes: [String]) -> [String: Any] {
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            self, attributes as CFArray, AXCopyMultipleAttributeOptions(), &values
        )
        guard status == .success, let list = values as? [Any], list.count == attributes.count else { return [:] }

        var result: [String: Any] = [:]
        for (attribute, value) in zip(attributes, list) where !Self.isErrorValue(value) {
            result[attribute] = value
        }
        return result
    }

    private static func isErrorValue(_ value: Any) -> Bool {
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return false }
        return AXValueGetType(object as! AXValue) == .axError // swiftlint:disable:this force_cast
    }
}

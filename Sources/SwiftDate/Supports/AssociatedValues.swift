//
//  SwiftDate
//  Parse, validate, manipulate, and display dates, time and timezones in Swift
//
//  Created by Daniele Margutti
//   - Web: https://www.danielemargutti.com
//   - Twitter: https://twitter.com/danielemargutti
//   - Mail: hello@danielemargutti.com
//
//  Copyright © 2019 Daniele Margutti. Licensed under MIT License.
//

import Foundation

private class AssociatedValue {
        weak var _weakValue: AnyObject?
        var _value: Any?

        var value: Any? {
                _weakValue ?? _value
        }

        init(_ value: Any?) {
                _value = value
        }

        init(weak: AnyObject?) {
                _weakValue = weak
        }
}

extension String {
        fileprivate var address: UnsafeRawPointer {
                UnsafeRawPointer(bitPattern: abs(hashValue))!
        }
}

#if canImport(ObjectiveC)
import ObjectiveC.runtime

internal func getAssociatedValue<T>(key: String, object: AnyObject) -> T? {
        (objc_getAssociatedObject(object, key.address) as? AssociatedValue)?.value as? T
}

internal func getAssociatedValue<T>(key: String, object: AnyObject, initialValue: @autoclosure () -> T) -> T {
        getAssociatedValue(key: key, object: object) ?? setAndReturn(initialValue: initialValue(), key: key, object: object)
}

internal func getAssociatedValue<T>(key: String, object: AnyObject, initialValue: () -> T) -> T {
        getAssociatedValue(key: key, object: object) ?? setAndReturn(initialValue: initialValue(), key: key, object: object)
}

private func setAndReturn<T>(initialValue: T, key: String, object: AnyObject) -> T {
        set(associatedValue: initialValue, key: key, object: object)
        return initialValue
}

internal func set<T>(associatedValue: T?, key: String, object: AnyObject) {
        set(associatedValue: AssociatedValue(associatedValue), key: key, object: object)
}

internal func set<T: AnyObject>(weakAssociatedValue: T?, key: String, object: AnyObject) {
        set(associatedValue: AssociatedValue(weak: weakAssociatedValue), key: key, object: object)
}

private func set(associatedValue: AssociatedValue, key: String, object: AnyObject) {
        objc_setAssociatedObject(object, key.address, associatedValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

#else

private final class AssociationStorage {
        static let shared = AssociationStorage()

        private var storage: [ObjectIdentifier: [String: AssociatedValue]] = [:]
        private let lock = NSLock()

        func value(forKey key: String, object: AnyObject) -> AssociatedValue? {
                lock.lock()
                defer { lock.unlock() }
                let identifier = ObjectIdentifier(object)
                return storage[identifier]?[key]
        }

        func set(value: AssociatedValue?, forKey key: String, object: AnyObject) {
                lock.lock()
                defer { lock.unlock() }
                let identifier = ObjectIdentifier(object)
                var values = storage[identifier] ?? [:]
                values[key] = value
                storage[identifier] = values
        }
}

internal func getAssociatedValue<T>(key: String, object: AnyObject) -> T? {
        AssociationStorage.shared.value(forKey: key, object: object)?.value as? T
}

internal func getAssociatedValue<T>(key: String, object: AnyObject, initialValue: @autoclosure () -> T) -> T {
        if let value: T = getAssociatedValue(key: key, object: object) {
                return value
        }
        let value = initialValue()
        set(associatedValue: value, key: key, object: object)
        return value
}

internal func getAssociatedValue<T>(key: String, object: AnyObject, initialValue: () -> T) -> T {
        if let value: T = getAssociatedValue(key: key, object: object) {
                return value
        }
        let value = initialValue()
        set(associatedValue: value, key: key, object: object)
        return value
}

private func setAndReturn<T>(initialValue: T, key: String, object: AnyObject) -> T {
        set(associatedValue: initialValue, key: key, object: object)
        return initialValue
}

internal func set<T>(associatedValue: T?, key: String, object: AnyObject) {
        set(associatedValue: AssociatedValue(associatedValue), key: key, object: object)
}

internal func set<T: AnyObject>(weakAssociatedValue: T?, key: String, object: AnyObject) {
        set(associatedValue: AssociatedValue(weak: weakAssociatedValue), key: key, object: object)
}

private func set(associatedValue: AssociatedValue, key: String, object: AnyObject) {
        AssociationStorage.shared.set(value: associatedValue, forKey: key, object: object)
}

#endif

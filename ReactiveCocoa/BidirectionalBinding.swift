import ReactiveSwift
import Result

infix operator <~>: BindingPrecedence

// `ValueBindable` need not conform to `BindingSource`, since the expected public
// APIs for observing user interactions are still the signals named with plural nouns.

public struct ValueBindable<Value>: ActionBindableProtocol, BindingTargetProvider {
	fileprivate weak var control: AnyObject?
	fileprivate let setEnabled: (AnyObject, Bool) -> Void
	fileprivate let setValue: (AnyObject, Value) -> Void
	fileprivate let values: (AnyObject) -> Signal<Value, NoError>
	fileprivate let actionDidBind: ((AnyObject, ActionStates) -> Void)?

	public var bindingTarget: BindingTarget<Value> {
		let lifetime = control.map(lifetime(of:)) ?? .empty
		return BindingTarget(on: UIScheduler(), lifetime: lifetime) { [weak control, setValue] value in
			if let control = control {
				setValue(control, value)
			}
		}
	}

	public var actionBindable: ActionBindable<Value> {
		guard let control = control else { return ActionBindable() }
		return ActionBindable(control: control, setEnabled: setEnabled, values: values, actionDidBind: actionDidBind)
	}

	fileprivate init() {
		control = nil
		setEnabled = { _ in }
		setValue = { _ in }
		values = { _ in .empty }
		actionDidBind = nil
	}

	public init<Control: AnyObject>(
		control: Control,
		setEnabled: @escaping (Control, Bool) -> Void,
		setValue: @escaping (Control, Value) -> Void,
		values: @escaping (Control) -> Signal<Value, NoError>,
		actionDidBind: ((Control, ActionStates) -> Void)? = nil
	) {
		self.control = control
		self.setEnabled = { setEnabled($0 as! Control, $1) }
		self.setValue = { setValue($0 as! Control, $1) }
		self.values = { values($0 as! Control) }
		self.actionDidBind = actionDidBind.map { action in { action($0 as! Control, $1) } }
	}
}

public struct ActionBindable<Value>: ActionBindableProtocol {
	fileprivate weak var control: AnyObject?
	fileprivate let setEnabled: (AnyObject, Bool) -> Void
	fileprivate let values: (AnyObject) -> Signal<Value, NoError>
	fileprivate let actionDidBind: ((AnyObject, ActionStates) -> Void)?

	public var actionBindable: ActionBindable<Value> {
		return self
	}

	fileprivate init() {
		control = nil
		setEnabled = { _ in }
		values = { _ in .empty }
		actionDidBind = nil
	}

	public init<Control: AnyObject>(
		control: Control,
		setEnabled: @escaping (Control, Bool) -> Void,
		values: @escaping (Control) -> Signal<Value, NoError>,
		actionDidBind: ((Control, ActionStates) -> Void)? = nil
	) {
		self.control = control
		self.setEnabled = { setEnabled($0 as! Control, $1) }
		self.values = { values($0 as! Control) }
		self.actionDidBind = actionDidBind.map { action in { action($0 as! Control, $1) } }
	}
}

public protocol ActionBindableProtocol {
	associatedtype Value

	var actionBindable: ActionBindable<Value> { get }
}

public protocol ActionStates {
	var isEnabled: Property<Bool> { get }
	var isExecuting: Property<Bool> { get }
}

extension Action: ActionStates {}

// MARK: Transformation

extension ActionBindableProtocol {
	public func liftOutput<U>(_ transform: @escaping (Signal<Value, NoError>) -> Signal<U, NoError>) -> ActionBindable<U> {
		let bindable = actionBindable
		guard let control = bindable.control else { return ActionBindable() }
		return ActionBindable(control: control,
		                      setEnabled: bindable.setEnabled,
		                      values: { [values = bindable.values] in transform(values($0)) })
	}

	public func mapOutput<U>(_ transform: @escaping (Value) -> U) -> ActionBindable<U> {
		return liftOutput { $0.map(transform) }
	}

	public func filterOutput(_ transform: @escaping (Value) -> Bool) -> ActionBindable<Value> {
		return liftOutput { $0.filter(transform) }
	}

	public func filterMapOutput<U>(_ transform: @escaping (Value) -> U?) -> ActionBindable<U> {
		return liftOutput { $0.filterMap(transform) }
	}
}

extension ActionBindableProtocol where Value: OptionalProtocol {
	public func skipNilOutput() -> ActionBindable<Value.Wrapped> {
		return liftOutput { $0.skipNil() }
	}
}

// MARK: Value bindings

extension MutablePropertyProtocol {
	public static func <~>(property: Self, bindable: ValueBindable<Value>) -> Disposable? {
		return nil
	}
}

extension ValueBindable {
	public static func <~> <P: MutablePropertyProtocol>(bindable: ValueBindable, property: P) -> Disposable? where P.Value == Value {
		return property <~> bindable
	}
}

// MARK: Action bindings

extension Action {
	public static func <~><Bindable>(action: Action, bindable: Bindable) -> Disposable? where Bindable: ActionBindableProtocol, Bindable.Value == Input {
		return nil
	}
}

extension Action where Input == () {
	public static func <~> <Bindable>(action: Action, bindable: Bindable) -> Disposable? where Bindable: ActionBindableProtocol {
		return nil
	}

	public static func <~> <Bindable>(action: Action, bindable: Bindable) -> Disposable? where Bindable: ActionBindableProtocol, Bindable.Value == () {
		return nil
	}
}

extension ActionBindableProtocol {
	public static func <~> <Output, Error>(bindable: Self, action: Action<Value, Output, Error>) -> Disposable? {
		return action <~> bindable
	}

	public static func <~> <Output, Error>(bindable: Self, action: Action<(), Output, Error>) -> Disposable? {
		return action <~> bindable
	}
}

extension ActionBindableProtocol where Value == () {
	public static func <~> <Output, Error>(bindable: Self, action: Action<(), Output, Error>) -> Disposable? {
		return action <~> bindable
	}
}

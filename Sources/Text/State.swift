import GameToolkit
import SDL3

// SwiftUI's state, for views rebuilt every frame: a view's @State lives in the
// ViewGraph, under the view's identity, from the first frame the view is in to
// the last, and a @Binding reads and writes state that another view keeps.

/// Where a view is: the places of the views it is in, from the root, and its
/// own, which are an index among its siblings with its type, or an id it was
/// given.
struct Identity: Hashable {
    var path: [AnyHashable] = []

    func appending(_ component: AnyHashable) -> Identity {
        Identity(path: path + [component])
    }
}

/// What a view that has the focus is given, in the order it came.
enum InputEvent {
    case key(KeyboardEvent)
    case text(TextInputUpdate)
}

/// Evaluates views into nodes, keeping their state from frame to frame, and
/// what they are given to act on in a frame: its clicks, and the keys and
/// text for the view with the focus, which a click gives.
@MainActor
final class ViewGraph {
    let compositor: Compositor
    let textInput: TextInput
    /// Whether a state has changed since the frame was built, for an app that
    /// does not build a frame until something changes.
    var needsUpdate = true
    /// The clicks of the frame being built, in points: where a mouse button
    /// went down, and where one went up.
    var clicks: [(x: Float, y: Float)] = []
    var releases: [(x: Float, y: Float)] = []
    /// Where the pointer is, in points, if it is over the window.
    var pointer: (x: Float, y: Float)?
    /// The keys and text of the frame being built.
    var inputs: [InputEvent] = []
    /// When the frame is, in seconds, for what blinks or moves.
    var time: Double = 0
    /// The view that has the focus.
    private(set) var focus: Identity?
    private var focusClaimed = false
    private var focusDrawn = false
    // The view a press began on, until the button goes up, and what each
    // interactive view was in the last frame.
    private var pressed: Identity?
    private var interactions: [Identity: Interaction] = [:]

    private var storage: [StateKey: AnyObject] = [:]
    private var visited = Set<StateKey>()

    init(compositor: Compositor, textInput: TextInput) {
        self.compositor = compositor
        self.textInput = textInput
    }

    /// Gives the view at `identity` the focus, as a click on it does.
    func claimFocus(_ identity: Identity) {
        if focus != identity {
            focus = identity
            needsUpdate = true
        }
        focusClaimed = true
    }

    /// Whether the view at `identity` has the focus, which it says when it is
    /// drawn, for the focus to go when the view does.
    func hasFocus(_ identity: Identity) -> Bool {
        guard focus == identity else { return false }
        focusDrawn = true
        return true
    }

    /// Ends the frame, after it is drawn: a click on nothing, or the view's
    /// going, takes the focus away, and text input is on while a view has it.
    func endFrame() throws {
        if !clicks.isEmpty && !focusClaimed || !focusDrawn {
            focus = nil
        }
        if focus != nil && !textInput.isActive {
            try textInput.start()
        } else if focus == nil && textInput.isActive {
            try textInput.stop()
        }
        if !releases.isEmpty {
            pressed = nil
        }
        clicks.removeAll(keepingCapacity: true)
        releases.removeAll(keepingCapacity: true)
        inputs.removeAll(keepingCapacity: true)
        focusClaimed = false
        focusDrawn = false
    }

    /// What the interactive view at `identity` was in the last frame: whether
    /// the pointer was over it, and whether it was pressed.
    func interaction(at identity: Identity) -> Interaction {
        interactions[identity] ?? Interaction()
    }

    /// Has the interactive view at `identity` take this frame's pointer, as it
    /// is drawn from `x`, `y`, `width` by `height`: a button going down on it
    /// presses it, and going up on it while it is pressed runs `action`.
    func interact(
        at identity: Identity, x: Float, y: Float, width: Float, height: Float, action: (() -> Void)?
    ) {
        func contains(_ point: (x: Float, y: Float)) -> Bool {
            (x..<x + width).contains(point.x) && (y..<y + height).contains(point.y)
        }
        if clicks.contains(where: contains) {
            pressed = identity
        }
        let hovered = pointer.map(contains) ?? false
        if pressed == identity, let release = releases.last, contains(release) {
            action?()
        }
        let interaction = Interaction(isHovered: hovered, isPressed: pressed == identity && hovered)
        if interactions[identity] != interaction {
            interactions[identity] = interaction
            needsUpdate = true
        }
    }

    /// The nodes of `root` for this frame. The state of the views that were in
    /// the last frame and are not in this one is gone.
    func update(_ root: some View) -> [any Node] {
        visited.removeAll(keepingCapacity: true)
        needsUpdate = false
        let nodes = resolve([root], in: ResolveContext(graph: self, identity: Identity(), environment: EnvironmentValues()))
        storage = storage.filter { visited.contains($0.key) }
        interactions = interactions.filter { key, _ in visited.contains(StateKey(identity: key, property: -2)) }
        return nodes
    }

    /// The nodes of `views`, each at its place under `context`'s view.
    func resolve(_ views: [any View], in context: ResolveContext) -> [any Node] {
        views.enumerated().flatMap { index, view in
            resolve(view, in: context.appending(Place(index: index, type: ObjectIdentifier(type(of: view)))))
        }
    }

    private func resolve<V: View>(_ view: V, in context: ResolveContext) -> [any Node] {
        // Interactive views are kept by their identities as other state is.
        visited.insert(StateKey(identity: context.identity, property: -2))
        if let primitive = view as? any PrimitiveView {
            return primitive.makeNodes(in: context)
        }
        // Its state, found by its identity and the order of its properties,
        // and its environment go into the copy of it that is evaluated.
        for (index, child) in Mirror(reflecting: view).children.enumerated() {
            if let property = child.value as? any DynamicProperty {
                property.install(
                    in: self, key: StateKey(identity: context.identity, property: index),
                    environment: context.environment)
            }
        }
        return resolve([view.body], in: context)
    }

    /// What a primitive view at `identity` keeps from frame to frame, made
    /// with `initial` the first time.
    func state<Value>(at identity: Identity, initial: Value) -> StateBox<Value> {
        box(StateKey(identity: identity, property: -1), initial: initial)
    }

    // The box of `key`, made with `initial` the first time.
    fileprivate func box<Value>(_ key: StateKey, initial: Value) -> StateBox<Value> {
        visited.insert(key)
        if let box = storage[key] as? StateBox<Value> {
            return box
        }
        let box = StateBox(initial)
        storage[key] = box
        return box
    }
}

// A view's place among its siblings: its index, and its type, for a view of
// another type in the same place to be another view.
private struct Place: Hashable {
    var index: Int
    var type: ObjectIdentifier
}

private struct StateKey: Hashable {
    var identity: Identity
    var property: Int
}

final class StateBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Whether the pointer is over a view, and whether it is pressed.
struct Interaction: Equatable {
    var isHovered = false
    var isPressed = false
}

// A property of a view that the graph gives what it needs before the view's
// body is evaluated: its state, or its environment.
@MainActor
private protocol DynamicProperty {
    func install(in graph: ViewGraph, key: StateKey, environment: EnvironmentValues)
}

/// A value a view keeps from frame to frame, as SwiftUI's @State. It is the
/// initial value until the view is first evaluated in a ViewGraph.
@MainActor
@propertyWrapper
struct State<Value>: DynamicProperty {
    private final class Location {
        var box: StateBox<Value>?
        weak var graph: ViewGraph?
    }

    private let initial: Value
    // Made anew with each copy of the view, and given its box when the copy
    // is evaluated.
    private let location = Location()

    init(wrappedValue: Value) {
        initial = wrappedValue
    }

    var wrappedValue: Value {
        get { location.box?.value ?? initial }
        nonmutating set {
            guard let box = location.box else { return }
            box.value = newValue
            location.graph?.needsUpdate = true
        }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }

    fileprivate func install(in graph: ViewGraph, key: StateKey, environment: EnvironmentValues) {
        location.box = graph.box(key, initial: initial)
        location.graph = graph
    }
}

/// A value of the environment a view is in, as SwiftUI's @Environment.
@MainActor
@propertyWrapper
struct Environment<Value>: DynamicProperty {
    @MainActor
    private final class Location {
        var environment = EnvironmentValues()
    }

    private let keyPath: KeyPath<EnvironmentValues, Value>
    private let location = Location()

    init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    var wrappedValue: Value {
        location.environment[keyPath: keyPath]
    }

    fileprivate func install(in graph: ViewGraph, key: StateKey, environment: EnvironmentValues) {
        location.environment = environment
    }
}

/// Reading and writing a value kept somewhere else, as SwiftUI's @Binding:
/// what $ makes of a @State, and of a part of a Binding's value, which
/// `$value.part` makes.
@MainActor
@propertyWrapper
@dynamicMemberLookup
struct Binding<Value> {
    private let get: () -> Value
    private let set: (Value) -> Void

    init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }

    /// A value nothing can change.
    static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    var projectedValue: Binding<Value> { self }

    subscript<Part>(dynamicMember keyPath: WritableKeyPath<Value, Part>) -> Binding<Part> {
        Binding<Part>(
            get: { get()[keyPath: keyPath] },
            set: { part in
                var value = get()
                value[keyPath: keyPath] = part
                set(value)
            })
    }
}

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

/// Evaluates views into nodes, keeping their state from frame to frame, and
/// what they are given to act on in a frame: the clicks in it.
@MainActor
final class ViewGraph {
    let renderer: TextRenderer
    /// Whether a state has changed since the frame was built, for an app that
    /// does not build a frame until something changes.
    var needsUpdate = true
    /// The clicks of the frame being built, in points.
    var clicks: [(x: Float, y: Float)] = []

    private var storage: [StateKey: AnyObject] = [:]
    private var visited = Set<StateKey>()

    init(renderer: TextRenderer) {
        self.renderer = renderer
    }

    /// The nodes of `root` for this frame. The state of the views that were in
    /// the last frame and are not in this one is gone.
    func update(_ root: some View) -> [any Node] {
        visited.removeAll(keepingCapacity: true)
        needsUpdate = false
        let nodes = resolve([root], at: Identity())
        storage = storage.filter { visited.contains($0.key) }
        return nodes
    }

    /// The nodes of `views`, each at its place under `identity`.
    func resolve(_ views: [any View], at identity: Identity) -> [any Node] {
        views.enumerated().flatMap { index, view in
            resolve(view, at: identity.appending(Place(index: index, type: ObjectIdentifier(type(of: view)))))
        }
    }

    private func resolve<V: View>(_ view: V, at identity: Identity) -> [any Node] {
        if let primitive = view as? any PrimitiveView {
            return primitive.makeNodes(in: self, at: identity)
        }
        // Its state, found by its identity and the order of its properties,
        // goes into the copy of it that is evaluated.
        for (index, child) in Mirror(reflecting: view).children.enumerated() {
            if let property = child.value as? any StateProperty {
                property.install(in: self, key: StateKey(identity: identity, property: index))
            }
        }
        return resolve([view.body], at: identity)
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

private final class StateBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor
private protocol StateProperty {
    func install(in graph: ViewGraph, key: StateKey)
}

/// A value a view keeps from frame to frame, as SwiftUI's @State. It is the
/// initial value until the view is first evaluated in a ViewGraph.
@MainActor
@propertyWrapper
struct State<Value>: StateProperty {
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

    fileprivate func install(in graph: ViewGraph, key: StateKey) {
        location.box = graph.box(key, initial: initial)
        location.graph = graph
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

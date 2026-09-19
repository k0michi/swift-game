import Foundation

private enum AudioConnectionDestination {
    case node(AudioNode, input: UInt32)
    case parameter(AudioParam)
}

private struct AudioConnection {
    let source: ObjectIdentifier
    let output: UInt32
    let destination: AudioConnectionDestination
}

final class AudioGraph {
    private let lock = NSLock()
    private var connections: [AudioConnection] = []

    func connect(source: AudioNode, output: UInt32, destination: AudioNode, input: UInt32) {
        lock.withLock {
            connections.append(AudioConnection(
                source: ObjectIdentifier(source),
                output: output,
                destination: .node(destination, input: input)
            ))
        }
    }

    func connect(source: AudioNode, output: UInt32, destination: AudioParam) {
        lock.withLock {
            connections.append(AudioConnection(
                source: ObjectIdentifier(source),
                output: output,
                destination: .parameter(destination)
            ))
        }
    }

    func disconnect(source: AudioNode) {
        remove { $0.source == ObjectIdentifier(source) }
    }

    func disconnect(source: AudioNode, output: UInt32) {
        remove { $0.source == ObjectIdentifier(source) && $0.output == output }
    }

    func disconnect(source: AudioNode, destination: AudioNode, output: UInt32?, input: UInt32?) {
        remove { connection in
            guard connection.source == ObjectIdentifier(source) else { return false }
            guard output.map({ connection.output == $0 }) ?? true else { return false }
            guard case .node(let node, let destinationInput) = connection.destination else { return false }
            return node === destination && (input.map { destinationInput == $0 } ?? true)
        }
    }

    func disconnect(source: AudioNode, destination: AudioParam, output: UInt32?) {
        remove { connection in
            guard connection.source == ObjectIdentifier(source) else { return false }
            guard output.map({ connection.output == $0 }) ?? true else { return false }
            guard case .parameter(let parameter) = connection.destination else { return false }
            return parameter === destination
        }
    }

    private func remove(where predicate: (AudioConnection) -> Bool) {
        lock.withLock { connections.removeAll(where: predicate) }
    }
}

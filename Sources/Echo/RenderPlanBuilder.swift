struct RenderPlanBuilder {
    let nodes: [AudioNodeID: RenderNodeState]
    let nodeConnections: Set<RenderNodeConnection>
    let paramConnections: Set<RenderParamConnection>

    func build() -> RenderPlan {
        let dependencies = makeDependencies()
        // TODO: Split cyclic DelayNodes into DelayReader and DelayWriter before
        // muting the remaining cyclic strongly connected components.
        let mutedNodeIDs = cyclicNodeIDs(dependencies: dependencies)
        var visited: Set<AudioNodeID> = []
        var order: [AudioNodeID] = []

        func visit(_ id: AudioNodeID) {
            guard !mutedNodeIDs.contains(id), visited.insert(id).inserted else { return }
            for dependency in dependencies[id, default: []] {
                visit(dependency)
            }
            order.append(id)
        }

        for id in nodes.keys {
            visit(id)
        }
        return RenderPlan(order: order, mutedNodeIDs: mutedNodeIDs)
    }

    private func makeDependencies() -> [AudioNodeID: Set<AudioNodeID>] {
        let parameterOwners = nodes.reduce(into: [AudioParamID: AudioNodeID]()) { result, element in
            for parameterID in element.value.processor.parameterIDs {
                result[parameterID] = element.key
            }
        }
        var dependencies = nodes.keys.reduce(into: [AudioNodeID: Set<AudioNodeID>]()) {
            $0[$1] = []
        }
        for connection in nodeConnections where nodes[connection.source] != nil
            && nodes[connection.destination] != nil
        {
            dependencies[connection.destination, default: []].insert(connection.source)
        }
        for connection in paramConnections {
            guard nodes[connection.source] != nil,
                  let owner = parameterOwners[connection.destination]
            else { continue }
            dependencies[owner, default: []].insert(connection.source)
        }
        return dependencies
    }

    private func cyclicNodeIDs(
        dependencies: [AudioNodeID: Set<AudioNodeID>]
    ) -> Set<AudioNodeID> {
        var nextIndex = 0
        var indices: [AudioNodeID: Int] = [:]
        var lowLinks: [AudioNodeID: Int] = [:]
        var stack: [AudioNodeID] = []
        var onStack: Set<AudioNodeID> = []
        var result: Set<AudioNodeID> = []

        func connect(_ id: AudioNodeID) {
            indices[id] = nextIndex
            lowLinks[id] = nextIndex
            nextIndex += 1
            stack.append(id)
            onStack.insert(id)

            for dependency in dependencies[id, default: []] {
                if indices[dependency] == nil {
                    connect(dependency)
                    lowLinks[id] = min(lowLinks[id]!, lowLinks[dependency]!)
                } else if onStack.contains(dependency) {
                    lowLinks[id] = min(lowLinks[id]!, indices[dependency]!)
                }
            }

            guard lowLinks[id] == indices[id] else { return }
            var component: Set<AudioNodeID> = []
            while let member = stack.popLast() {
                onStack.remove(member)
                component.insert(member)
                if member == id { break }
            }
            if component.count > 1
                || dependencies[id, default: []].contains(id)
            {
                result.formUnion(component)
            }
        }

        for id in nodes.keys where indices[id] == nil {
            connect(id)
        }
        return result
    }
}

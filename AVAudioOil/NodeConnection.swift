//
//  NodeConnection.swift
//  AVAudioOil
//
//  Created by David O'Neill on 12/19/17.
//  Copyright © 2017 David O'Neill. All rights reserved.
//

import AVFoundation

/// Source node for connection.
public protocol OutputNode {
    var outputNode: AVAudioNode { get }
}
/// Destination node of a connection.
public protocol InputNode: OutputNode {
    var inputNode: AVAudioNode { get }
}
/// All AVAudioNodes are output nodes.
extension AVAudioNode: OutputNode {
    public var outputNode: AVAudioNode { return self }
}

/// These system provided nodes are input nodes.
extension AVAudioMixerNode: InputNode {
    public var inputNode: AVAudioNode { return outputNode }
}
extension AVAudioUnitEffect: InputNode {
    public var inputNode: AVAudioNode { return outputNode }
}
extension AVAudioUnitTimeEffect: InputNode {
    public var inputNode: AVAudioNode { return outputNode }
}

extension OutputNode {

    /// Output connection points.
    var outputConnections: [AVAudioConnectionPoint] {
        get { return outputNode.engine?.outputConnectionPoints(for: outputNode, outputBus: 0) ?? [] }
        set { setOutputConnections(newValue, engine: outputNode.engine) }
    }

    /// Sets the output connection points.
    public func setOutputConnections(_ connections: [AVAudioConnectionPoint],
                                     fromBus: Int = 0,
                                     format: AVAudioFormat = AVAudioOil.format,
                                     engine: AVAudioEngine? = nil) {
        let engine = engine ?? outputNode.engine ?? AVAudioOil.engine
        AVAudioOil.connect(outputNode,
                           to: connections,
                           fromBus: fromBus,
                           format: format,
                           engine: engine)
    }

    /// Set output to a single node
    @discardableResult public func setOutput(to node: InputNode,
                                             fromBus: Int = 0,
                                             toBus: Int? = nil,
                                             format: AVAudioFormat = AVAudioOil.format,
                                             engine: AVAudioEngine? = nil) -> InputNode {

        let engine = engine ?? outputNode.engine ?? AVAudioOil.engine
        var bus: Int? = toBus
        if bus == nil,
            let mixer = node as? AVAudioMixerNode {
            bus = mixer.nextAvailableInputBus
        }
        AVAudioOil.connect(outputNode,
                           to: node.inputNode,
                           fromBus: fromBus,
                           toBus: bus!,
                           format: format,
                           engine: engine)
        return node
    }
    /// Connect output to an array of input nodes.
    @discardableResult public func connect(to nodes: [InputNode],
                                           format: AVAudioFormat = AVAudioOil.format,
                                           engine: AVAudioEngine? = nil) -> [InputNode] {
        let connections = nodes.map { AVAudioConnectionPoint(node: $0.inputNode, bus: $0.nextInput) }
        setOutputConnections(outputConnections + connections, format: format, engine: engine)
        return nodes
    }
    /// Connect output to an input node.
    @discardableResult public func connect(to node: InputNode,
                                           bus: Int? = nil,
                                           format: AVAudioFormat = AVAudioOil.format,
                                           engine: AVAudioEngine? = nil) -> InputNode {
        let connections = [AVAudioConnectionPoint(node: node.inputNode, bus: bus ?? node.nextInput)]
        setOutputConnections(outputConnections + connections, format: format, engine: engine)
        return node
    }
    /// Disconnect all output connections
    public func disconnectOutput() {
        outputNode.engine?.disconnectNodeOutput(outputNode)
    }

    /// Breaks connection from outputNode to an input's node if exists.
    ///   - Parameter from: The node that output will disconnect from.
    public mutating func disconnectOutput(from: InputNode) {
        outputConnections = outputConnections.filter({ $0.node != from.inputNode })
    }

}

public extension InputNode {

    /// Untested :/
    public var inputConnections: [AVAudioConnectionPoint] {
        guard let engine = inputNode.engine else { return [] }
        var inputs = [AVAudioConnectionPoint]()
        for bus in 0..<self.inputNode.numberOfInputs {
            if let conection = engine.inputConnectionPoint(for: inputNode, inputBus: bus) {
                inputs.append(conection)
            }
        }
        return inputs
    }
    /// Returns 0 or nextAvailableInputBus if self is a mixer
    public var nextInput: Int {
        if let mixer = self as? AVAudioMixerNode {
            return mixer.nextAvailableInputBus
        }
        return 0
    }
}

/*
 Operator for connecting nodes.
 Use: node1 >>> node2 >>> AVAudioOil.mainMixerNode
 Equivalent is node1.connect(to: node2).connect(to: AVAudioOil.mainMixerNode)
*/
infix operator >>>: AdditionPrecedence

@discardableResult public func >>>(left: OutputNode, right: InputNode) -> InputNode {
    return left.connect(to: right)
}
@discardableResult public func >>>(left: OutputNode, right: [InputNode]) -> [InputNode] {
    return left.connect(to: right)
}
@discardableResult public func >>>(left: [OutputNode], right: InputNode) -> InputNode {
    for node in left {
        node.connect(to: right)
    }
    return right
}




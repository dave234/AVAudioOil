//
//  NodeConnection.swift
//  AVAudioOil
//
//  Created by David O'Neill on 12/19/17.
//  Copyright © 2017 David O'Neill. All rights reserved.
//

import AVFoundation


/** Uses a few global defaults to make connections easier

 */

public class AVAudioOil {

    public static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    public lazy    var engine = AVAudioEngine()
    public static  var engine: AVAudioEngine { return shared.engine }
    public static  var mainMixerNode: AVAudioMixerNode { return shared.engine.mainMixerNode }

    private init() {}
    public static let shared = AVAudioOil()

    // Attaches nodes if node.engine == nil
    private static func safeAttach(_ nodes: [AVAudioNode], engine: AVAudioEngine = engine) {
        _ = nodes.filter { $0.engine == nil }.map { engine.attach($0) }
    }

    open static func connect(_ sourceNode: AVAudioNode,
                             to destNodes: [AVAudioConnectionPoint],
                             fromBus sourceBus: AVAudioNodeBus = 0,
                             format: AVAudioFormat = format,
                             engine: AVAudioEngine?) {

        let connectionsWithNodes = destNodes.filter { $0.node != nil }
        let engine = engine ?? sourceNode.engine ?? AVAudioOil.engine

        safeAttach([sourceNode] + connectionsWithNodes.map { $0.node! }, engine:  engine)
        // See addDummyOnEmptyMixer for dummyNode explanation.
        let dummyNode = addDummyOnEmptyMixer(sourceNode, engine: engine)
        checkMixerInputs(connectionsWithNodes, engine: engine)
        engine.connect(sourceNode, to: connectionsWithNodes, fromBus: sourceBus, format: format)
        dummyNode?.disconnectOutput()
    }

    open static func connect(_ sourceNode: AVAudioNode,
                             to destNode: AVAudioNode,
                             fromBus: AVAudioNodeBus = 0,
                             toBus: AVAudioNodeBus = 0,
                             format: AVAudioFormat = format,
                             engine: AVAudioEngine?) {

        let engine = engine ?? sourceNode.engine ?? AVAudioOil.engine

        safeAttach([sourceNode, destNode], engine: engine)
        // See addDummyOnEmptyMixer for dummyNode explanation.
        let dummyNode = addDummyOnEmptyMixer(sourceNode, engine: engine)
        engine.connect(sourceNode, to: destNode, fromBus: fromBus, toBus: toBus, format: format)
        dummyNode?.disconnectOutput()
    }
    public static func start() {
        try? engine.start()
    }
}

/// Check manage mixers without connections on Audio engine start
private extension AVAudioMixerNode {
    var hasInputs: Bool {
        return (0..<numberOfInputs).contains {
            engine?.inputConnectionPoint(for: self, inputBus: $0) != nil
        }
    }
}
public extension AVAudioOil {
    /** HACK!

     AVAudioMixer will crash if engine is started and connection is made to a bus exceeding mixer's
     numberOfInputs. The crash only happens when using the AVAudioEngine function that connects a node to an array
     of AVAudioConnectionPoints and the mixer is one of those points. When AVAudioEngine uses a different function
     that connects a node's output to a single AVAudioMixerNode, the mixer's inputs are incremented to accommodate
     the new connection. So the workaround is to create dummy nodes, make a connections to the mixer using the
     function that makes the mixer create new inputs, then remove the dummy nodes so that there is an available
     bus to connect to.
     */
    private static func checkMixerInputs(_ connectionPoints: [AVAudioConnectionPoint], engine: AVAudioEngine) {

        if !engine.isRunning { return }

        for connection in connectionPoints {
            if let mixer = connection.node as? AVAudioMixerNode,
                connection.bus >= mixer.numberOfInputs {

                var dummyNodes = [AVAudioNode]()
                while connection.bus >= mixer.numberOfInputs {
                    let dummyNode = AVAudioUnitSampler()
                    dummyNode.setOutput(to: mixer)
                    dummyNodes.append(dummyNode)
                }
                for dummyNode in dummyNodes {
                    dummyNode.disconnectOutput()
                }

            }
        }
    }

    // If an AVAudioMixerNode's output connection is made while engine is running, and there are no input connections
    // on the mixer, subsequent connections made to the mixer will silently fail.  A workaround is to connect a dummy
    // node to the mixer prior to making a connection, then removing the dummy node after the connection has been made.
    //
    private static func addDummyOnEmptyMixer(_ node: AVAudioNode, engine: AVAudioEngine) -> AVAudioNode? {

        // Only an issue if engine is running, node is a mixer, and mixer has no inputs
        guard let mixer = node as? AVAudioMixerNode,
            engine.isRunning,
            !mixer.hasInputs else {
                return nil
        }

        let dummy = AVAudioUnitSampler()
        engine.attach(dummy)
        engine.connect(dummy, to: mixer, format: AVAudioOil.format)
        return dummy
    }
}

public protocol OutputNode {
    var outputNode: AVAudioNode { get }

}
extension OutputNode {
    var outputConnections: [AVAudioConnectionPoint] {
        get { return outputNode.engine?.outputConnectionPoints(for: outputNode, outputBus: 0) ?? [] }
        set { setOutputConnections(newValue, engine: outputNode.engine) }
    }

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
    @discardableResult public func connect(to nodes: [InputNode],
                                           format: AVAudioFormat = AVAudioOil.format,
                                           engine: AVAudioEngine? = nil) -> [InputNode] {
        let connections = nodes.map { AVAudioConnectionPoint(node: $0.outputNode, bus: $0.outputNode.nextInput) }
        setOutputConnections(outputConnections + connections, format: format, engine: engine)
        return nodes
    }
    @discardableResult public func connect(to node: InputNode,
                                           bus: Int? = nil,
                                           format: AVAudioFormat = AVAudioOil.format,
                                           engine: AVAudioEngine? = nil) -> InputNode {
        let connections = [AVAudioConnectionPoint(node: node.inputNode, bus: bus ?? node.nextInput)]
        setOutputConnections(outputConnections + connections, format: format, engine: engine)
        return node
    }

    public func disconnectOutput() {
        outputNode.engine?.disconnectNodeOutput(outputNode)
    }

    /// Breaks connection from outputNode to an input's node if exists.
    ///   - Parameter from: The node that output will disconnect from.
    public mutating func disconnectOutput(from: InputNode) {
        outputConnections = outputConnections.filter({ $0.node != from.inputNode })
    }

}
private extension AVAudioNode {
    var nextInput: Int {
        if let mixer = self as? AVAudioMixerNode {
            return mixer.nextAvailableInputBus
        }
        return 0
    }
}
public protocol InputNode: OutputNode {
    var inputNode: AVAudioNode { get }
}
extension InputNode {
    var inputConnections: [AVAudioConnectionPoint] {
        guard let engine = inputNode.engine else { return [] }
        var inputs = [AVAudioConnectionPoint]()
        for bus in 0..<self.inputNode.numberOfInputs {
            if let conection = engine.inputConnectionPoint(for: inputNode, inputBus: bus) {
                inputs.append(conection)
            }
        }
        return inputs
    }
    var nextInput: Int {
        if let mixer = inputNode as? AVAudioMixerNode {
            return mixer.nextAvailableInputBus
        }
        return 0
    }
}

extension AVAudioNode:  InputNode {
    public var outputNode: AVAudioNode { return self }
    public var inputNode: AVAudioNode { return self }

}


// Set output connection(s)
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




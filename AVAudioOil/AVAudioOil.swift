//
//  AVAudioOil.swift
//  AVAudioOil
//
//  Created by David O'Neill on 12/19/17.
//  Copyright © 2017 David O'Neill. All rights reserved.
//

import AVFoundation


public class AVAudioOil {

    /// Convenince to get shared.engine
    public static  var engine: AVAudioEngine { return shared.engine }
    /// Convenince to get shared.engine.mainMixerNode
    public static  var mainMixerNode: AVAudioMixerNode { return shared.engine.mainMixerNode }
    /// Default format that will be used for AVAudioOil connections when format not provided as argument.
    public static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!


    private init() {}
    public static let shared = AVAudioOil()
    public lazy    var engine = AVAudioEngine()

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
        do { try engine.start() } catch { print(error) }
    }
    public static func stop() {
        engine.stop()
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

/// Couple of hacks to make sure mixers can be connected to after engine starts.
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
    private static func addDummyOnEmptyMixer(_ node: AVAudioNode, engine: AVAudioEngine) -> AVAudioUnitSampler? {

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

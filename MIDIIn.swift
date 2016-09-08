//
//  MIDIIn.swift
//
//  Created by Ales Tsurko on 22.08.16.
//  Copyright © 2016 Aliaksandr Tsurko. All rights reserved.
//

extension AUValue {
    func mapLinearRangeToLinear(inMin inMin: AUValue, inMax: AUValue, outMin: AUValue, outMax: AUValue) -> AUValue {
        return (self - inMin) / (inMax - inMin) * (outMax - outMin) + outMin
    }
}

public class MIDIMap: NSObject {
    
    public var noteOnOffCallback: ((note: UInt8, velocity: UInt8) -> Void)?
    public var sustainPedalCallback: ((value: UInt8) -> Void)?
    public var pitchBendCallback: ((value: UInt8) -> Void)?
    public var modulationWheelCallback: ((value: UInt8) -> Void)?
    public var notificationCallback: ((message: MIDINotification) -> Void)?
    public var ccMapping: [UInt8: AUParameter]?
    
    required public init(noteOnOffCallback: ((UInt8, UInt8) -> Void)?, sustainPedalCallback: (UInt8 -> Void)?, pitchBendCallback: (UInt8 -> Void)?, modulationWheelCallback: (UInt8 -> Void)?, notificationCallback: (MIDINotification -> Void)?, ccMapping: [UInt8: AUParameter]?) {
        super.init()
        
        self.noteOnOffCallback = noteOnOffCallback
        self.sustainPedalCallback = sustainPedalCallback
        self.pitchBendCallback = pitchBendCallback
        self.modulationWheelCallback = modulationWheelCallback
        self.notificationCallback = notificationCallback
        
        self.ccMapping = ccMapping
    }
}

public class MIDIDevice: NSObject {
    public var name: String!
    public var uniqueID: Int32!
    public var isConnected: Bool {
        didSet {
            var object: MIDIObjectRef = 0
            var type: MIDIObjectType = MIDIObjectType.Destination
            let err = MIDIObjectFindByUniqueID(self.uniqueID, &object, &type)
            
            if self.isConnected && err != kMIDIObjectNotFound {
                MIDIPortConnectSource(self.midiIn.port, object, nil)
                print("\(self.name) is connected")
            } else {
                MIDIPortDisconnectSource(self.midiIn.port, object)
                print("\(self.name) is disconnected")
            }
        }
    }
    public var midiIn: MIDIIn!
    
    required public init(midiIn: MIDIIn, name: String, id: Int32, isConnected: Bool) {
        self.midiIn = midiIn
        self.name = name
        self.uniqueID = id
        self.isConnected = isConnected
    }
    
}

private var inputDescription: MIDIMap!

public class MIDIIn: NSObject {
    
    public let client: MIDIClientRef
    public let port: MIDIPortRef
    public let midiMap: MIDIMap
    
    public var availableDevices: [MIDIDevice] = []
    
    public let MIDINotifyCallback: MIDINotifyProc = {message, refCon in
        var inDesc = UnsafeMutablePointer<MIDIMap>(refCon).memory
        if let callback = inDesc.notificationCallback {
            callback(message: message.memory)
        }
    }
    
    public let MIDIReadCallback: MIDIReadProc = {pktlist, refCon, connRefCon in
        var inDesc = UnsafeMutablePointer<MIDIMap>(refCon).memory
        
        var packet = pktlist.memory.packet
        
        for _ in 1...pktlist.memory.numPackets {
            let midiStatus = packet.data.0
            let midiCommand = midiStatus>>4
            
            // NoteOff, NoteOn
            if midiCommand == 0x08 || midiCommand == 0x09 {
                let note = packet.data.1&0x7f
                let velocity = midiCommand == 0x08 ? 0 : packet.data.2&0x7f
                
                if let callback = inDesc.noteOnOffCallback {
                    callback(note: note, velocity: velocity)
                }
                
            }
            
            // Pitch bend
            if midiCommand == 0x0E {
                if let callback = inDesc.pitchBendCallback {
                    let value = packet.data.2&0x7f
                    callback(value: value)
                }
            }
            
            // CC change
            if midiCommand == 0x0B {
                let number = packet.data.1&0x7f
                let value = packet.data.2&0x7f
                
                if number == 1 {
                    // if CC is the modulation wheel
                    if let callback = inDesc.modulationWheelCallback {
                        callback(value: value)
                    }
                } else if number == 64 {
                    // if CC is a sustain pedal
                    if let callback = inDesc.sustainPedalCallback {
                        callback(value: value)
                    }
                } else {
                    if let ccMap = inDesc.ccMapping {
                        if let parameter = ccMap[number] {
                            parameter.value = AUValue(value).mapLinearRangeToLinear(inMin: 0, inMax: 127, outMin: parameter.minValue, outMax: parameter.maxValue)
                        }
                    }
                }
                
                //                print("CCNum \(number) with value \(value)")
            }
            
            // copy into new var to prevent bug, that appeared when using a
            // packet's reference in place
            var packCopy = packet
            packet = MIDIPacketNext(&packCopy).memory
        }
    }
    
    required public init(clientName: String, portName: String, midiMap: MIDIMap) {
        inputDescription = midiMap
        self.midiMap = midiMap
        
        // Create client, port and connect
        
        var clientRef = MIDIPortRef()
        MIDIClientCreate(clientName, MIDINotifyCallback, &inputDescription, &clientRef)
        
        var portRef = MIDIPortRef()
        MIDIInputPortCreate(clientRef, portName, MIDIReadCallback, &inputDescription, &portRef)
        
        self.port = portRef
        self.client = clientRef
        
        super.init()
        
        self.updateAvailableDevices()
        
        // allow network MIDI
        let session = MIDINetworkSession.defaultSession()
        session.enabled = true
        session.connectionPolicy = MIDINetworkConnectionPolicy.Anyone
    }
    
    public func updateAvailableDevices() {
        // fill available inputs
        let sourceCount = MIDIGetNumberOfSources()
        
        self.availableDevices = []
        
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            var endpointName: Unmanaged<CFStringRef>?
            
            MIDIObjectGetStringProperty(src, kMIDIPropertyName, &endpointName)
            let name = endpointName!.takeRetainedValue() as String
            
            var id: Int32 = 0
            MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &id)
            
            let device = MIDIDevice(midiIn: self, name: name, id: id, isConnected: false)
            
            self.availableDevices.append(device)
        }
    }
    
}

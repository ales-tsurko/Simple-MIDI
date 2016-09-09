//
//  MIDIIn.swift
//
//  Created by Ales Tsurko on 22.08.16.
//  Copyright © 2016 Aliaksandr Tsurko. All rights reserved.
//

extension AUValue {
    func mapLinearRangeToLinear(inMin: AUValue, inMax: AUValue, outMin: AUValue, outMax: AUValue) -> AUValue {
        return (self - inMin) / (inMax - inMin) * (outMax - outMin) + outMin
    }
}

open class MIDIMap: NSObject {
    
    open var noteOnOffCallback: ((_ note: UInt8, _ velocity: UInt8) -> Void)?
    open var sustainPedalCallback: ((_ value: UInt8) -> Void)?
    open var pitchBendCallback: ((_ value: UInt8) -> Void)?
    open var modulationWheelCallback: ((_ value: UInt8) -> Void)?
    open var notificationCallback: ((_ message: MIDINotification) -> Void)?
    open var ccMapping: [UInt8: AUParameter]?
    
    required public init(noteOnOffCallback: ((UInt8, UInt8) -> Void)?, sustainPedalCallback: ((UInt8) -> Void)?, pitchBendCallback: ((UInt8) -> Void)?, modulationWheelCallback: ((UInt8) -> Void)?, notificationCallback: ((MIDINotification) -> Void)?, ccMapping: [UInt8: AUParameter]?) {
        super.init()
        
        self.noteOnOffCallback = noteOnOffCallback
        self.sustainPedalCallback = sustainPedalCallback
        self.pitchBendCallback = pitchBendCallback
        self.modulationWheelCallback = modulationWheelCallback
        self.notificationCallback = notificationCallback
        
        self.ccMapping = ccMapping
    }
}

open class MIDIDevice: NSObject {
    open var name: String!
    open var uniqueID: Int32!
    open var isConnected: Bool {
        didSet {
            var object: MIDIObjectRef = 0
            var type: MIDIObjectType = MIDIObjectType.destination
            let err = MIDIObjectFindByUniqueID(self.uniqueID, &object, &type)
            
            if self.isConnected && err != kMIDIObjectNotFound {
                MIDIPortConnectSource(self.midiIn.port, object, nil)
                print("\(self.name!) is connected")
            } else {
                MIDIPortDisconnectSource(self.midiIn.port, object)
                print("\(self.name!) is disconnected")
            }
        }
    }
    open var midiIn: MIDIIn!
    
    required public init(midiIn: MIDIIn, name: String, id: Int32, isConnected: Bool) {
        self.midiIn = midiIn
        self.name = name
        self.uniqueID = id
        self.isConnected = isConnected
    }
    
}

private var inputDescription: MIDIMap!

open class MIDIIn: NSObject {
    
    open let client: MIDIClientRef
    open let port: MIDIPortRef
    open let midiMap: MIDIMap
    
    open var availableDevices: [MIDIDevice] = []
    
    open let MIDINotifyCallback: MIDINotifyProc = {message, refCon in
        var inDesc = refCon?.assumingMemoryBound(to: MIDIMap.self).pointee
        if let callback = inDesc?.notificationCallback {
            callback(message.pointee)
        }
    }
    
    open let MIDIReadCallback: MIDIReadProc = {pktlist, refCon, connRefCon in
        var inDesc = refCon?.assumingMemoryBound(to: MIDIMap.self).pointee
        
        var packet = pktlist.pointee.packet
        
        for _ in 1...pktlist.pointee.numPackets {
            let midiStatus = packet.data.0
            let midiCommand = midiStatus>>4
            
            // NoteOff, NoteOn
            if midiCommand == 0x08 || midiCommand == 0x09 {
                let note = packet.data.1&0x7f
                let velocity = midiCommand == 0x08 ? 0 : packet.data.2&0x7f
                
                if let callback = inDesc?.noteOnOffCallback {
                    callback(note, velocity)
                }
                
            }
            
            // Pitch bend
            if midiCommand == 0x0E {
                if let callback = inDesc?.pitchBendCallback {
                    let value = packet.data.2&0x7f
                    callback(value)
                }
            }
            
            // CC change
            if midiCommand == 0x0B {
                let number = packet.data.1&0x7f
                let value = packet.data.2&0x7f
                
                if number == 1 {
                    // if CC is the modulation wheel
                    if let callback = inDesc?.modulationWheelCallback {
                        callback(value)
                    }
                } else if number == 64 {
                    // if CC is a sustain pedal
                    if let callback = inDesc?.sustainPedalCallback {
                        callback(value)
                    }
                } else {
                    if let ccMap = inDesc?.ccMapping {
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
            packet = MIDIPacketNext(&packCopy).pointee
        }
    }
    
    required public init(clientName: String, portName: String, midiMap: MIDIMap) {
        inputDescription = midiMap
        self.midiMap = midiMap
        
        // Create client, port and connect
        
        var clientRef = MIDIPortRef()
        MIDIClientCreate(clientName as CFString, MIDINotifyCallback, &inputDescription, &clientRef)
        
        var portRef = MIDIPortRef()
        MIDIInputPortCreate(clientRef, portName as CFString, MIDIReadCallback, &inputDescription, &portRef)
        
        self.port = portRef
        self.client = clientRef
        
        super.init()
        
        self.updateAvailableDevices()
        
        // allow network MIDI
        let session = MIDINetworkSession.default()
        session.isEnabled = true
        session.connectionPolicy = MIDINetworkConnectionPolicy.anyone
    }
    
    open func updateAvailableDevices() {
        // fill available inputs
        let sourceCount = MIDIGetNumberOfSources()
        
        self.availableDevices = []
        
        for i in 0..<sourceCount {
            let src = MIDIGetSource(i)
            var endpointName: Unmanaged<CFString>?
            
            MIDIObjectGetStringProperty(src, kMIDIPropertyName, &endpointName)
            let name = endpointName!.takeRetainedValue() as String
            
            var id: Int32 = 0
            MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &id)
            
            let device = MIDIDevice(midiIn: self, name: name, id: id, isConnected: false)
            
            self.availableDevices.append(device)
        }
    }
    
}

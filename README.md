# Simple-MIDI
Swift classes for simple usage of Core MIDI. Currently only MIDI input is available.

# Usage

```Swift
// First, we need to define a MIDIMap with appropriate callbacks.
// For example, we have some audio unit with a parameter "volume"
let volumeParam = audioUnit.parameterTree?.valueForKey("volume") as! AUParameter
  
// We define CC-map, where we bind CC-number with a parameter.
// Here we bind an AUParameter with key "volume" to a CC with number 7
let ccMap: [UInt8 : AUParameter] = [7 : volumeParam] // CC-map is a dictionary of type [CCNum : AUParameter]
  
// MIDIMap initialization with given CC-map
// All parameters in the MIDIMap class are optional.
let map = MIDIMap(noteOnOffCallback: nil, sustainPedalCallback: nil, pitchBendCallback: nil, modulationWheelCallback: nil, notificationCallback: nil, ccMapping: ccMap)

/* We also can define callbacks for another common MIDI messages: Note On/Off,
Pitch Bend, Modulation Wheel and MIDI Notifications.

Let's define a callback for the modulation wheel. Our audio unit has a parameter
"filter-frequency" with minimum value 0 and maximum value 1. We're going to change
it's value with the modulation wheel. */

let frequencyParam = audioUnit.parameterTree?.valueForKey("filter-frequency") as! AUParamter
let modulationWheelCallback = {(value: UInt8) in
  frequencyParam.value = AUValue(value)/127
}

// add the callback to the MIDIMap
map.modulationWheelCallback = modulationWheelCallback

// Now we can initialize MIDIIn
let midiIn = MIDIIn(clientName: "Here The Name For Your MIDI Client", portName: "Here The Name For Your MIDI Input Port", midiMap: map)

// And we can get available MIDI devices now.
// Let's connect the first one (if any)
if !midiIn.availableDevices.isEmpty {
  midiIn.availableDevices[0].isConnected = true
}

// Now we can control the audio unit's parameters with the connected device.
```

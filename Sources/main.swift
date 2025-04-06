import SwiftUI
import CoreBluetooth
import AppKit

struct Reading{
    var level: UInt8
    var ts: UInt64
}
struct BatterInfo {
    var levels: [Reading]
    var label: String {
        let joined = levels.makeIterator().map { "\(String($0.level))%"}.joined(separator: ", ");
        return joined
    }

}
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var connectedDevices: [CBPeripheral] = []
    @Published var batteryInfo: [UUID: BatterInfo] = [:]
    
    private var centralManager: CBCentralManager!
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // this only runs when the central manager's state changes ( + startup ) =>  i.e when bluetooth is turned on or off NOT when new devices are connected 
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            let peripherals = central.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
            for peripheral in peripherals {
                if !connectedDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                    connectedDevices.append(peripheral)
                    centralManager.connect(peripheral, options: nil)
                }
            }
        } else {
            print("Bluetooth not available: \(central.state)")
        }
    }
    // this discovers already connected devices with the battery service that have been connected since the app was launched
    // and also updated the list of connected devices potentially removing any that are no longer connected
    func discoverNewDevices(){
        guard centralManager.state == .poweredOn else{
            print("Bluetooth is not available")
            return
        }
        let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [batteryServiceUUID])
        var connectedDevicesNew :[CBPeripheral] = []
        for peripheral in  peripherals{
            connectedDevicesNew.append(peripheral)
            centralManager.connect(peripheral,options: nil)
        }
        connectedDevices =  connectedDevicesNew
    }

    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([batteryServiceUUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == batteryServiceUUID {
            peripheral.discoverCharacteristics([batteryLevelCharacteristicUUID], for: service)
        }
    }
    
    // Called when characteristics are discovered.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == batteryLevelCharacteristicUUID {
            peripheral.readValue(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    // Called when the value of a characteristic is updated.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid != batteryLevelCharacteristicUUID {
            return
        }
        guard let data = characteristic.value,
        let newReading = data.first else { return }

        print("Packet received for peripheral \(peripheral.name ?? "Unknown") with value: \(data.first ?? 0)")
        if batteryInfo[peripheral.identifier] == nil {
            batteryInfo[peripheral.identifier] = BatterInfo(levels: [])
        }
        // current ts for comparison
        let ts_curr = UInt64(Date().timeIntervalSince1970 * 1000) 

        // if it is empty then add the first reading
        if batteryInfo[peripheral.identifier]?.levels.count == 0 {
            batteryInfo[peripheral.identifier]?.levels.append(Reading(level: newReading, ts: ts_curr))
        }
        var last_was_recent = false
        let info = batteryInfo[peripheral.identifier]!;
        for (i,reading) in info.levels.enumerated() {
            if reading.ts + 150 > ts_curr{
                last_was_recent = true
                continue
            }else{
                batteryInfo[peripheral.identifier]?.levels[i].level = newReading
                batteryInfo[peripheral.identifier]?.levels[i].ts = ts_curr
                last_was_recent = false
                break
            }
        } 
        // if the last reading was recent then add the new reading meaning this was a recording / device that has not ever been stored
        let last = batteryInfo[peripheral.identifier]?.levels.last?.level
        if last_was_recent && last != newReading{
            batteryInfo[peripheral.identifier]?.levels.append(Reading(level: newReading, ts: ts_curr))
        }
        
    }
}
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }
    
    struct HoverButton: View {
        let configuration: Configuration
        @State private var isHovered = false
        
        var body: some View {
            configuration.label
            .padding(4)
                .frame( minHeight: 20).frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Group {
                        if isHovered {
                            VisualEffectView(material: .selection, blendingMode: .withinWindow)
                        } else {
                            Color.clear
                        }
                    }
                )
                .cornerRadius(4)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isHovered = hovering
                    }
                }
        }
    }
}


@main
struct MenuBarHelloApp: App {
    @StateObject var bluetoothManager = BluetoothManager()
    @State private var selectedPeripheral: CBPeripheral? = nil
    
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 2) {
                Text("Select your keyboard")
                    .font(.headline)
                Divider()
                if bluetoothManager.connectedDevices.isEmpty {
                    Text("No devices found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(bluetoothManager.connectedDevices, id: \.identifier) { peripheral in
                        Button { 
                            selectedPeripheral = peripheral
                            print("\(peripheral.name ?? "Unknown") selected")
                        } label: {
                            HStack {
                                Text(peripheral.name ?? "Unknown Device")
                                Spacer()
                                Text(bluetoothManager.batteryInfo[peripheral.identifier]?.label ?? "N/A")
                                    .foregroundColor(.secondary)
                            }
                        }.buttonStyle(HoverButtonStyle())

                    }
                }
                Spacer()
                Text("Actions").font(.headline)
                Divider()
                Button("Discover / Update"){
                    print("Discovering / Update devices")
                    bluetoothManager.discoverNewDevices()

                }.buttonStyle(HoverButtonStyle()).foregroundStyle(.primary)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }.buttonStyle(HoverButtonStyle()).foregroundStyle(.primary)
            }
            .padding()
            .onReceive(Timer.publish(every: 120, on:.main, in: .common).autoconnect()) {_ in 
                print("Checking for new connected devices")
                // every 120 seconds we check the device list for conected devices to update our state
                bluetoothManager.discoverNewDevices()
            }
            .frame(minWidth:200, minHeight: 100,alignment: .topLeading)
        } label: {
            if let selected = selectedPeripheral,
               let batteryLabel = bluetoothManager.batteryInfo[selected.identifier]?.label {
                Text(" \(selected.name ?? "Name"): \(batteryLabel)")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            } else {
                Text("Select your keyboard")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
        }
        .menuBarExtraStyle(.window)
    }
}

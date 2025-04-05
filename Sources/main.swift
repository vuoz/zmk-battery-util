import SwiftUI
import CoreBluetooth

struct Reading{
    var level: UInt8
    var ts: UInt64
}
struct BatterInfo {
    var levels: [Reading]

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
            if reading.ts + 200 > ts_curr{
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
struct ContentView: View {
    @StateObject var bluetoothManager = BluetoothManager()
    
    var body: some View {
        VStack {
            if bluetoothManager.connectedDevices.isEmpty {
                Text("No connected devices with battery service found.")
            } else {
                List(bluetoothManager.connectedDevices, id: \.identifier) { peripheral in
                    VStack(alignment: .leading) {
                        Text(peripheral.name ?? "Unknown Device")
                            .font(.headline)
                        if let battery = bluetoothManager.batteryInfo[peripheral.identifier] {
                            List{
                                ForEach(battery.levels, id: \.ts) { reading in
                                    Text("Battery Level: \(reading.level)%")
                                        .foregroundColor(.blue)
                                    
                                }
                            }
                            
                            
                        } else {
                            Text("Reading battery level...")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}

@main
struct MenuBarHelloApp: App {
    var body: some Scene {
        MenuBarExtra("Devices", systemImage: "battery.100") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}


#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <EEPROM.h>

// Relay pin
const int RELAY_PIN = 2; // GPIO2 for the relay

// EEPROM settings
#define EEPROM_SIZE 1
#define RELAY_STATE_ADDRESS 0

// BLE settings
BLEServer *pServer = nullptr;
BLECharacteristic *pCharacteristic = nullptr;
bool deviceConnected = false;
bool relayState = false;
bool oldDeviceConnected = false; // Track previous connection state

// Service and characteristic UUIDs (must match the controller)
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Function to save relay state to EEPROM
void saveRelayState()
{
    EEPROM.write(RELAY_STATE_ADDRESS, relayState);
    EEPROM.commit();
}

// Function to load relay state from EEPROM
void loadRelayState()
{
    relayState = EEPROM.read(RELAY_STATE_ADDRESS);
    digitalWrite(RELAY_PIN, relayState);
}

class MyServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *pServer)
    {
        deviceConnected = true;
        Serial.println("Client connected");
    }

    void onDisconnect(BLEServer *pServer)
    {
        deviceConnected = false;
        Serial.println("Client disconnected");

        // Restart advertising
        BLEDevice::startAdvertising();
        Serial.println("Advertising restarted");
    }
};

class MyCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *pCharacteristic)
    {
        String value = pCharacteristic->getValue().c_str();
        if (value == "toggle")
        {
            relayState = !relayState;
            digitalWrite(RELAY_PIN, relayState);
            saveRelayState(); // Save state after BLE toggle
            Serial.print("Relay state changed to: ");
            Serial.println(relayState ? "ON" : "OFF");
        }
    }
};

void setup()
{
    Serial.begin(115200);

    // Initialize EEPROM
    EEPROM.begin(EEPROM_SIZE);

    // Initialize relay pin
    pinMode(RELAY_PIN, OUTPUT);

    // Load saved relay state and toggle it
    loadRelayState();
    relayState = !relayState; // Toggle the state
    digitalWrite(RELAY_PIN, relayState);
    saveRelayState(); // Save the new state
    Serial.print("Relay state toggled on boot to: ");
    Serial.println(relayState ? "ON" : "OFF");

    // Initialize BLE
    BLEDevice::init("DoorRelay");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);
    pCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_READ |
            BLECharacteristic::PROPERTY_WRITE);

    pCharacteristic->setCallbacks(new MyCallbacks());
    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("BLE server started");
}

void loop()
{
    // Handle disconnection
    if (!deviceConnected && oldDeviceConnected)
    {
        delay(500);                  // Give the BLE stack a chance to get things ready
        pServer->startAdvertising(); // Restart advertising
        Serial.println("Advertising restarted");
        oldDeviceConnected = deviceConnected;
    }

    // Handle connection
    if (deviceConnected && !oldDeviceConnected)
    {
        oldDeviceConnected = deviceConnected;
    }

    delay(200); // Delay to reduce power consumption
}
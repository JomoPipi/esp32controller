#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Relay pin
const int RELAY_PIN = 2; // GPIO2 for the relay

// BLE settings
BLEServer *pServer = nullptr;
BLECharacteristic *pCharacteristic = nullptr;
bool deviceConnected = false;
bool relayState = false;

// Service and characteristic UUIDs (must match the controller)
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

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
            Serial.print("Relay state changed to: ");
            Serial.println(relayState ? "ON" : "OFF");
        }
    }
};

void setup()
{
    Serial.begin(115200);
    pinMode(RELAY_PIN, OUTPUT);
    digitalWrite(RELAY_PIN, LOW); // Start with relay OFF

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
    delay(2000); // Delay to reduce power consumption
}
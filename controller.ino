#include <BLEDevice.h>
#include <BLEClient.h>
#include <BLEUtils.h>
#include <BLEScan.h>

// Button pin
const int BUTTON_PIN = 0; // GPIO0 is typically a button on ESP32 dev boards

// BLE settings
BLEClient *pClient = nullptr;
BLERemoteCharacteristic *pRemoteCharacteristic = nullptr;
bool deviceConnected = false;
bool lastButtonState = false;

// Service and characteristic UUIDs
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Device name to connect to
const char *DEVICE_NAME = "DoorRelay";

class MyClientCallback : public BLEClientCallbacks
{
    void onConnect(BLEClient *pclient)
    {
        deviceConnected = true;
        Serial.println("Connected to server");
    }

    void onDisconnect(BLEClient *pclient)
    {
        deviceConnected = false;
        Serial.println("Disconnected from server");
    }
};

void setup()
{
    Serial.begin(115200);
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    // Initialize BLE
    BLEDevice::init("Controller");
    pClient = BLEDevice::createClient();
    pClient->setClientCallbacks(new MyClientCallback());
}

void connectToServer()
{
    BLEScan *pBLEScan = BLEDevice::getScan();
    pBLEScan->setActiveScan(true);
    pBLEScan->start(5);

    BLEScanResults *foundDevices = pBLEScan->getResults();
    for (int i = 0; i < foundDevices->getCount(); i++)
    {
        BLEAdvertisedDevice device = foundDevices->getDevice(i);
        if (device.getName() == DEVICE_NAME)
        {
            pClient->connect(&device);
            BLERemoteService *pRemoteService = pClient->getService(SERVICE_UUID);
            if (pRemoteService != nullptr)
            {
                pRemoteCharacteristic = pRemoteService->getCharacteristic(CHARACTERISTIC_UUID);
                if (pRemoteCharacteristic != nullptr)
                {
                    Serial.println("Found our characteristic");
                }
            }
            break;
        }
    }
    pBLEScan->clearResults();
}

void loop()
{
    if (!deviceConnected)
    {
        connectToServer();
        delay(1000);
        return;
    }

    // Read button state
    bool currentButtonState = digitalRead(BUTTON_PIN);

    // Check for button state change
    if (currentButtonState != lastButtonState)
    {
        if (currentButtonState == LOW)
        { // Button pressed
            if (pRemoteCharacteristic != nullptr)
            {
                pRemoteCharacteristic->writeValue("toggle");
                Serial.println("Sent toggle command");
            }
        }
        lastButtonState = currentButtonState;
    }

    delay(50); // Small delay to prevent bouncing
}
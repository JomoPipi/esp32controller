import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Service and characteristic UUIDs (must match the ESP32)
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String DEVICE_NAME = "DoorRelay";

void main() {
  enableBluetooth();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Door Controller',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Door Controller'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  bool _isConnected = false;
  bool _isScanning = false;
  String _statusMessage = "Not connected";
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _reconnectTimer;

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request location permissions
      var locationStatus = await Permission.location.request();
      if (!locationStatus.isGranted) {
        setState(() {
          _statusMessage = "Location permission required for BLE scanning";
        });
        return false;
      }

      // Request Bluetooth permissions
      var bluetoothScanStatus = await Permission.bluetoothScan.request();
      var bluetoothConnectStatus = await Permission.bluetoothConnect.request();

      if (!bluetoothScanStatus.isGranted || !bluetoothConnectStatus.isGranted) {
        setState(() {
          _statusMessage = "Bluetooth permissions required";
        });
        return false;
      }
    }
    return true;
  }

  Future<void> _scanAndConnect() async {
    // Request permissions first
    if (!await _requestPermissions()) {
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = "Scanning...";
    });

    try {
      // Cancel any existing scan subscription
      await _scanSubscription?.cancel();

      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            print(
              'Found device: ${result.device.name} (${result.device.remoteId})',
            );
            if (result.device.name == DEVICE_NAME) {
              FlutterBluePlus.stopScan();
              _connectToDevice(result.device);
              break;
            }
          }
        },
        onError: (e) {
          print('Scan error: $e');
          setState(() {
            _statusMessage = "Scan error: $e";
            _isScanning = false;
          });
        },
      );

      // Listen for scan completion
      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && !_isConnected) {
          setState(() {
            _statusMessage = "Device not found. Try again.";
            _isScanning = false;
          });
        }
      });
    } catch (e) {
      print('Scan error: $e');
      setState(() {
        _statusMessage = "Error scanning: $e";
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _statusMessage = "Connecting to ${device.name}...";
      });

      // Cancel any existing connection subscription
      await _connectionSubscription?.cancel();

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) async {
        print('Connection state changed: $state');
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _isConnected = false;
            _statusMessage = "Disconnected. Attempting to reconnect...";
          });

          // Start reconnection timer
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (
            timer,
          ) async {
            if (!_isConnected) {
              print('Attempting to reconnect...');
              try {
                await device.connect();
              } catch (e) {
                print('Reconnection failed: $e');
              }
            } else {
              timer.cancel();
            }
          });
        } else if (state == BluetoothConnectionState.connected) {
          _reconnectTimer?.cancel();
          await _discoverServices(device);
        }
      });

      await device.connect();
      _device = device;

      setState(() {
        _statusMessage = "Discovering services...";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        print('Found service: ${service.uuid}');
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            print('Found characteristic: ${characteristic.uuid}');
            if (characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
              _characteristic = characteristic;
              setState(() {
                _isConnected = true;
                _statusMessage = "Connected to ${device.name}";
                _isScanning = false;
              });
              return;
            }
          }
        }
      }

      // If we get here, we didn't find our service/characteristic
      setState(() {
        _statusMessage = "Device found but service not available";
        _isScanning = false;
      });
      await device.disconnect();
    } catch (e) {
      print('Connection error: $e');
      setState(() {
        _statusMessage = "Error connecting: $e";
        _isScanning = false;
      });
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      setState(() {
        _statusMessage = "Discovering services...";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        print('Found service: ${service.uuid}');
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            print('Found characteristic: ${characteristic.uuid}');
            if (characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
              _characteristic = characteristic;
              setState(() {
                _isConnected = true;
                _statusMessage = "Connected to ${device.name}";
                _isScanning = false;
              });
              return;
            }
          }
        }
      }

      // If we get here, we didn't find our service/characteristic
      setState(() {
        _statusMessage = "Device found but service not available";
        _isScanning = false;
      });
      await device.disconnect();
    } catch (e) {
      print('Service discovery error: $e');
      setState(() {
        _statusMessage = "Error discovering services: $e";
        _isScanning = false;
      });
    }
  }

  Future<void> _sendToggleCommand() async {
    if (_characteristic != null) {
      try {
        await _characteristic!.write("toggle".codeUnits);
        setState(() {
          _statusMessage = "Toggle command sent";
        });
      } catch (e) {
        print('Write error: $e');
        setState(() {
          _statusMessage = "Error sending command: $e";
        });
      }
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _statusMessage,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (!_isConnected && !_isScanning)
              ElevatedButton(
                onPressed: _scanAndConnect,
                child: const Text('Connect to Door Relay'),
              ),
            if (_isConnected)
              ElevatedButton(
                onPressed: _sendToggleCommand,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 50,
                    vertical: 20,
                  ),
                ),
                child: const Text('Toggle Door'),
              ),
          ],
        ),
      ),
    );
  }
}

void enableBluetooth() async {
  // first, check if bluetooth is supported by your hardware
  // Note: The platform is initialized on the first call to any FlutterBluePlus method.
  if (await FlutterBluePlus.isSupported == false) {
    print("Bluetooth not supported by this device");
    return;
  }

  // handle bluetooth on & off
  // note: for iOS the initial state is typically BluetoothAdapterState.unknown
  // note: if you have permissions issues you will get stuck at BluetoothAdapterState.unauthorized
  var subscription = FlutterBluePlus.adapterState.listen((
    BluetoothAdapterState state,
  ) {
    print(state);
    if (state == BluetoothAdapterState.on) {
      // usually start scanning, connecting, etc
    } else {
      // show an error to the user, etc
    }
  });

  // turn on bluetooth ourself if we can
  // for iOS, the user controls bluetooth enable/disable
  if (!kIsWeb && Platform.isAndroid) {
    await FlutterBluePlus.turnOn();
  }

  // cancel to prevent duplicate listeners
  subscription.cancel();
}

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bluez/bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:test/test.dart';

class MockBlueZObject extends DBusObject {
  MockBlueZObject(DBusObjectPath path) : super(path);
}

InternetAddress makeRandomUnixAddress() {
  var path = '@bluez-dart-test-';
  var r = Random();
  final randomChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  for (var i = 0; i < 8; i++) {
    path += randomChars[r.nextInt(randomChars.length)];
  }
  return InternetAddress(path, type: InternetAddressType.unix);
}

class MockBlueZManagerObject extends MockBlueZObject {
  final MockBlueZServer server;

  MockBlueZManagerObject(this.server) : super(DBusObjectPath('/org/bluez'));

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.AgentManager1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'RegisterAgent':
        server.agentAddress = methodCall.sender;
        server.agentPath = methodCall.values[0].asObjectPath();
        server.agentCapability = methodCall.values[1].asString();
        return DBusMethodSuccessResponse();
      case 'RequestDefaultAgent':
        server.agentIsDefault = true;
        return DBusMethodSuccessResponse();
      case 'UnregisterAgent':
        if (server.agentAddress != null) {
          await client!.callMethod(
              destination: server.agentAddress,
              path: server.agentPath!,
              interface: 'org.bluez.Agent1',
              name: 'Release',
              replySignature: DBusSignature(''));
        }
        server.agentAddress = null;
        server.agentPath = null;
        server.agentCapability = '';
        server.agentIsDefault = false;
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class MockBlueZBatteryProvider extends DBusRemoteObject {
  late final StreamSubscription<DBusSignal> _signalSubscription;

  var batteries = <DBusObjectPath, MockBlueZBattery>{};

  MockBlueZBatteryProvider(DBusClient client,
      {required String name, required DBusObjectPath path})
      : super(client, name: name, path: path) {
    var objectManager = DBusRemoteObjectManager(client, name: name, path: path);
    _signalSubscription = objectManager.signals.listen((signal) {
      if (signal is DBusObjectManagerInterfacesAddedSignal) {
        if (signal.interfacesAndProperties
            .containsKey('org.bluez.BatteryProvider1')) {
          var path = signal.changedPath;
          var properties =
              signal.interfacesAndProperties['org.bluez.BatteryProvider1']!;
          var device =
              properties['Device']?.asObjectPath() ?? DBusObjectPath('/');
          var percentage = properties['Percentage']?.asByte() ?? 0;
          var source = properties['Source']?.asString() ?? '';
          batteries[path] = MockBlueZBattery(
              client, signal.sender!, path, device,
              percentage: percentage, source: source);
        }
      } else if (signal is DBusObjectManagerInterfacesRemovedSignal) {
        if (signal.interfaces.contains('org.bluez.BatteryProvider1')) {
          batteries.remove(signal.changedPath);
        }
      } else if (signal is DBusPropertiesChangedSignal) {
        if (signal.propertiesInterface == 'org.bluez.BatteryProvider1') {
          var battery = batteries[signal.path];
          var percentage = signal.changedProperties['Percentage']?.asByte();
          if (battery != null && percentage != null) {
            battery.percentage = percentage;
          }
        }
      }
    });
  }

  Future<void> close() async {
    await _signalSubscription.cancel();
  }
}

class MockBlueZBattery extends DBusRemoteObject {
  final DBusObjectPath device;
  int percentage;
  final String source;

  MockBlueZBattery(
      DBusClient client, String name, DBusObjectPath path, this.device,
      {this.percentage = 0, this.source = ''})
      : super(client, name: name, path: path);
}

class MockBlueZAdapterObject extends MockBlueZObject {
  final MockBlueZServer server;
  final String deviceName;

  final String address;
  final String addressType;
  String alias;
  var batteryProviders = <MockBlueZBatteryProvider>[];
  final int class_;
  bool discoverable;
  int discoverableTimeout;
  bool discovering;
  Map<String, DBusValue> discoveryFilter;
  final String modalias;
  final String name;
  bool pairable;
  int pairableTimeout;
  bool powered;
  final List<String> roles;
  final List<String> uuids;

  MockBlueZAdapterObject(this.server, this.deviceName,
      {this.address = '',
      this.addressType = 'public',
      this.alias = '',
      this.class_ = 0,
      this.discoverable = false,
      this.discoverableTimeout = 0,
      this.discovering = false,
      this.discoveryFilter = const {},
      this.modalias = '',
      this.name = '',
      this.pairable = false,
      this.pairableTimeout = 0,
      this.powered = true,
      this.roles = const [],
      this.uuids = const []})
      : super(DBusObjectPath('/org/bluez/$deviceName'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.bluez.Adapter1': {
          'Address': DBusString(address),
          'AddressType': DBusString(addressType),
          'Alias': DBusString(alias),
          'Class': DBusUint32(class_),
          'Discoverable': DBusBoolean(discoverable),
          'DiscoverableTimeout': DBusUint32(discoverableTimeout),
          'Discovering': DBusBoolean(discovering),
          'Modalias': DBusString(modalias),
          'Name': DBusString(name),
          'Pairable': DBusBoolean(pairable),
          'PairableTimeout': DBusUint32(pairableTimeout),
          'Powered': DBusBoolean(powered),
          'Roles': DBusArray.string(roles),
          'UUIDs': DBusArray.string(uuids)
        }
      };

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface != 'org.bluez.Adapter1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    if (name == 'Alias') {
      alias = value.asString();
    } else if (name == 'Discoverable') {
      discoverable = value.asBoolean();
    } else if (name == 'DiscoverableTimeout') {
      discoverableTimeout = value.asUint32();
    } else if (name == 'Pairable') {
      pairable = value.asBoolean();
    } else if (name == 'PairableTimeout') {
      pairableTimeout = value.asUint32();
    } else if (name == 'Powered') {
      powered = value.asBoolean();
    } else {
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    switch (methodCall.interface) {
      case 'org.bluez.BatteryProviderManager1':
        switch (methodCall.name) {
          case 'RegisterBatteryProvider':
            var path = methodCall.values[0].asObjectPath();
            batteryProviders.add(MockBlueZBatteryProvider(client!,
                name: methodCall.sender!, path: path));
            return DBusMethodSuccessResponse();
          case 'UnregisterBatteryProvider':
            var path = methodCall.values[0].asObjectPath();
            var provider = batteryProviders
                .firstWhere((provider) => provider.path == path);
            await provider.close();
            batteryProviders.remove(provider);
            return DBusMethodSuccessResponse();
          default:
            return DBusMethodErrorResponse.unknownMethod();
        }
      case 'org.bluez.Adapter1':
        switch (methodCall.name) {
          case 'GetDiscoveryFilters':
            return DBusMethodSuccessResponse(
                [DBusArray.string(discoveryFilter.keys)]);
          case 'RemoveDevice':
            var path = methodCall.values[0].asObjectPath();
            var devices = server.devices.where((device) => device.path == path);
            if (devices.isEmpty) {
              return DBusMethodErrorResponse('org.bluez.Error.DoesNotExist');
            }
            await server.removeDevice(devices.first);
            return DBusMethodSuccessResponse();
          case 'SetDiscoveryFilter':
            var properties = methodCall.values[0].asStringVariantDict();
            discoveryFilter.addAll(properties);
            return DBusMethodSuccessResponse();
          case 'StartDiscovery':
            discovering = true;
            return DBusMethodSuccessResponse();
          case 'StopDiscovery':
            discovering = false;
            return DBusMethodSuccessResponse();
          default:
            return DBusMethodErrorResponse.unknownMethod();
        }
      default:
        return DBusMethodErrorResponse.unknownInterface();
    }
  }

  void changeProperties(
      {bool? discoverable,
      bool? discovering,
      bool? pairable,
      bool? powered}) async {
    var changedProperties = <String, DBusValue>{};
    if (discoverable != null) {
      this.discoverable = discoverable;
      changedProperties['Discoverable'] = DBusBoolean(discoverable);
    }
    if (discovering != null) {
      this.discovering = discovering;
      changedProperties['Discovering'] = DBusBoolean(discovering);
    }
    if (pairable != null) {
      this.pairable = pairable;
      changedProperties['Pairable'] = DBusBoolean(pairable);
    }
    if (powered != null) {
      this.powered = powered;
      changedProperties['Powered'] = DBusBoolean(powered);
    }
    await emitPropertiesChanged('org.bluez.Adapter1',
        changedProperties: changedProperties);
  }
}

enum MockBlueZDeviceAuthType {
  none,
  confirm,
  confirmPinCode,
  confirmPasskey,
  requestPinCode,
  requestPasskey
}

class MockBlueZDeviceObject extends MockBlueZObject {
  final MockBlueZAdapterObject adapter;
  MockBlueZServer get server => adapter.server;

  final String address;
  final String addressType;
  String alias;
  final int appearance;
  final MockBlueZDeviceAuthType authType;
  bool blocked;
  final int class_;
  bool connected;
  var connectedProfiles = <String>{};
  final String icon;
  final bool legacyPairing;
  final Map<int, DBusValue> manufacturerData;
  final String modalias;
  final String name;
  bool paired;
  final int? passkey;
  final String? pinCode;
  int rssi;
  final Map<String, DBusValue> serviceData;
  final bool servicesResolved;
  bool trusted;
  final int txPower;
  bool wakeAllowed;
  final List<String> uuids;

  MockBlueZDeviceObject(this.adapter,
      {required this.address,
      this.addressType = 'public',
      this.alias = '',
      this.appearance = 0,
      this.authType = MockBlueZDeviceAuthType.none,
      this.blocked = false,
      this.class_ = 0,
      this.connected = false,
      Set<String> connectedProfiles = const {},
      this.icon = '',
      this.legacyPairing = false,
      this.manufacturerData = const {},
      this.modalias = '',
      this.name = '',
      this.paired = false,
      this.passkey,
      this.pinCode,
      this.rssi = 0,
      this.serviceData = const {},
      this.servicesResolved = false,
      this.trusted = false,
      this.txPower = 0,
      this.wakeAllowed = false,
      this.uuids = const []})
      : super(DBusObjectPath(
            '${adapter.path.value}/dev_${address.replaceAll(':', '_')}')) {
    this.connectedProfiles.addAll(connectedProfiles);
  }

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.bluez.Device1': {
          'Adapter': adapter.path,
          'Address': DBusString(address),
          'AddressType': DBusString(addressType),
          'Alias': DBusString(alias),
          'Appearance': DBusUint16(appearance),
          'Blocked': DBusBoolean(blocked),
          'Class': DBusUint32(class_),
          'Connected': DBusBoolean(connected),
          'Icon': DBusString(icon),
          'LegacyPairing': DBusBoolean(legacyPairing),
          'ManufacturerData': DBusDict(
              DBusSignature('q'),
              DBusSignature('v'),
              manufacturerData.map(
                  (id, value) => MapEntry(DBusUint16(id), DBusVariant(value)))),
          'Modalias': DBusString(modalias),
          'Name': DBusString(name),
          'Paired': DBusBoolean(paired),
          'RSSI': DBusInt16(rssi),
          'ServiceData': DBusDict.stringVariant(serviceData),
          'ServicesResolved': DBusBoolean(servicesResolved),
          'Trusted': DBusBoolean(trusted),
          'TxPower': DBusInt16(txPower),
          'WakeAllowed': DBusBoolean(wakeAllowed),
          'UUIDs': DBusArray.string(uuids)
        }
      };

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface != 'org.bluez.Device1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    if (name == 'Alias') {
      alias = value.asString();
    } else if (name == 'Blocked') {
      blocked = value.asBoolean();
    } else if (name == 'Trusted') {
      trusted = value.asBoolean();
    } else if (name == 'WakeAllowed') {
      wakeAllowed = value.asBoolean();
    } else {
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.Device1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'CancelPairing':
        return cancelPairing();
      case 'Connect':
        if (connected) {
          return DBusMethodErrorResponse('org.bluez.Error.AlreadyConnected');
        }
        await changeProperties(connected: true);
        return DBusMethodSuccessResponse();
      case 'Disconnect':
        if (!connected) {
          return DBusMethodErrorResponse('org.bluez.Error.NotConnected');
        }
        await changeProperties(connected: false);
        return DBusMethodSuccessResponse();
      case 'ConnectProfile':
        var uuid = methodCall.values[0].asString();
        if (!uuids.contains(uuid)) {
          return DBusMethodErrorResponse('org.bluez.Error.NotAvailable');
        }
        connectedProfiles.add(uuid);
        return DBusMethodSuccessResponse();
      case 'DisconnectProfile':
        var uuid = methodCall.values[0].asString();
        if (!connectedProfiles.contains(uuid)) {
          return DBusMethodErrorResponse('org.bluez.Error.InvalidArguments');
        }
        connectedProfiles.remove(uuid);
        return DBusMethodSuccessResponse();
      case 'Pair':
        return pair();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  Future<DBusMethodResponse> cancelPairing() async {
    if (server.agentAddress == null) {
      return DBusMethodErrorResponse('org.bluez.Error.AgentNotAvailable');
    }

    await client!.callMethod(
        destination: server.agentAddress,
        path: server.agentPath!,
        interface: 'org.bluez.Agent1',
        name: 'Cancel',
        replySignature: DBusSignature(''));

    return DBusMethodSuccessResponse();
  }

  Future<DBusMethodResponse> pair() async {
    switch (authType) {
      case MockBlueZDeviceAuthType.none:
        await changeProperties(paired: true);
        return DBusMethodSuccessResponse();
      case MockBlueZDeviceAuthType.confirm:
        if (server.agentAddress == null) {
          return DBusMethodErrorResponse('org.bluez.Error.AgentNotAvailable');
        }

        try {
          await client!.callMethod(
              destination: server.agentAddress,
              path: server.agentPath!,
              interface: 'org.bluez.Agent1',
              name: 'RequestAuthorization',
              values: [path],
              replySignature: DBusSignature(''));
        } on DBusMethodResponseException catch (e) {
          return processAuthErrorResponse(e.response);
        }
        await changeProperties(paired: true);
        return DBusMethodSuccessResponse();
      case MockBlueZDeviceAuthType.confirmPinCode:
        if (server.agentAddress == null) {
          return DBusMethodErrorResponse('org.bluez.Error.AgentNotAvailable');
        }

        try {
          await client!.callMethod(
              destination: server.agentAddress,
              path: server.agentPath!,
              interface: 'org.bluez.Agent1',
              name: 'DisplayPinCode',
              values: [path, DBusString(pinCode!)],
              replySignature: DBusSignature(''));
        } on DBusMethodResponseException catch (e) {
          return processAuthErrorResponse(e.response);
        }
        await changeProperties(paired: true);
        return DBusMethodSuccessResponse();
      case MockBlueZDeviceAuthType.confirmPasskey:
        if (server.agentAddress == null) {
          return DBusMethodErrorResponse('org.bluez.Error.AgentNotAvailable');
        }

        try {
          await client!.callMethod(
              destination: server.agentAddress,
              path: server.agentPath!,
              interface: 'org.bluez.Agent1',
              name: 'RequestConfirmation',
              values: [path, DBusUint32(passkey!)],
              replySignature: DBusSignature(''));
        } on DBusMethodResponseException catch (e) {
          return processAuthErrorResponse(e.response);
        }
        await changeProperties(paired: true);
        return DBusMethodSuccessResponse();
      case MockBlueZDeviceAuthType.requestPinCode:
        if (server.agentAddress == null) {
          return DBusMethodErrorResponse('org.bluez.Error.AgentNotAvailable');
        }

        DBusMethodSuccessResponse result;
        try {
          result = await client!.callMethod(
              destination: server.agentAddress,
              path: server.agentPath!,
              interface: 'org.bluez.Agent1',
              name: 'RequestPinCode',
              values: [path],
              replySignature: DBusSignature('s'));
        } on DBusMethodResponseException catch (e) {
          return processAuthErrorResponse(e.response);
        }

        var pinCodeValue = result.values[0].asString();
        if (pinCodeValue == pinCode) {
          await changeProperties(paired: true);
        }
        return DBusMethodSuccessResponse();
      case MockBlueZDeviceAuthType.requestPasskey:
        if (server.agentAddress == null) {
          return DBusMethodErrorResponse('org.bluez.Error.AgentNotAvailable');
        }

        DBusMethodSuccessResponse result;
        try {
          result = await client!.callMethod(
              destination: server.agentAddress,
              path: server.agentPath!,
              interface: 'org.bluez.Agent1',
              name: 'RequestPasskey',
              values: [path],
              replySignature: DBusSignature('u'));
        } on DBusMethodResponseException catch (e) {
          return processAuthErrorResponse(e.response);
        }

        var passkey = result.values[0].asUint32();
        if (passkey == this.passkey) {
          await changeProperties(paired: true);
        }
        return DBusMethodSuccessResponse();
    }
  }

  DBusMethodResponse processAuthErrorResponse(
      DBusMethodErrorResponse response) {
    if (response.errorName == 'org.bluez.Error.Rejected') {
      return DBusMethodErrorResponse('org.bluez.Error.AuthenticationRejected');
    } else if (response.errorName == 'org.bluez.Error.Canceled') {
      return DBusMethodErrorResponse('org.bluez.Error.AuthenticationCanceled');
    } else {
      return response;
    }
  }

  Future<void> changeProperties(
      {bool? connected, bool? paired, int? rssi}) async {
    var changedProperties = <String, DBusValue>{};
    if (connected != null) {
      this.connected = connected;
      changedProperties['Connected'] = DBusBoolean(connected);
    }
    if (paired != null) {
      this.paired = paired;
      changedProperties['Paired'] = DBusBoolean(paired);
    }
    if (rssi != null) {
      this.rssi = rssi;
      changedProperties['RSSI'] = DBusInt16(rssi);
    }
    await emitPropertiesChanged('org.bluez.Device1',
        changedProperties: changedProperties);
  }
}

class MockBlueZGattServiceObject extends MockBlueZObject {
  final MockBlueZDeviceObject device;

  final int id;
  final List<MockBlueZGattServiceObject> includes;
  final bool primary;
  final String uuid;

  MockBlueZGattServiceObject(this.device, this.id,
      {this.includes = const [], this.primary = true, required this.uuid})
      : super(DBusObjectPath(
            '${device.path.value}/service${id.toRadixString(16).padLeft(4, '0')}'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.bluez.GattService1': {
          'Device': device.path,
          'Includes':
              DBusArray.objectPath(includes.map((service) => service.path)),
          'Primary': DBusBoolean(primary),
          'UUID': DBusString(uuid)
        }
      };
}

class MockBlueZGattCharacteristicObject extends MockBlueZObject {
  final MockBlueZGattServiceObject service;

  final int id;
  final List<String> flags;
  final int mtu;
  var notifyAcquired = false;
  var notifying = false;
  var writeAcquired = false;
  var value = <int>[];
  final String uuid;
  final _writtenDataCompleter = Completer<List<int>>();
  Future<List<int>> get writtenData => _writtenDataCompleter.future;
  RawSocket? notifySocket;

  MockBlueZGattCharacteristicObject(this.service, this.id,
      {this.flags = const [],
      this.mtu = 0,
      required this.uuid,
      List<int> value = const []})
      : super(DBusObjectPath(
            '${service.path.value}/char${id.toRadixString(16).padLeft(4, '0')}')) {
    this.value.addAll(value);
  }

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.bluez.GattCharacteristic1': {
          'Flags': DBusArray.string(flags),
          'NotifyAcquired': DBusBoolean(notifyAcquired),
          'Notifying': DBusBoolean(notifying),
          'WriteAcquired': DBusBoolean(writeAcquired),
          'Service': service.path,
          'UUID': DBusString(uuid),
          'Value': DBusArray.byte(value),
          'MTU': DBusUint16(mtu),
        }
      };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.GattCharacteristic1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'ReadValue':
        var options = methodCall.values[0].asStringVariantDict();
        var offset = options['offset']?.asUint16() ?? 0;
        return DBusMethodSuccessResponse([DBusArray.byte(value.skip(offset))]);
      case 'WriteValue':
        var data = methodCall.values[0].asByteArray();
        var options = methodCall.values[1].asStringVariantDict();
        var offset = options['offset']?.asUint16() ?? 0;
        value.removeRange(offset, offset + data.length);
        value.insertAll(offset, data);
        return DBusMethodSuccessResponse();
      case 'AcquireWrite':
        if (writeAcquired) {
          return DBusMethodErrorResponse('org.bluez.Error.Failed');
        }
        await changeProperties(writeAcquired: true);
        var address = makeRandomUnixAddress();
        var serverSocket = await ServerSocket.bind(address, 0);
        RawSocket? socket;
        unawaited(serverSocket.first.then((childSocket) async {
          _writtenDataCompleter.complete(await childSocket.first);
          await childSocket.close();
          await serverSocket.close();
          await socket?.close();
        }));
        socket = await RawSocket.connect(address, 0);
        var handle = ResourceHandle.fromRawSocket(socket);
        return DBusMethodSuccessResponse([DBusUnixFd(handle), DBusUint16(mtu)]);
      case 'AcquireNotify':
        if (notifyAcquired) {
          return DBusMethodErrorResponse('org.bluez.Error.Failed');
        }
        await changeProperties(notifyAcquired: true);
        var address = makeRandomUnixAddress();
        RawSocket? socket;
        var serverSocket = await RawServerSocket.bind(address, 0);
        unawaited(serverSocket.first.then((childSocket) {
          notifySocket = childSocket;
          childSocket.listen((event) {
            if (event == RawSocketEvent.closed) {
              childSocket.close();
              serverSocket.close();
              socket?.close();
            }
          });
        }));
        socket = await RawSocket.connect(address, 0);
        var handle = ResourceHandle.fromRawSocket(socket);
        return DBusMethodSuccessResponse([DBusUnixFd(handle), DBusUint16(mtu)]);
      case 'StartNotify':
        if (notifying) {
          return DBusMethodErrorResponse('org.bluez.Error.InProgress');
        }
        await changeProperties(notifying: true);
        return DBusMethodSuccessResponse();
      case 'StopNotify':
        if (!notifying) {
          return DBusMethodSuccessResponse();
        }
        await changeProperties(notifying: false);
        return DBusMethodSuccessResponse();
      case 'MTU':
        return DBusMethodSuccessResponse([DBusUint16(mtu)]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  Future<void> changeProperties(
      {bool? notifyAcquired,
      bool? notifying,
      List<int>? value,
      bool? writeAcquired}) async {
    var changedProperties = <String, DBusValue>{};
    if (notifyAcquired != null) {
      this.notifyAcquired = notifyAcquired;
      changedProperties['NotifyAcquired'] = DBusBoolean(notifyAcquired);
    }
    if (notifying != null) {
      this.notifying = notifying;
      changedProperties['Notifying'] = DBusBoolean(notifying);
    }
    if (value != null) {
      this.value = value;
      changedProperties['Value'] = DBusArray.byte(value);
    }
    if (writeAcquired != null) {
      this.writeAcquired = writeAcquired;
      changedProperties['WriteAcquired'] = DBusBoolean(writeAcquired);
    }
    await emitPropertiesChanged('org.bluez.GattCharacteristic1',
        changedProperties: changedProperties);
  }

  Future<void> setValue(List<int> value) async {
    if (notifying) {
      await changeProperties(value: value);
    } else if (notifySocket != null) {
      notifySocket!.write(value);
    } else {
      value = value;
    }
  }
}

class MockBlueZGattDescriptorObject extends MockBlueZObject {
  final MockBlueZGattCharacteristicObject characteristic;

  final int id;
  final List<int> value;
  final String uuid;

  MockBlueZGattDescriptorObject(this.characteristic, this.id,
      {required this.uuid, this.value = const []})
      : super(DBusObjectPath(
            '${characteristic.path.value}/desc${id.toRadixString(16).padLeft(4, '0')}'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.bluez.GattDescriptor1': {
          'Characteristic': characteristic.path,
          'UUID': DBusString(uuid),
          'Value': DBusArray.byte(value)
        }
      };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.GattDescriptor1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    switch (methodCall.name) {
      case 'ReadValue':
        var options = methodCall.values[0].asStringVariantDict();
        var offset = options['offset']?.asUint16() ?? 0;
        return DBusMethodSuccessResponse([DBusArray.byte(value.skip(offset))]);
      case 'WriteValue':
        var data = methodCall.values[0].asByteArray();
        var options = methodCall.values[1].asStringVariantDict();
        var offset = options['offset']?.asUint16() ?? 0;
        value.removeRange(offset, offset + data.length);
        value.insertAll(offset, data);
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

class MockBlueZMediaPlayerObject extends MockBlueZObject {
  final MockBlueZDeviceObject device;

  String status;
  int position;

  /// What a live Properties.Get for Position answers, when it should differ
  /// from the cached [position] - which is how BlueZ really behaves, since it
  /// computes the property on read but only signals it on a seek.
  int? livePosition;

  Map<String, DBusValue> track;
  String name;
  String type;
  String subtype;
  bool browsable;
  bool searchable;
  String? equalizer;
  String? repeat;
  String? shuffle;
  String? scan;

  /// Every method call received, in order, so a test can assert what went out
  /// rather than only what came back.
  final calls = <String>[];

  MockBlueZMediaPlayerObject(
    this.device, {
    this.status = 'stopped',
    this.position = 0,
    this.livePosition,
    this.track = const {},
    this.name = '',
    this.type = '',
    this.subtype = '',
    this.browsable = false,
    this.searchable = false,
    this.equalizer,
    this.repeat,
    this.shuffle,
    this.scan,
  }) : super(DBusObjectPath('${device.path.value}/player0'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties =>
      {'org.bluez.MediaPlayer1': _properties()};

  Map<String, DBusValue> _properties() => {
        'Device': device.path,
        'Name': DBusString(name),
        'Type': DBusString(type),
        'Subtype': DBusString(subtype),
        'Status': DBusString(status),
        'Position': DBusUint32(position),
        'Browsable': DBusBoolean(browsable),
        'Searchable': DBusBoolean(searchable),
        if (equalizer != null) 'Equalizer': DBusString(equalizer!),
        if (repeat != null) 'Repeat': DBusString(repeat!),
        if (shuffle != null) 'Shuffle': DBusString(shuffle!),
        if (scan != null) 'Scan': DBusString(scan!),
        'Track': DBusDict(
            DBusSignature('s'),
            DBusSignature('v'),
            track.map(
                (key, value) => MapEntry(DBusString(key), DBusVariant(value)))),
      };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'org.bluez.MediaPlayer1') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (name == 'Position') {
      return DBusGetPropertyResponse(DBusUint32(livePosition ?? position));
    }
    var value = _properties()[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface != 'org.bluez.MediaPlayer1') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (name) {
      case 'Equalizer':
        equalizer = value.asString();
        break;
      case 'Repeat':
        repeat = value.asString();
        break;
      case 'Shuffle':
        shuffle = value.asString();
        break;
      case 'Scan':
        scan = value.asString();
        break;
      default:
        return DBusMethodErrorResponse.propertyReadOnly();
    }
    await emitPropertiesChanged('org.bluez.MediaPlayer1',
        changedProperties: {name: value});
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.MediaPlayer1') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'Play':
      case 'Pause':
      case 'Stop':
      case 'Next':
      case 'Previous':
      case 'FastForward':
      case 'Rewind':
      case 'Release':
        calls.add(methodCall.name);
        return DBusMethodSuccessResponse();
      case 'Press':
      case 'Hold':
        calls.add('${methodCall.name}:${methodCall.values[0].asByte()}');
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  /// Pushes a change the way BlueZ would, so a listener sees it.
  Future<void> change(Map<String, DBusValue> changed) async {
    for (var entry in changed.entries) {
      switch (entry.key) {
        case 'Status':
          status = entry.value.asString();
          break;
        case 'Position':
          position = entry.value.asUint32();
          break;
      }
    }
    await emitPropertiesChanged('org.bluez.MediaPlayer1',
        changedProperties: changed);
  }
}

class MockBlueZMediaTransportObject extends MockBlueZObject {
  final MockBlueZDeviceObject device;

  final String uuid;
  final int codec;
  final List<int> configuration;
  final String state;
  final int? delay;
  int? volume;

  MockBlueZMediaTransportObject(
    this.device, {
    this.uuid = '0000110a-0000-1000-8000-00805f9b34fb',
    this.codec = 0,
    this.configuration = const [],
    this.state = 'idle',
    this.delay,
    this.volume,
  }) : super(DBusObjectPath('${device.path.value}/fd0'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        'org.bluez.MediaTransport1': {
          'Device': device.path,
          'UUID': DBusString(uuid),
          'Codec': DBusByte(codec),
          'Configuration': DBusArray.byte(configuration),
          'State': DBusString(state),
          if (delay != null) 'Delay': DBusUint16(delay!),
          if (volume != null) 'Volume': DBusUint16(volume!),
        }
      };

  @override
  Future<DBusMethodResponse> setProperty(
      String interface, String name, DBusValue value) async {
    if (interface != 'org.bluez.MediaTransport1') {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (name != 'Volume') {
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    volume = value.asUint16();
    await emitPropertiesChanged('org.bluez.MediaTransport1',
        changedProperties: {'Volume': value});
    return DBusMethodSuccessResponse();
  }
}

class MockBlueZServer extends DBusClient {
  late final DBusObject root;

  String? agentAddress;
  DBusObjectPath? agentPath;
  String agentCapability = '';
  bool agentIsDefault = false;

  final adapters = <MockBlueZAdapterObject>[];
  final devices = <MockBlueZDeviceObject>[];

  MockBlueZServer(DBusAddress clientAddress) : super(clientAddress);

  Future<void> start() async {
    await requestName('org.bluez');
    root = DBusObject(DBusObjectPath('/'), isObjectManager: true);
    await registerObject(root);

    var manager = MockBlueZManagerObject(this);
    await registerObject(manager);
  }

  Future<MockBlueZAdapterObject> addAdapter(String deviceName,
      {String address = '',
      String addressType = 'public',
      String alias = '',
      int class_ = 0,
      bool discoverable = false,
      int discoverableTimeout = 0,
      bool discovering = false,
      Map<String, DBusValue> discoveryFilter = const {},
      String modalias = '',
      String name = '',
      bool pairable = false,
      int pairableTimeout = 0,
      bool powered = true,
      List<String> roles = const [],
      List<String> uuids = const []}) async {
    var adapter = MockBlueZAdapterObject(this, deviceName,
        address: address,
        addressType: addressType,
        alias: alias,
        class_: class_,
        discoverable: discoverable,
        discoverableTimeout: discoverableTimeout,
        discovering: discovering,
        discoveryFilter: discoveryFilter,
        modalias: modalias,
        name: name,
        pairable: pairable,
        pairableTimeout: pairableTimeout,
        powered: powered,
        roles: roles,
        uuids: uuids);
    adapters.add(adapter);
    await registerObject(adapter);
    return adapter;
  }

  Future<void> removeAdapter(MockBlueZAdapterObject adapter) async {
    adapters.remove(adapter);
    await unregisterObject(adapter);
  }

  Future<MockBlueZDeviceObject> addDevice(MockBlueZAdapterObject adapter,
      {required String address,
      String addressType = 'public',
      String alias = '',
      int appearance = 0,
      MockBlueZDeviceAuthType authType = MockBlueZDeviceAuthType.none,
      bool blocked = false,
      int class_ = 0,
      bool connected = false,
      Set<String> connectedProfiles = const {},
      String icon = '',
      bool legacyPairing = false,
      Map<int, DBusValue> manufacturerData = const {},
      String modalias = '',
      String name = '',
      bool paired = false,
      int? passkey,
      String? pinCode,
      int rssi = 0,
      Map<String, DBusValue> serviceData = const {},
      bool servicesResolved = false,
      bool trusted = false,
      int txPower = 0,
      List<String> uuids = const [],
      bool wakeAllowed = false}) async {
    var device = MockBlueZDeviceObject(adapter,
        address: address,
        addressType: addressType,
        alias: alias,
        appearance: appearance,
        authType: authType,
        blocked: blocked,
        class_: class_,
        connected: connected,
        connectedProfiles: connectedProfiles,
        icon: icon,
        legacyPairing: legacyPairing,
        manufacturerData: manufacturerData,
        modalias: modalias,
        name: name,
        paired: paired,
        passkey: passkey,
        pinCode: pinCode,
        rssi: rssi,
        serviceData: serviceData,
        servicesResolved: servicesResolved,
        trusted: trusted,
        txPower: txPower,
        wakeAllowed: wakeAllowed,
        uuids: uuids);
    devices.add(device);
    await registerObject(device);
    return device;
  }

  Future<void> removeDevice(MockBlueZDeviceObject device) async {
    devices.remove(device);
    await unregisterObject(device);
  }

  Future<MockBlueZMediaPlayerObject> addMediaPlayer(
      MockBlueZDeviceObject device,
      {String status = 'stopped',
      int position = 0,
      int? livePosition,
      Map<String, DBusValue> track = const {},
      String name = '',
      String type = '',
      String subtype = '',
      bool browsable = false,
      bool searchable = false,
      String? equalizer,
      String? repeat,
      String? shuffle,
      String? scan}) async {
    var player = MockBlueZMediaPlayerObject(device,
        status: status,
        position: position,
        livePosition: livePosition,
        track: track,
        name: name,
        type: type,
        subtype: subtype,
        browsable: browsable,
        searchable: searchable,
        equalizer: equalizer,
        repeat: repeat,
        shuffle: shuffle,
        scan: scan);
    await registerObject(player);
    return player;
  }

  Future<void> removeMediaPlayer(MockBlueZMediaPlayerObject player) =>
      unregisterObject(player);

  Future<MockBlueZMediaTransportObject> addMediaTransport(
      MockBlueZDeviceObject device,
      {String uuid = '0000110a-0000-1000-8000-00805f9b34fb',
      int codec = 0,
      List<int> configuration = const [],
      String state = 'idle',
      int? delay,
      int? volume}) async {
    var transport = MockBlueZMediaTransportObject(device,
        uuid: uuid,
        codec: codec,
        configuration: configuration,
        state: state,
        delay: delay,
        volume: volume);
    await registerObject(transport);
    return transport;
  }

  Future<MockBlueZGattServiceObject> addService(
      MockBlueZDeviceObject device, int id,
      {List<MockBlueZGattServiceObject> includes = const [],
      bool primary = true,
      required String uuid}) async {
    var service = MockBlueZGattServiceObject(device, id,
        includes: includes, primary: primary, uuid: uuid);
    await registerObject(service);
    return service;
  }

  Future<MockBlueZGattCharacteristicObject> addCharacteristic(
      MockBlueZGattServiceObject service, int id,
      {List<String> flags = const [],
      int mtu = 0,
      List<int> value = const [],
      required String uuid}) async {
    var characteristic = MockBlueZGattCharacteristicObject(service, id,
        flags: flags, mtu: mtu, value: value, uuid: uuid);
    await registerObject(characteristic);
    return characteristic;
  }

  Future<MockBlueZGattDescriptorObject> addDescriptor(
      MockBlueZGattCharacteristicObject service, int id,
      {List<int> value = const [], required String uuid}) async {
    var characteristic =
        MockBlueZGattDescriptorObject(service, id, value: value, uuid: uuid);
    await registerObject(characteristic);
    return characteristic;
  }
}

class TestAgent extends BlueZAgent {
  final String? pinCode;
  final int? passkey;
  String? lastPinCode;
  var pinCodeRequested = false;
  int? lastPasskey;
  var passkeyRequested = false;
  var authRequested = false;
  var released = false;

  TestAgent({this.pinCode, this.passkey});

  @override
  Future<void> release() async {
    released = true;
  }

  @override
  Future<BlueZAgentPinCodeResponse> requestPinCode(BlueZDevice device) async {
    pinCodeRequested = true;
    if (pinCode != null) {
      return BlueZAgentPinCodeResponse.success(pinCode!);
    } else {
      return BlueZAgentPinCodeResponse.rejected();
    }
  }

  @override
  Future<BlueZAgentResponse> displayPinCode(
      BlueZDevice device, String pinCode) async {
    lastPinCode = pinCode;
    return BlueZAgentResponse.success();
  }

  @override
  Future<BlueZAgentPasskeyResponse> requestPasskey(BlueZDevice device) async {
    passkeyRequested = true;
    if (passkey != null) {
      return BlueZAgentPasskeyResponse.success(passkey!);
    } else {
      return BlueZAgentPasskeyResponse.rejected();
    }
  }

  @override
  Future<BlueZAgentResponse> requestConfirmation(
      BlueZDevice device, int passkey) async {
    lastPasskey = passkey;
    return BlueZAgentResponse.success();
  }

  @override
  Future<BlueZAgentResponse> requestAuthorization(BlueZDevice device) async {
    authRequested = true;
    return BlueZAgentResponse.success();
  }
}

class TestEmptyAgent extends BlueZAgent {}

class TestCancelAgent extends BlueZAgent {
  Completer<BlueZAgentResponse>? completer;
  Completer<BlueZAgentPinCodeResponse>? pinCodeCompleter;
  Completer<BlueZAgentPasskeyResponse>? passkeyCompleter;

  @override
  Future<BlueZAgentPinCodeResponse> requestPinCode(BlueZDevice device) async {
    if (completer != null ||
        pinCodeCompleter != null ||
        passkeyCompleter != null) {
      return BlueZAgentPinCodeResponse.rejected();
    }
    pinCodeCompleter = Completer<BlueZAgentPinCodeResponse>();
    return pinCodeCompleter!.future;
  }

  @override
  Future<BlueZAgentResponse> displayPinCode(
      BlueZDevice device, String pinCode) async {
    if (completer != null ||
        pinCodeCompleter != null ||
        passkeyCompleter != null) {
      return BlueZAgentResponse.rejected();
    }
    completer = Completer<BlueZAgentResponse>();
    return completer!.future;
  }

  @override
  Future<BlueZAgentPasskeyResponse> requestPasskey(BlueZDevice device) async {
    if (completer != null ||
        pinCodeCompleter != null ||
        passkeyCompleter != null) {
      return BlueZAgentPasskeyResponse.rejected();
    }
    passkeyCompleter = Completer<BlueZAgentPasskeyResponse>();
    return passkeyCompleter!.future;
  }

  @override
  Future<BlueZAgentResponse> requestConfirmation(
      BlueZDevice device, int passkey) async {
    if (completer != null ||
        pinCodeCompleter != null ||
        passkeyCompleter != null) {
      return BlueZAgentResponse.rejected();
    }
    completer = Completer<BlueZAgentResponse>();
    return completer!.future;
  }

  @override
  Future<BlueZAgentResponse> requestAuthorization(BlueZDevice device) async {
    if (completer != null ||
        pinCodeCompleter != null ||
        passkeyCompleter != null) {
      return BlueZAgentResponse.rejected();
    }
    completer = Completer<BlueZAgentResponse>();
    return completer!.future;
  }

  @override
  Future<void> cancel() async {
    completer?.complete(BlueZAgentResponse.canceled());
    completer = null;
    pinCodeCompleter?.complete(BlueZAgentPinCodeResponse.canceled());
    pinCodeCompleter = null;
    passkeyCompleter?.complete(BlueZAgentPasskeyResponse.canceled());
    passkeyCompleter = null;
  }
}

void main() {
  test('uuid', () async {
    // Too short.
    expect(() => BlueZUUID([]), throwsFormatException);
    expect(() => BlueZUUID([1, 2, 3]), throwsFormatException);

    // Invalid strings.
    expect(() => BlueZUUID.fromString(''), throwsFormatException);
    expect(() => BlueZUUID.fromString('000004d200001000800000805f9b34fb'),
        throwsFormatException);
    expect(
        () => BlueZUUID.fromString('0000-04d2-0000-1000-8000-0080-5f9b-34fb'),
        throwsFormatException);
    expect(() => BlueZUUID.fromString('4d2-0-1000-8000-805f9b34fb'),
        throwsFormatException);
    expect(() => BlueZUUID.fromString('xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'),
        throwsFormatException);

    // Different constructors.
    expect(
        BlueZUUID(
            [0, 0, 4, 210, 0, 0, 16, 0, 128, 0, 0, 128, 95, 155, 52, 251]),
        equals(BlueZUUID.fromString('000004d2-0000-1000-8000-00805f9b34fb')));
    expect(BlueZUUID.fromString('000004d2-0000-1000-8000-00805f9b34fb'),
        equals(BlueZUUID.fromString('000004d2-0000-1000-8000-00805f9b34fb')));
    expect(BlueZUUID.short(1234),
        equals(BlueZUUID.fromString('000004d2-0000-1000-8000-00805f9b34fb')));

    // Can determine which UUIDs are in short form.
    expect(BlueZUUID.fromString('000004d2-0000-1000-8000-00805f9b34fb').isShort,
        isTrue);
    expect(BlueZUUID.fromString('e95d0753-251d-470a-a062-fa1922dfa9a8').isShort,
        isFalse);

    // Can read raw value.
    expect(BlueZUUID.fromString('000004d2-0000-1000-8000-00805f9b34fb').value,
        equals([0, 0, 4, 210, 0, 0, 16, 0, 128, 0, 0, 128, 95, 155, 52, 251]));
  });

  test('no adapters or devices', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, isEmpty);
    expect(client.devices, isEmpty);
  });

  test('adapters', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    await bluez.addAdapter('hci0', address: 'AD:A9:7E:F0:00:01');
    await bluez.addAdapter('hci1', address: 'AD:A9:7E:F0:00:02');
    await bluez.addAdapter('hci2', address: 'AD:A9:7E:F0:00:03');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(3));
    expect(client.adapters[0].address, equals('AD:A9:7E:F0:00:01'));
    expect(client.adapters[1].address, equals('AD:A9:7E:F0:00:02'));
    expect(client.adapters[2].address, equals('AD:A9:7E:F0:00:03'));
  });

  test('adapter added', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    client.adapterAdded.listen(expectAsync1((adapter) {
      expect(adapter.address, equals('AD:A9:7E:F0:00:01'));
    }));

    await bluez.addAdapter('hci0', address: 'AD:A9:7E:F0:00:01');
  });

  test('adapter removed', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var adapter = await bluez.addAdapter('hci0', address: 'AD:A9:7E:F0:00:01');

    client.adapterRemoved.listen(expectAsync1((adapter) {
      expect(adapter.address, equals('AD:A9:7E:F0:00:01'));
    }));

    await bluez.removeAdapter(adapter);
  });

  test('adapter properties', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    await bluez.addAdapter('hci0',
        address: 'AD:A9:7E:F0:00:01',
        addressType: 'public',
        alias: 'Test Adapter Alias',
        class_: 777,
        discoverable: true,
        discoverableTimeout: 60,
        discovering: true,
        modalias: 'usb:adapter1',
        name: 'Test Adapter',
        pairable: true,
        pairableTimeout: 120,
        powered: true,
        roles: [
          'role1',
          'role2'
        ],
        uuids: [
          '00000001-0000-1000-8000-00805f9b34fb',
          '00000002-0000-1000-8000-00805f9b34fb'
        ]);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(1));
    var adapter = client.adapters[0];
    expect(adapter.address, equals('AD:A9:7E:F0:00:01'));
    expect(adapter.addressType, equals(BlueZAddressType.public));
    expect(adapter.alias, equals('Test Adapter Alias'));
    expect(adapter.deviceClass, equals(777));
    expect(adapter.discoverable, isTrue);
    expect(adapter.discoverableTimeout, equals(60));
    expect(adapter.discovering, isTrue);
    expect(adapter.modalias, equals('usb:adapter1'));
    expect(adapter.name, equals('Test Adapter'));
    expect(adapter.pairable, isTrue);
    expect(adapter.pairableTimeout, equals(120));
    expect(adapter.powered, isTrue);
    expect(adapter.roles, equals(['role1', 'role2']));
    expect(adapter.uuids, equals([BlueZUUID.short(1), BlueZUUID.short(2)]));
  });

  test('adapter set properties', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0',
        alias: 'Original Alias',
        discoverable: false,
        discoverableTimeout: 0,
        pairable: false,
        pairableTimeout: 0,
        powered: false);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(1));
    var adapter = client.adapters[0];

    expect(a.alias, equals('Original Alias'));
    await adapter.setAlias('New Alias');
    expect(a.alias, equals('New Alias'));

    expect(a.discoverable, isFalse);
    expect(a.discoverableTimeout, equals(0));
    await adapter.setDiscoverable(true);
    await adapter.setDiscoverableTimeout(60);
    expect(a.discoverable, isTrue);
    expect(a.discoverableTimeout, equals(60));

    expect(a.pairable, isFalse);
    expect(a.pairableTimeout, equals(0));
    await adapter.setPairable(true);
    await adapter.setPairableTimeout(60);
    expect(a.pairable, isTrue);
    expect(a.pairableTimeout, equals(60));

    expect(a.powered, isFalse);
    await adapter.setPowered(true);
    expect(a.powered, isTrue);
  });

  test('adapter properties changed', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0', powered: false, discovering: false);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(1));
    var adapter = client.adapters[0];
    adapter.propertiesChanged.listen(expectAsync1((properties) {
      expect(properties, equals(['Discovering', 'Powered']));
      expect(adapter.discovering, isTrue);
      expect(adapter.powered, isTrue);
    }));

    a.changeProperties(powered: true, discovering: true);
  });

  test('adapter discover', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));

    addTearDown(() async => await server.close());
    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0', discoveryFilter: {
      'UUIDs': DBusArray.string([]),
      'RSSI': DBusInt16(-50),
      'Pathloss': DBusUint16(0),
      'Transport': DBusString('auto'),
      'DuplicateData': DBusBoolean(true),
      'Discoverable': DBusBoolean(false),
      'Pattern': DBusString('')
    });

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(1));
    var adapter = client.adapters[0];

    expect(
        await adapter.getDiscoveryFilters(),
        equals([
          'UUIDs',
          'RSSI',
          'Pathloss',
          'Transport',
          'DuplicateData',
          'Discoverable',
          'Pattern'
        ]));

    await adapter.setDiscoveryFilter(
        uuids: [
          '00000001-0000-1000-8000-00805f9b34fb',
          '00000002-0000-1000-8000-00805f9b34fb'
        ],
        rssi: -99,
        pathloss: 42,
        transport: 'le',
        duplicateData: false,
        discoverable: true,
        pattern: 'foo');
    expect(
        a.discoveryFilter,
        equals({
          'UUIDs': DBusArray(DBusSignature('s'), [
            DBusString('00000001-0000-1000-8000-00805f9b34fb'),
            DBusString('00000002-0000-1000-8000-00805f9b34fb')
          ]),
          'RSSI': DBusInt16(-99),
          'Pathloss': DBusUint16(42),
          'Transport': DBusString('le'),
          'DuplicateData': DBusBoolean(false),
          'Discoverable': DBusBoolean(true),
          'Pattern': DBusString('foo')
        }));

    expect(a.discovering, isFalse);
    await adapter.startDiscovery();
    expect(a.discovering, isTrue);
    await adapter.stopDiscovery();
    expect(a.discovering, isFalse);
  });

  test('no devices', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    await bluez.addAdapter('hci0');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, isEmpty);
  });

  test('devices', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter(
      'hci0',
    );
    await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');
    await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:02');
    await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:03');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(3));
    expect(client.devices[0].address, equals('DE:71:CE:00:00:01'));
    expect(client.devices[1].address, equals('DE:71:CE:00:00:02'));
    expect(client.devices[2].address, equals('DE:71:CE:00:00:03'));
  });

  test('device added', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var adapter = await bluez.addAdapter('hci0');

    client.deviceAdded.listen(expectAsync1((device) {
      expect(device.address, equals('DE:71:CE:00:00:01'));
    }));

    await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');
  });

  test('device removed', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();

    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');

    client.deviceRemoved.listen(expectAsync1((device) {
      expect(device.address, equals('DE:71:CE:00:00:01'));
    }));

    await bluez.removeDevice(device);
  });

  test('remove device', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:02');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:03');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();

    expect(bluez.devices, hasLength(3));
    var adapter = client.adapters[0];
    await adapter.removeDevice(client.devices[1]);
    expect(bluez.devices, hasLength(2));
    expect(bluez.devices[0].address, equals('DE:71:CE:00:00:01'));
    expect(bluez.devices[1].address, equals('DE:71:CE:00:00:03'));
  });

  test('device properties', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0', address: 'AD:A9:7E:F0:00:01');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        addressType: 'public',
        alias: 'Test Device Alias',
        appearance: 0x03C1,
        blocked: true,
        class_: 999,
        connected: true,
        icon: 'keyboard',
        legacyPairing: true,
        manufacturerData: {
          0: DBusArray.byte([1, 2, 3]),
          1: DBusArray.byte([4, 5, 6])
        },
        modalias: 'usb:device1',
        name: 'Test Device',
        paired: true,
        rssi: 123,
        serviceData: {
          '00000001-0000-1000-8000-00805f9b34fb': DBusArray.byte([1, 2, 3]),
          '00000002-0000-1000-8000-00805f9b34fb': DBusArray.byte([4, 5, 6])
        },
        servicesResolved: true,
        trusted: true,
        txPower: 456,
        uuids: [
          '00000001-0000-1000-8000-00805f9b34fb',
          '00000002-0000-1000-8000-00805f9b34fb'
        ],
        wakeAllowed: true);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.adapter.address, equals('AD:A9:7E:F0:00:01'));
    expect(device.address, equals('DE:71:CE:00:00:01'));
    expect(device.addressType, equals(BlueZAddressType.public));
    expect(device.alias, equals('Test Device Alias'));
    expect(device.appearance, equals(0x03C1));
    expect(device.blocked, isTrue);
    expect(device.connected, isTrue);
    expect(device.deviceClass, equals(999));
    expect(device.icon, equals('keyboard'));
    expect(device.legacyPairing, isTrue);
    expect(
        device.manufacturerData,
        equals({
          BlueZManufacturerId(0): [1, 2, 3],
          BlueZManufacturerId(1): [4, 5, 6]
        }));
    expect(device.modalias, equals('usb:device1'));
    expect(device.name, equals('Test Device'));
    expect(device.paired, isTrue);
    expect(device.rssi, equals(123));
    expect(
        device.serviceData,
        equals({
          BlueZUUID.fromString('00000001-0000-1000-8000-00805f9b34fb'): [
            1,
            2,
            3
          ],
          BlueZUUID.fromString('00000002-0000-1000-8000-00805f9b34fb'): [
            4,
            5,
            6
          ]
        }));
    expect(device.servicesResolved, isTrue);
    expect(device.trusted, isTrue);
    expect(device.txPower, equals(456));
    expect(device.uuids, equals([BlueZUUID.short(1), BlueZUUID.short(2)]));
    expect(device.wakeAllowed, isTrue);
  });

  test('device set properties', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        alias: 'Original Alias',
        blocked: false,
        trusted: false,
        wakeAllowed: false);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(d.alias, equals('Original Alias'));
    await device.setAlias('New Alias');
    expect(d.alias, equals('New Alias'));

    expect(d.blocked, isFalse);
    await device.setBlocked(true);
    expect(d.blocked, isTrue);

    expect(d.trusted, isFalse);
    await device.setTrusted(true);
    expect(d.trusted, isTrue);

    expect(d.wakeAllowed, isFalse);
    await device.setWakeAllowed(true);
    expect(d.wakeAllowed, isTrue);
  });

  test('device connect', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01', connected: false);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.connected, isFalse);
    await device.connect();
    expect(device.connected, isTrue);
  });

  test('device already connected', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01', connected: true);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(
        () => device.connect(), throwsA(isA<BlueZAlreadyConnectedException>()));
  });

  test('device disconnect', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01', connected: true);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.connected, isTrue);
    await device.disconnect();
    expect(device.connected, isFalse);
  });

  test('device disconnect not connected', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01', connected: false);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.connected, isFalse);
    expect(
        () => device.disconnect(), throwsA(isA<BlueZNotConnectedException>()));
  });

  test('device connect profile', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(a,
        address: 'DE:71:CE:00:00:01',
        uuids: ['00000001-0000-1000-8000-00805f9b34fb']);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(d.connectedProfiles.contains('00000001-0000-1000-8000-00805f9b34fb'),
        isFalse);
    await device.connectProfile(
        BlueZUUID.fromString('00000001-0000-1000-8000-00805f9b34fb'));
    expect(d.connectedProfiles.contains('00000001-0000-1000-8000-00805f9b34fb'),
        isTrue);
  });

  test('device disconnect profile', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(a,
        address: 'DE:71:CE:00:00:01',
        uuids: ['00000001-0000-1000-8000-00805f9b34fb'],
        connectedProfiles: {'00000001-0000-1000-8000-00805f9b34fb'});

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(d.connectedProfiles.contains('00000001-0000-1000-8000-00805f9b34fb'),
        isTrue);
    await device.disconnectProfile(
        BlueZUUID.fromString('00000001-0000-1000-8000-00805f9b34fb'));
    expect(d.connectedProfiles.contains('00000001-0000-1000-8000-00805f9b34fb'),
        isFalse);
  });

  test('device properties changed', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var a = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(a,
        address: 'DE:71:CE:00:00:01', connected: false, rssi: 123);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    device.propertiesChanged.listen(expectAsync1((properties) {
      expect(properties, equals(['Connected', 'RSSI']));
      expect(device.connected, isTrue);
      expect(device.rssi, equals(124));
    }));

    await d.changeProperties(connected: true, rssi: 124);
  });

  test('no gatt services', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01', servicesResolved: true);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.gattServices, isEmpty);
  });

  test('gatt services', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01', servicesResolved: true);
    await bluez.addService(d, 1, uuid: '00000001-0000-1000-8000-00805f9b34fb');
    await bluez.addService(d, 2,
        primary: true, uuid: '00000002-0000-1000-8000-00805f9b34fb');
    await bluez.addService(d, 3,
        primary: false, uuid: '00000003-0000-1000-8000-00805f9b34fb');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.gattServices, hasLength(3));
    expect(device.gattServices[0].uuid, equals(BlueZUUID.short(1)));
    expect(device.gattServices[1].uuid, equals(BlueZUUID.short(2)));
    expect(device.gattServices[1].primary, isTrue);
    expect(device.gattServices[2].uuid, equals(BlueZUUID.short(3)));
    expect(device.gattServices[2].primary, isFalse);
    expect(device.gattServices[2].characteristics, isEmpty);
  });

  test('gatt characteristics', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01', servicesResolved: true);
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    await bluez.addCharacteristic(s, 1,
        uuid: '0000000a-0000-1000-8000-00805f9b34fb');
    await bluez.addCharacteristic(s, 2,
        uuid: '0000000b-0000-1000-8000-00805f9b34fb');
    await bluez.addCharacteristic(s, 3,
        flags: [
          'broadcast',
          'read',
          'write-without-response',
          'write',
          'notify',
          'indicate',
          'authenticated-signed-writes',
          'extended-properties',
          'reliable-write',
          'writable-auxiliaries',
          'encrypt-read',
          'encrypt-write',
          'encrypt-authenticated-read',
          'encrypt-authenticated-write',
          'secure-read',
          'secure-write',
          'authorize'
        ],
        mtu: 512,
        value: [0xde, 0xad, 0xbe, 0xef],
        uuid: '0000000c-0000-1000-8000-00805f9b34fb');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(3));
    expect(service.characteristics[0].uuid, equals(BlueZUUID.short(0xa)));
    expect(service.characteristics[1].uuid, equals(BlueZUUID.short(0xb)));
    expect(service.characteristics[2].uuid, equals(BlueZUUID.short(0xc)));
    expect(service.characteristics[2].mtu, equals(512));
    expect(
        service.characteristics[2].flags,
        equals({
          BlueZGattCharacteristicFlag.broadcast,
          BlueZGattCharacteristicFlag.read,
          BlueZGattCharacteristicFlag.writeWithoutResponse,
          BlueZGattCharacteristicFlag.write,
          BlueZGattCharacteristicFlag.notify,
          BlueZGattCharacteristicFlag.indicate,
          BlueZGattCharacteristicFlag.authenticatedSignedWrites,
          BlueZGattCharacteristicFlag.extendedProperties,
          BlueZGattCharacteristicFlag.reliableWrite,
          BlueZGattCharacteristicFlag.writableAuxiliaries,
          BlueZGattCharacteristicFlag.encryptRead,
          BlueZGattCharacteristicFlag.encryptWrite,
          BlueZGattCharacteristicFlag.encryptAuthenticatedRead,
          BlueZGattCharacteristicFlag.encryptAuthenticatedWrite,
          BlueZGattCharacteristicFlag.secureRead,
          BlueZGattCharacteristicFlag.secureWrite,
          BlueZGattCharacteristicFlag.authorize
        }));
    expect(service.characteristics[2].value, equals([0xde, 0xad, 0xbe, 0xef]));
    expect(service.characteristics[2].descriptors, isEmpty);
  });

  test('gatt read value', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    await bluez.addCharacteristic(s, 1,
        uuid: '0000000c-0000-1000-8000-00805f9b34fb',
        value: [0xde, 0xad, 0xbe, 0xef]);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(1));
    var characteristic = service.characteristics[0];

    var data = await characteristic.readValue();
    expect(data, equals([0xde, 0xad, 0xbe, 0xef]));
    data = await characteristic.readValue(offset: 2);
    expect(data, equals([0xbe, 0xef]));
  });

  test('gatt write value', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    var c = await bluez.addCharacteristic(s, 1,
        uuid: '0000000c-0000-1000-8000-00805f9b34fb',
        value: [0xde, 0xad, 0xbe, 0xef]);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(1));
    var characteristic = service.characteristics[0];

    await characteristic.writeValue([0xaa]);
    expect(c.value, equals([0xaa, 0xad, 0xbe, 0xef]));
    await characteristic.writeValue([0xbb, 0xcc], offset: 1);
    expect(c.value, equals([0xaa, 0xbb, 0xcc, 0xef]));
  });

  test('gatt notify', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    var c = await bluez.addCharacteristic(s, 1,
        uuid: '0000000a-0000-1000-8000-00805f9b34fb', value: [0x12, 0x34]);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(1));
    var characteristic = service.characteristics[0];

    expect(characteristic.value, equals([0x12, 0x34]));
    expect(characteristic.notifying, isFalse);
    await characteristic.startNotify();
    expect(characteristic.notifying, isTrue);
    characteristic.propertiesChanged
        .where((properties) => properties.contains('Value'))
        .listen(expectAsync1((properties) {
      expect(characteristic.value, equals([0xf0, 0x0d]));
    }));
    await c.setValue([0xf0, 0x0d]);
    await characteristic.stopNotify();
    expect(characteristic.notifying, isFalse);
  });

  test('gatt descriptors', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01', servicesResolved: true);
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    var c = await bluez.addCharacteristic(s, 1,
        uuid: '00000002-0000-1000-8000-00805f9b34fb');
    await bluez.addDescriptor(c, 1,
        uuid: '0000000a-0000-1000-8000-00805f9b34fb');
    await bluez.addDescriptor(c, 2,
        uuid: '0000000b-0000-1000-8000-00805f9b34fb');
    var descriptor = await bluez.addDescriptor(c, 3,
        value: [0xde, 0xad, 0xbe, 0xef],
        uuid: '0000000c-0000-1000-8000-00805f9b34fb');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(1));
    var characteristic = service.characteristics[0];
    expect(characteristic.descriptors, hasLength(3));
    expect(characteristic.descriptors[0].uuid, equals(BlueZUUID.short(0xa)));
    expect(characteristic.descriptors[1].uuid, equals(BlueZUUID.short(0xb)));
    expect(characteristic.descriptors[2].uuid, equals(BlueZUUID.short(0xc)));
    expect(
        characteristic.descriptors[2].value, equals([0xde, 0xad, 0xbe, 0xef]));

    var data = await characteristic.descriptors[2].readValue();
    expect(data, equals([0xde, 0xad, 0xbe, 0xef]));
    data = await characteristic.descriptors[2].readValue(offset: 2);
    expect(data, equals([0xbe, 0xef]));

    await characteristic.descriptors[2].writeValue([0xaa]);
    expect(descriptor.value, equals([0xaa, 0xad, 0xbe, 0xef]));
    await characteristic.descriptors[2].writeValue([0xbb, 0xcc], offset: 1);
    expect(descriptor.value, equals([0xaa, 0xbb, 0xcc, 0xef]));
  });

  test('gatt acquire write', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01', servicesResolved: true);
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    var c = await bluez.addCharacteristic(s, 1,
        uuid: '00000002-0000-1000-8000-00805f9b34fb', mtu: 23);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(1));
    var characteristic = service.characteristics[0];
    var result = await characteristic.acquireWrite();
    expect(characteristic.writeAcquired, isTrue);
    expect(result.mtu, equals(23));
    result.socket.write([0x12, 0x34, 0x56]);
    expect(await c.writtenData, equals([0x12, 0x34, 0x56]));
    await result.socket.close();
  });

  test('gatt acquire notify', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    var d = await bluez.addDevice(adapter, address: 'DE:71:CE:00:00:01');
    var s = await bluez.addService(d, 1,
        uuid: '00000001-0000-1000-8000-00805f9b34fb');
    var c = await bluez.addCharacteristic(s, 1,
        uuid: '00000002-0000-1000-8000-00805f9b34fb', mtu: 23);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];
    expect(device.gattServices, hasLength(1));
    var service = device.gattServices[0];
    expect(service.characteristics, hasLength(1));
    var characteristic = service.characteristics[0];

    expect(characteristic.notifyAcquired, isFalse);
    var result = await characteristic.acquireNotify();
    expect(characteristic.notifyAcquired, isTrue);
    expect(result.mtu, equals(23));
    addTearDown(() async => await result.socket.close());
    result.socket
        .where((event) => event == RawSocketEvent.read)
        .listen(expectAsync1((event) async {
      expect(result.socket.read(), equals([0x12, 0x34, 0x56]));
    }));
    await c.setValue([0x12, 0x34, 0x56]);
  });

  test('pair - no auth', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01', authType: MockBlueZDeviceAuthType.none);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.paired, isFalse);
    await device.pair();
    expect(device.paired, isTrue);
  });

  test('pair - auth confirm', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.confirm);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();
    await client.registerAgent(agent);

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.paired, isFalse);
    await device.pair();
    expect(device.paired, isTrue);
    expect(agent.authRequested, isTrue);
  });

  test('pair - auth confirm pin code', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.confirmPinCode,
        pinCode: 'abc123');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();
    await client.registerAgent(agent);

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.paired, isFalse);
    await device.pair();
    expect(device.paired, isTrue);
    expect(agent.lastPinCode, equals('abc123'));
  });

  test('pair - auth request pin code', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.requestPinCode,
        pinCode: 'abc123');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent(pinCode: 'abc123');
    await client.registerAgent(agent);

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.paired, isFalse);
    await device.pair();
    expect(device.paired, isTrue);
    expect(agent.pinCodeRequested, isTrue);
  });

  test('pair - auth confirm passkey', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.confirmPasskey,
        passkey: 123456);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();
    await client.registerAgent(agent);

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.paired, isFalse);
    await device.pair();
    expect(device.paired, isTrue);
    expect(agent.lastPasskey, equals(123456));
  });

  test('pair - auth request passkey', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.requestPasskey,
        passkey: 123456);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent(passkey: 123456);
    await client.registerAgent(agent);

    expect(client.devices, hasLength(1));
    var device = client.devices[0];

    expect(device.paired, isFalse);
    await device.pair();
    expect(device.paired, isTrue);
    expect(agent.passkeyRequested, isTrue);
  });

  test('pair - default agent', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.confirm);
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:02',
        authType: MockBlueZDeviceAuthType.confirmPinCode,
        pinCode: 'abc123');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:03',
        authType: MockBlueZDeviceAuthType.requestPinCode,
        pinCode: 'abc123');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:04',
        authType: MockBlueZDeviceAuthType.confirmPasskey,
        passkey: 123456);
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:05',
        authType: MockBlueZDeviceAuthType.requestPasskey,
        passkey: 123456);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestEmptyAgent();
    await client.registerAgent(agent);

    // Test all pairing that requires interaction fails without an agent that doesn't implement the required methods.
    expect(() => client.devices[0].pair(),
        throwsA(isA<BlueZAuthenticationRejectedException>()));
    expect(() => client.devices[1].pair(),
        throwsA(isA<BlueZAuthenticationRejectedException>()));
    expect(() => client.devices[2].pair(),
        throwsA(isA<BlueZAuthenticationRejectedException>()));
    expect(() => client.devices[3].pair(),
        throwsA(isA<BlueZAuthenticationRejectedException>()));
    expect(() => client.devices[4].pair(),
        throwsA(isA<BlueZAuthenticationRejectedException>()));

    await client.devices[0].cancelPairing();

    await client.unregisterAgent();
  });

  test('pair - no agent', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.confirm);
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:02',
        authType: MockBlueZDeviceAuthType.confirmPinCode,
        pinCode: 'abc123');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:03',
        authType: MockBlueZDeviceAuthType.requestPinCode,
        pinCode: 'abc123');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:04',
        authType: MockBlueZDeviceAuthType.confirmPasskey,
        passkey: 123456);
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:05',
        authType: MockBlueZDeviceAuthType.requestPasskey,
        passkey: 123456);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    // Test all pairing that requires interaction fails without an agent.
    expect(() => client.devices[0].pair(),
        throwsA(isA<BlueZAgentNotAvailableException>()));
    expect(() => client.devices[1].pair(),
        throwsA(isA<BlueZAgentNotAvailableException>()));
    expect(() => client.devices[2].pair(),
        throwsA(isA<BlueZAgentNotAvailableException>()));
    expect(() => client.devices[3].pair(),
        throwsA(isA<BlueZAgentNotAvailableException>()));
    expect(() => client.devices[4].pair(),
        throwsA(isA<BlueZAgentNotAvailableException>()));
  });

  test('pair - cancel', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:01',
        authType: MockBlueZDeviceAuthType.confirm);
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:02',
        authType: MockBlueZDeviceAuthType.confirmPinCode,
        pinCode: 'abc123');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:03',
        authType: MockBlueZDeviceAuthType.requestPinCode,
        pinCode: 'abc123');
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:04',
        authType: MockBlueZDeviceAuthType.confirmPasskey,
        passkey: 123456);
    await bluez.addDevice(adapter,
        address: 'DE:71:CE:00:00:05',
        authType: MockBlueZDeviceAuthType.requestPasskey,
        passkey: 123456);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestCancelAgent();
    await client.registerAgent(agent);

    // Test all pairing methods can be canceled with the appropriate exception.

    expect(() => client.devices[0].pair(),
        throwsA(isA<BlueZAuthenticationCanceledException>()));
    await client.devices[0].cancelPairing();

    expect(() => client.devices[1].pair(),
        throwsA(isA<BlueZAuthenticationCanceledException>()));
    await client.devices[1].cancelPairing();

    expect(() => client.devices[2].pair(),
        throwsA(isA<BlueZAuthenticationCanceledException>()));
    await client.devices[2].cancelPairing();

    expect(() => client.devices[3].pair(),
        throwsA(isA<BlueZAuthenticationCanceledException>()));
    await client.devices[3].cancelPairing();

    expect(() => client.devices[4].pair(),
        throwsA(isA<BlueZAuthenticationCanceledException>()));
    await client.devices[4].cancelPairing();
  });

  test('pair - default agent', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();
    await client.registerAgent(agent);
    expect(bluez.agentIsDefault, isFalse);
    await client.requestDefaultAgent();
    expect(bluez.agentIsDefault, isTrue);
  });

  test('pair - agent capabilities', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();

    await client.registerAgent(agent,
        capability: BlueZAgentCapability.displayOnly);
    expect(bluez.agentCapability, equals('DisplayOnly'));
    await client.unregisterAgent();

    await client.registerAgent(agent,
        capability: BlueZAgentCapability.displayYesNo);
    expect(bluez.agentCapability, equals('DisplayYesNo'));
    await client.unregisterAgent();

    await client.registerAgent(agent,
        capability: BlueZAgentCapability.keyboardOnly);
    expect(bluez.agentCapability, equals('KeyboardOnly'));
    await client.unregisterAgent();

    await client.registerAgent(agent,
        capability: BlueZAgentCapability.noInputNoOutput);
    expect(bluez.agentCapability, equals('NoInputNoOutput'));
    await client.unregisterAgent();

    await client.registerAgent(agent,
        capability: BlueZAgentCapability.keyboardDisplay);
    expect(bluez.agentCapability, equals('KeyboardDisplay'));
    await client.unregisterAgent();
  });

  test('pair - agent path', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();
    await client.registerAgent(agent,
        path: DBusObjectPath('/com/example/TestAgent'));
    expect(bluez.agentPath, equals(DBusObjectPath('/com/example/TestAgent')));
  });

  test('pair - unregister agent', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var agent = TestAgent();
    expect(bluez.agentAddress, isNull);
    await client.registerAgent(agent);
    expect(bluez.agentAddress, isNotNull);
    await client.unregisterAgent();
    expect(bluez.agentAddress, isNull);
    expect(agent.released, isTrue);
  });

  test('battery', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01');

    var bus = DBusClient(clientAddress);
    var client = BlueZClient(bus: bus);
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(1));
    expect(client.devices, hasLength(1));

    var adapter = client.adapters[0];
    var device = client.devices[0];
    var bpm = adapter.batteryProviderManager;

    expect(bluez.adapters[0].batteryProviders, isEmpty);
    var provider = await bpm.registerBatteryProvider();
    expect(bluez.adapters[0].batteryProviders, hasLength(1));

    var bp = bluez.adapters[0].batteryProviders[0];
    expect(bp.batteries, isEmpty);
    var battery = await provider.addBattery(device);
    // Ensure signals handled.
    await bus.ping();
    expect(bp.batteries, hasLength(1));
    var b = bp.batteries.values.first;
    expect(b.percentage, equals(0));
    expect(b.source, equals(''));

    battery.percentage = 10;
    // Ensure signals handled.
    await bus.ping();
    expect(b.percentage, equals(10));

    await provider.removeBattery(battery);
    // Ensure signals handled.
    await bus.ping();
    expect(bp.batteries, isEmpty);

    await bpm.unregisterBatteryProvider(provider);
    expect(bluez.adapters[0].batteryProviders, isEmpty);
  });

  test('battery - percentage and source', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    addTearDown(() async => await bluez.close());

    var a = await bluez.addAdapter('hci0');
    await bluez.addDevice(a, address: 'DE:71:CE:00:00:01');

    var bus = DBusClient(clientAddress);
    var client = BlueZClient(bus: bus);
    await client.connect();
    addTearDown(() async => await client.close());

    expect(client.adapters, hasLength(1));
    expect(client.devices, hasLength(1));

    var adapter = client.adapters[0];
    var device = client.devices[0];
    var bpm = adapter.batteryProviderManager;

    expect(bluez.adapters[0].batteryProviders, isEmpty);
    var provider = await bpm.registerBatteryProvider();
    expect(bluez.adapters[0].batteryProviders, hasLength(1));

    var bp = bluez.adapters[0].batteryProviders[0];
    expect(bp.batteries, isEmpty);
    await provider.addBattery(device, percentage: 100, source: 'Dummy Battery');
    // Ensure signals handled.
    await bus.ping();
    expect(bp.batteries, hasLength(1));
    var b = bp.batteries.values.first;
    expect(b.percentage, equals(100));
    expect(b.source, equals('Dummy Battery'));
  });

  test('media player - properties', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    await bluez.addMediaPlayer(device,
        status: 'playing',
        position: 18000,
        name: 'Music',
        type: 'Audio',
        subtype: 'Podcast',
        browsable: true,
        searchable: true,
        equalizer: 'off',
        repeat: 'singletrack',
        shuffle: 'alltracks',
        scan: 'off',
        track: {
          'Title': DBusString('Highway to Hell'),
          'Artist': DBusString('AC/DC'),
          'Album': DBusString('Highway to Hell'),
          'Genre': DBusString('Rock'),
          'TrackNumber': DBusUint32(1),
          'NumberOfTracks': DBusUint32(10),
          'Duration': DBusUint32(208000),
        });

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var player = client.devices[0].mediaPlayer;
    expect(player, isNotNull);
    expect(player!.name, equals('Music'));
    expect(player.type, equals('Audio'));
    expect(player.subtype, equals('Podcast'));
    expect(player.browsable, isTrue);
    expect(player.searchable, isTrue);
    expect(player.status, equals('playing'));
    expect(player.playerStatus, equals(BlueZMediaPlayerStatus.playing));
    expect(player.position, equals(18000));
    expect(player.equalizer, equals(BlueZMediaPlayerEqualizer.off));
    expect(player.repeat, equals(BlueZMediaPlayerRepeat.singleTrack));
    expect(player.shuffle, equals(BlueZMediaPlayerShuffle.allTracks));
    expect(player.scan, equals(BlueZMediaPlayerScan.off));
    expect(player.device?.address, equals('DC:E5:5B:66:AC:96'));

    var track = player.trackInfo;
    expect(track.title, equals('Highway to Hell'));
    expect(track.artist, equals('AC/DC'));
    expect(track.album, equals('Highway to Hell'));
    expect(track.genre, equals('Rock'));
    expect(track.trackNumber, equals(1));
    expect(track.numberOfTracks, equals(10));
    expect(track.duration, equals(Duration(milliseconds: 208000)));
  });

  test('media player - a player that reports nothing', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    await bluez.addMediaPlayer(device);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    // A player with no Repeat/Shuffle/Scan properties supports none of them,
    // which is different from having them switched off.
    var player = client.devices[0].mediaPlayer!;
    expect(player.repeat, isNull);
    expect(player.shuffle, isNull);
    expect(player.scan, isNull);
    expect(player.equalizer, isNull);
    expect(player.trackInfo.title, isNull);
    expect(player.trackInfo.duration, isNull);
  });

  test('media player - a metadata field of an unexpected type is skipped',
      () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    await bluez.addMediaPlayer(device, track: {
      'Title': DBusString('Tom Sawyer'),
      // Signed rather than the unsigned AVRCP specifies. The point is that
      // this costs us TrackNumber only - it must not take Title with it.
      'TrackNumber': DBusInt32(4),
    });

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var track = client.devices[0].mediaPlayer!.trackInfo;
    expect(track.title, equals('Tom Sawyer'));
    expect(track.trackNumber, isNull);
    // Nothing is thrown away: the raw value is still there to be inspected.
    expect(track.properties['TrackNumber'], equals(DBusInt32(4)));
  });

  test('media player - no player object', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    // A connected device that has not started playing has no MediaPlayer1
    // object. That is ordinary, and used to throw.
    expect(client.devices[0].mediaPlayer, isNull);
  });

  test('media player - transport methods', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    var mock = await bluez.addMediaPlayer(device);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var player = client.devices[0].mediaPlayer!;
    await player.play();
    await player.pause();
    await player.stop();
    await player.next();
    await player.previous();
    await player.fastForward();
    await player.rewind();
    await player.press(0x44);
    await player.hold(0x44);
    await player.release();

    expect(
        mock.calls,
        equals([
          'Play',
          'Pause',
          'Stop',
          'Next',
          'Previous',
          'FastForward',
          'Rewind',
          'Press:68',
          'Hold:68',
          'Release',
        ]));
  });

  test('media player - settings are writable', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    var mock = await bluez.addMediaPlayer(device,
        equalizer: 'off', repeat: 'off', shuffle: 'off', scan: 'off');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var bus = DBusClient(clientAddress);
    addTearDown(() async => await bus.close());

    var player = client.devices[0].mediaPlayer!;
    await player.setEqualizer(BlueZMediaPlayerEqualizer.on);
    await player.setRepeat(BlueZMediaPlayerRepeat.allTracks);
    await player.setShuffle(BlueZMediaPlayerShuffle.group);
    await player.setScan(BlueZMediaPlayerScan.allTracks);

    expect(mock.equalizer, equals('on'));
    expect(mock.repeat, equals('alltracks'));
    expect(mock.shuffle, equals('group'));
    expect(mock.scan, equals('alltracks'));

    // Ensure signals handled, then the client's own cache agrees.
    await bus.ping();
    expect(player.equalizer, equals(BlueZMediaPlayerEqualizer.on));
    expect(player.repeat, equals(BlueZMediaPlayerRepeat.allTracks));
    expect(player.shuffle, equals(BlueZMediaPlayerShuffle.group));
    expect(player.scan, equals(BlueZMediaPlayerScan.allTracks));
  });

  test('media player - readPosition bypasses the property cache', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    // BlueZ signals Position only on a seek but computes it on read, so the
    // cache and the daemon legitimately disagree while a track is playing.
    await bluez.addMediaPlayer(device,
        status: 'playing', position: 18000, livePosition: 41000);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var player = client.devices[0].mediaPlayer!;
    expect(player.position, equals(18000));
    expect(await player.readPosition(), equals(41000));
  });

  test('media player - status changes reach a listener', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    var mock = await bluez.addMediaPlayer(device, status: 'paused');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var player = client.devices[0].mediaPlayer!;
    var changes = player.propertiesChanged.take(1).toList();
    await mock.change({'Status': DBusString('playing')});
    expect(
        await changes,
        equals([
          ['Status']
        ]));
    expect(player.playerStatus, equals(BlueZMediaPlayerStatus.playing));
  });

  test('media player - a subscription survives a re-announced interface',
      () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    var mock = await bluez.addMediaPlayer(device, status: 'paused');

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());
    var bus = DBusClient(clientAddress);
    addTearDown(() async => await bus.close());

    var player = client.devices[0].mediaPlayer!;
    var seen = <List<String>>[];
    var subscription = player.propertiesChanged.listen(seen.add);
    addTearDown(subscription.cancel);

    // BlueZ re-announces InterfacesAdded for a path it has already published
    // when a player comes back after an AVRCP reconnect. That used to replace
    // the interface and silently orphan every listener.
    await bluez.emitSignal(
        path: DBusObjectPath('/'),
        interface: 'org.freedesktop.DBus.ObjectManager',
        name: 'InterfacesAdded',
        values: [
          mock.path,
          DBusDict(DBusSignature('s'), DBusSignature('a{sv}'), {
            DBusString('org.bluez.MediaPlayer1'):
                DBusDict.stringVariant({'Status': DBusString('stopped')})
          })
        ]);
    await bus.ping();

    await mock.change({'Status': DBusString('playing')});
    await bus.ping();

    expect(
        seen,
        equals([
          ['Status']
        ]));
    expect(player.playerStatus, equals(BlueZMediaPlayerStatus.playing));
  });

  test('media transport - codec and volume', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    // Codec 0x02 is MPEG-2,4 AAC.
    var mock = await bluez.addMediaTransport(device,
        codec: 0x02,
        configuration: [0x80, 0x01, 0x04],
        state: 'active',
        delay: 1500,
        volume: 96);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    var transports = client.devices[0].mediaTransports;
    expect(transports, hasLength(1));
    var transport = transports[0];
    expect(transport.codec, equals(0x02));
    expect(transport.configuration, equals([0x80, 0x01, 0x04]));
    expect(transport.state, equals(BlueZMediaTransportState.active));
    expect(transport.delay, equals(1500));
    expect(transport.volume, equals(96));
    expect(transport.device?.address, equals('DC:E5:5B:66:AC:96'));
    expect(transport.uuid,
        equals(BlueZUUID.fromString('0000110a-0000-1000-8000-00805f9b34fb')));

    await transport.setVolume(40);
    expect(mock.volume, equals(40));
  });

  test('media transport - a remote end with no absolute volume', () async {
    var server = DBusServer();
    var clientAddress =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    addTearDown(() async => await server.close());

    var bluez = MockBlueZServer(clientAddress);
    await bluez.start();
    var adapter = await bluez.addAdapter('hci0');
    var device = await bluez.addDevice(adapter,
        address: 'DC:E5:5B:66:AC:96', connected: true);
    await bluez.addMediaTransport(device);

    var client = BlueZClient(bus: DBusClient(clientAddress));
    await client.connect();
    addTearDown(() async => await client.close());

    // Absent, not zero: a device that does not support AVRCP volume must not
    // look like one turned all the way down.
    var transport = client.devices[0].mediaTransports[0];
    expect(transport.volume, isNull);
    expect(transport.delay, isNull);
    expect(transport.state, equals(BlueZMediaTransportState.idle));
  });
}

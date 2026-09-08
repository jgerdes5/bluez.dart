import 'dart:async';

import 'package:bluez/src/bluez_agent.dart';
import 'package:bluez/src/bluez_client.dart';
import 'package:bluez/src/bluez_device.dart';
import 'package:bluez/src/bluez_uuid.dart';
import 'package:dbus/dbus.dart';

class BlueZAgentObject extends DBusObject {
  final BlueZClient bluezClient;
  final BlueZAgent agent;

  BlueZAgentObject(this.bluezClient, this.agent, DBusObjectPath path)
      : super(path);

  /// Runs [handle] with the device a call is about.
  ///
  /// Every handler below used to assert the device was already cached, with
  /// `!`. It is not always: `InterfacesAdded` is delivered asynchronously
  /// while an `Agent1` call is dispatched synchronously from the same socket
  /// read, so for a device bluetoothd has only just discovered - which is what
  /// an inbound pairing looks like - the cache can still be empty. The `!` then
  /// threw, and because package:dbus writes the reply only after the handler's
  /// future completes, bluetoothd was left waiting for a reply that never came:
  /// pairing failed with nothing on screen and nothing in the log.
  ///
  /// The cached case stays **synchronous** on purpose. [handle] must be invoked
  /// during dispatch, before any suspension, because an agent may hold the
  /// response open until `Cancel` arrives - and if the call that sets that up
  /// were deferred by even a microtask, a `Cancel` racing it would find nothing
  /// to cancel and both sides would wait for ever.
  Future<DBusMethodResponse> _withDevice(DBusValue path,
      FutureOr<DBusMethodResponse> Function(BlueZDevice device) handle) {
    var objectPath = path.asObjectPath();
    var known = bluezClient.getDevice(objectPath);
    if (known != null) {
      return Future.value(handle(known));
    }
    return bluezClient
        .awaitDevice(objectPath)
        .then((device) => device == null ? _noDevice : handle(device));
  }

  /// The answer when the device cannot be resolved at all.
  ///
  /// An error rather than a rejection, because the truth is that we do not know
  /// what is being asked about. `Canceled` is what BlueZ's own agents answer
  /// when they cannot decide.
  static DBusMethodResponse get _noDevice => DBusMethodErrorResponse(
      'org.bluez.Error.Canceled', [DBusString('unknown device')]);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    // Nothing below may throw. A handler that does never sends a reply -
    // `_processMethodCall` in package:dbus is fire-and-forget with no error
    // handling - and bluetoothd waits for that reply for ever.
    try {
      return await _handle(methodCall);
    } catch (e) {
      return DBusMethodErrorResponse(
          'org.bluez.Error.Canceled', [DBusString('$e')]);
    }
  }

  Future<DBusMethodResponse> _handle(DBusMethodCall methodCall) async {
    if (methodCall.interface != 'org.bluez.Agent1') {
      return DBusMethodErrorResponse.unknownInterface();
    }

    if (methodCall.name == 'Release') {
      if (methodCall.signature != DBusSignature('')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      await agent.release();
      return DBusMethodSuccessResponse();
    } else if (methodCall.name == 'RequestPinCode') {
      if (methodCall.signature != DBusSignature('o')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(methodCall.values[0],
          (device) async => (await agent.requestPinCode(device)).response);
    } else if (methodCall.name == 'DisplayPinCode') {
      if (methodCall.signature != DBusSignature('os')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(
          methodCall.values[0],
          (device) async => (await agent.displayPinCode(
                  device, methodCall.values[1].asString()))
              .response);
    } else if (methodCall.name == 'RequestPasskey') {
      if (methodCall.signature != DBusSignature('o')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(methodCall.values[0],
          (device) async => (await agent.requestPasskey(device)).response);
    } else if (methodCall.name == 'DisplayPasskey') {
      if (methodCall.signature != DBusSignature('ouq')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(methodCall.values[0], (device) async {
        await agent.displayPasskey(device, methodCall.values[1].asUint32(),
            methodCall.values[2].asUint16());
        return DBusMethodSuccessResponse();
      });
    } else if (methodCall.name == 'RequestConfirmation') {
      if (methodCall.signature != DBusSignature('ou')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(
          methodCall.values[0],
          (device) async => (await agent.requestConfirmation(
                  device, methodCall.values[1].asUint32()))
              .response);
    } else if (methodCall.name == 'RequestAuthorization') {
      if (methodCall.signature != DBusSignature('o')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(
          methodCall.values[0],
          (device) async =>
              (await agent.requestAuthorization(device)).response);
    } else if (methodCall.name == 'AuthorizeService') {
      if (methodCall.signature != DBusSignature('os')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      return _withDevice(
          methodCall.values[0],
          (device) async => (await agent.authorizeService(device,
                  BlueZUUID.fromString(methodCall.values[1].asString())))
              .response);
    } else if (methodCall.name == 'Cancel') {
      if (methodCall.signature != DBusSignature('')) {
        return DBusMethodErrorResponse.invalidArgs();
      }
      await agent.cancel();
      return DBusMethodSuccessResponse();
    } else {
      return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

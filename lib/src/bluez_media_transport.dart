import 'dart:io';

import 'package:bluez/src/bluez_client.dart';
import 'package:bluez/src/bluez_device.dart';
import 'package:bluez/src/bluez_enums.dart';
import 'package:bluez/src/bluez_object.dart';
import 'package:bluez/src/bluez_uuid.dart';
import 'package:dbus/dbus.dart';

/// An A2DP audio stream to or from a device.
///
/// This is the object that knows which codec was actually negotiated and
/// carries AVRCP absolute volume. BlueZMediaControl's volumeUp/volumeDown
/// are the older relative controls and cannot report a level.
class BlueZMediaTransport {
  final String _transportInterfaceName = 'org.bluez.MediaTransport1';

  final BlueZClient _client;
  final BlueZObject _object;

  BlueZMediaTransport(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged {
    var interface = _object.interfaces[_transportInterfaceName];
    if (interface == null) {
      throw 'BlueZ object missing $_transportInterfaceName interface';
    }
    return interface.propertiesChangedStreamController.stream;
  }

  /// The device this stream belongs to.
  BlueZDevice? get device {
    var path = _object.getObjectPathProperty(_transportInterfaceName, 'Device');
    return path == null ? null : _client.getDevice(path);
  }

  /// The profile UUID this stream serves, e.g. A2DP Source or Sink.
  BlueZUUID get uuid => BlueZUUID.fromString(
      _object.getStringProperty(_transportInterfaceName, 'UUID') ?? '');

  /// The negotiated A2DP codec: 0x00 SBC, 0x01 MPEG-1,2 Audio, 0x02
  /// MPEG-2,4 AAC, 0x04 ATRAC, 0xff vendor-specific (aptX, LDAC,
  /// FastStream and the rest).
  int get codec =>
      _object.getByteProperty(_transportInterfaceName, 'Codec') ?? 0;

  /// The codec-specific configuration blob, as negotiated.
  List<int> get configuration =>
      _object.getByteArrayProperty(_transportInterfaceName, 'Configuration') ??
      const [];

  /// The state of this stream.
  BlueZMediaTransportState get state =>
      _stateValues[
          _object.getStringProperty(_transportInterfaceName, 'State') ?? ''] ??
      BlueZMediaTransportState.idle;

  /// Transport delay in units of 0.1 ms, or null if the remote end does not
  /// support delay reporting.
  int? get delay => _object.getUint16Property(_transportInterfaceName, 'Delay');

  /// AVRCP absolute volume, 0-127, or null if the remote end does not support
  /// it.
  int? get volume =>
      _object.getUint16Property(_transportInterfaceName, 'Volume');

  /// Sets AVRCP absolute volume, 0-127.
  Future<void> setVolume(int value) async {
    assert(value >= 0 && value <= 127);
    await _object.setProperty(
        _transportInterfaceName, 'Volume', DBusUint16(value));
  }

  /// Path of the local endpoint this stream was configured against.
  DBusObjectPath? get endpoint =>
      _object.getObjectPathProperty(_transportInterfaceName, 'Endpoint');

  /// Acquires the transport file descriptor, returning it with the read and
  /// write MTUs.
  Future<BlueZMediaTransportFd> acquire() async {
    var result = await _object.callMethod(
        _transportInterfaceName, 'Acquire', [],
        replySignature: DBusSignature('hqq'));
    return BlueZMediaTransportFd(result.returnValues[0].asUnixFd(),
        result.returnValues[1].asUint16(), result.returnValues[2].asUint16());
  }

  /// Acquires the transport file descriptor only if the transport is already
  /// active, rather than waiting for it to become so.
  Future<BlueZMediaTransportFd> tryAcquire() async {
    var result = await _object.callMethod(
        _transportInterfaceName, 'TryAcquire', [],
        replySignature: DBusSignature('hqq'));
    return BlueZMediaTransportFd(result.returnValues[0].asUnixFd(),
        result.returnValues[1].asUint16(), result.returnValues[2].asUint16());
  }

  /// Releases a file descriptor previously acquired.
  Future<void> release() async {
    await _object.callMethod(_transportInterfaceName, 'Release', [],
        replySignature: DBusSignature(''));
  }

  // The strings BlueZ publishes for State.
  static const _stateValues = <String, BlueZMediaTransportState>{
    'idle': BlueZMediaTransportState.idle,
    'pending': BlueZMediaTransportState.pending,
    'active': BlueZMediaTransportState.active,
    'broadcasting': BlueZMediaTransportState.broadcasting,
  };
}

/// The file descriptor and MTUs returned by [BlueZMediaTransport.acquire].
class BlueZMediaTransportFd {
  /// The socket carrying the audio stream.
  final ResourceHandle handle;

  /// Maximum bytes that can be read from [handle] at once.
  final int readMtu;

  /// Maximum bytes that can be written to [handle] at once.
  final int writeMtu;

  BlueZMediaTransportFd(this.handle, this.readMtu, this.writeMtu);

  @override
  String toString() =>
      'BlueZMediaTransportFd(readMtu: $readMtu, writeMtu: $writeMtu)';
}

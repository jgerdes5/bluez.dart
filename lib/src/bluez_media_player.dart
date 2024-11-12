import 'package:dbus/dbus.dart';

import 'package:bluez/bluez.dart';
import 'package:bluez/src/bluez_object.dart';

/// Bluetooth Media Player
class BlueZMediaPlayer {
  final String _deviceInterfaceName = 'org.bluez.MediaPlayer1';

  final BlueZObject _object;
  final BlueZClient _client;

  BlueZMediaPlayer(this._client, this._object);

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged {
    var interface = _object.interfaces[_deviceInterfaceName];
    if (interface == null) {
      throw 'BlueZ device missing $_deviceInterfaceName interface';
    }
    return interface.propertiesChangedStreamController.stream;
  }

  /// Play
  Future<void> play() async {
    await _object.callMethod(_deviceInterfaceName, 'Play', [],
        replySignature: DBusSignature(''));
  }

  /// Pause
  Future<void> pause() async {
    await _object.callMethod(_deviceInterfaceName, 'Pause', [],
        replySignature: DBusSignature(''));
  }

  /// Stop
  Future<void> stop() async {
    await _object.callMethod(_deviceInterfaceName, 'Stop', [],
        replySignature: DBusSignature(''));
  }

  /// Next
  Future<void> next() async {
    await _object.callMethod(_deviceInterfaceName, 'Next', [],
        replySignature: DBusSignature(''));
  }

  /// Previous
  Future<void> previous() async {
    await _object.callMethod(_deviceInterfaceName, 'Previous', [],
        replySignature: DBusSignature(''));
  }

  /// Get the current status of the media player
  String get status  => _object.getStringProperty(_deviceInterfaceName, 'Status') ?? 'error';

  /// Get position in current Track
  int get position => _object.getUint32Property(_deviceInterfaceName, 'Position') ?? 0;

  /// Get current track information
  Map<String, Object> get track {
    var value = _object.getCachedProperty(_deviceInterfaceName, 'Track') ??
        DBusDict(DBusSignature('s'), DBusSignature('v'), {});
    if (value.signature != DBusSignature('a{sv}')) {
      return {};
    }
    Object processValue(DBusValue value) {
      if (value.signature == DBusSignature('s')) {
        return value.asString();
      } else if (value.signature == DBusSignature('u')) {
        return value.asUint32();
      }
      return '';
    }
    return value.asDict().map((key, value) => MapEntry(key.asString(), processValue(value.asVariant())));
  }
}

import 'package:dbus/dbus.dart';

import 'package:bluez/src/bluez_object.dart';

class BlueZMediaControl {
  final String _deviceInterfaceName = 'org.bluez.MediaControl1';

  final BlueZObject _object;

  BlueZMediaControl(this._object);

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

  /// VolumeUp
  Future<void> volumeUp() async {
    await _object.callMethod(_deviceInterfaceName, 'VolumeUp', [],
        replySignature: DBusSignature(''));
  }

  /// VolumeDown
  Future<void> volumeDown() async {
    await _object.callMethod(_deviceInterfaceName, 'VolumeDown', [],
        replySignature: DBusSignature(''));
  }

  /// True if the media player is connected
  bool get connected =>
      _object.getBooleanProperty(_deviceInterfaceName, 'Connected') ?? false;

  /// The player object path this deprecated interface reports, if any.
  ///
  /// Nullable, and no longer guessed. It used to fall back to
  /// `<device>/player0`, which is a path that may well not exist: BlueZ
  /// increments the number across AVRCP reconnects, so after one the guess
  /// points at a dead object for ever. Use [BlueZDevice.mediaPlayer], which
  /// finds the player by interface.
  DBusObjectPath? get player =>
      _object.getObjectPathProperty(_deviceInterfaceName, 'Player');
}

import 'package:bluez/src/bluez_client.dart';
import 'package:bluez/src/bluez_device.dart';
import 'package:bluez/src/bluez_enums.dart';
import 'package:bluez/src/bluez_object.dart';
import 'package:dbus/dbus.dart';

/// Metadata for the track a [BlueZMediaPlayer] is playing.
///
/// Typed rather than the raw `a{sv}`, because AVRCP metadata arrives as a
/// mixture of strings and uint32s and every caller was otherwise obliged to
/// repeat the same casts. A field whose value is absent or of an unexpected
/// signature is null; it does not spoil its neighbours.
class BlueZMediaPlayerTrack {
  /// Title of the track.
  final String? title;

  /// Track artist.
  final String? artist;

  /// Album the track is from.
  final String? album;

  /// Genre of the track.
  final String? genre;

  /// Position of this track within [numberOfTracks], counting from one.
  final int? trackNumber;

  /// Number of tracks in the album or playlist.
  final int? numberOfTracks;

  /// Length of the track, or null if the player does not report it. Many
  /// phones publish it only with a second metadata update, or never.
  final Duration? duration;

  /// Every property as received, including any this class does not model.
  final Map<String, DBusValue> properties;

  BlueZMediaPlayerTrack({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.trackNumber,
    this.numberOfTracks,
    this.duration,
    this.properties = const {},
  });

  factory BlueZMediaPlayerTrack.fromProperties(
      Map<String, DBusValue> properties) {
    String? string(String name) {
      var value = properties[name];
      return value != null && value.signature == DBusSignature('s')
          ? value.asString()
          : null;
    }

    int? uint32(String name) {
      var value = properties[name];
      return value != null && value.signature == DBusSignature('u')
          ? value.asUint32()
          : null;
    }

    var durationMs = uint32('Duration');

    return BlueZMediaPlayerTrack(
      title: string('Title'),
      artist: string('Artist'),
      album: string('Album'),
      genre: string('Genre'),
      trackNumber: uint32('TrackNumber'),
      numberOfTracks: uint32('NumberOfTracks'),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      properties: properties,
    );
  }

  @override
  String toString() =>
      'BlueZMediaPlayerTrack(title: \$title, artist: \$artist, album: \$album, genre: \$genre, trackNumber: \$trackNumber, numberOfTracks: \$numberOfTracks, duration: \$duration)';
}

/// Bluetooth Media Player
class BlueZMediaPlayer {
  final String _mediaPlayerInterfaceName = 'org.bluez.MediaPlayer1';

  final BlueZObject _object;
  final BlueZClient _client;

  BlueZMediaPlayer(this._client, this._object);

  /// The player's own object path.
  ///
  /// Exposed so a client can tell one player object from another - BlueZ
  /// increments the number across AVRCP reconnects, and a subscription to the
  /// old object goes quiet rather than failing.
  DBusObjectPath get path => _object.path;

  /// Stream of property names as their values change.
  Stream<List<String>> get propertiesChanged {
    var interface = _object.interfaces[_mediaPlayerInterfaceName];
    if (interface == null) {
      throw 'BlueZ device missing $_mediaPlayerInterfaceName interface';
    }
    return interface.propertiesChangedStreamController.stream;
  }

  /// Play
  Future<void> play() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Play', [],
        replySignature: DBusSignature(''));
  }

  /// Pause
  Future<void> pause() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Pause', [],
        replySignature: DBusSignature(''));
  }

  /// Stop
  Future<void> stop() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Stop', [],
        replySignature: DBusSignature(''));
  }

  /// Next
  Future<void> next() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Next', [],
        replySignature: DBusSignature(''));
  }

  /// Previous
  Future<void> previous() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Previous', [],
        replySignature: DBusSignature(''));
  }

  /// FastForward
  Future<void> fastForward() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'FastForward', [],
        replySignature: DBusSignature(''));
  }

  /// Rewind
  Future<void> rewind() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Rewind', [],
        replySignature: DBusSignature(''));
  }

  /// Presses the AV/C operation [avcKey], as defined in the AV/C panel
  /// subunit specification.
  ///
  /// Paired with [hold] and [release] this is what a physical transport
  /// button wants: hold to seek, release to stop, rather than repeating
  /// [next].
  Future<void> press(int avcKey) async {
    await _object.callMethod(
        _mediaPlayerInterfaceName, 'Press', [DBusByte(avcKey)],
        replySignature: DBusSignature(''));
  }

  /// Holds the AV/C operation [avcKey] until [release] is called.
  Future<void> hold(int avcKey) async {
    await _object.callMethod(
        _mediaPlayerInterfaceName, 'Hold', [DBusByte(avcKey)],
        replySignature: DBusSignature(''));
  }

  /// Releases the operation started with [press] or [hold].
  Future<void> release() async {
    await _object.callMethod(_mediaPlayerInterfaceName, 'Release', [],
        replySignature: DBusSignature(''));
  }

  /// Name of the player as reported by the remote device.
  String get name =>
      _object.getStringProperty(_mediaPlayerInterfaceName, 'Name') ?? '';

  /// Player type, e.g. 'Audio', 'Video', 'Audio Broadcasting'.
  String get type =>
      _object.getStringProperty(_mediaPlayerInterfaceName, 'Type') ?? '';

  /// Player subtype, e.g. 'Audio Book', 'Podcast'.
  String get subtype =>
      _object.getStringProperty(_mediaPlayerInterfaceName, 'Subtype') ?? '';

  /// True if the player supports browsing its library.
  bool get browsable =>
      _object.getBooleanProperty(_mediaPlayerInterfaceName, 'Browsable') ??
      false;

  /// True if the player supports searching.
  bool get searchable =>
      _object.getBooleanProperty(_mediaPlayerInterfaceName, 'Searchable') ??
      false;

  /// The device this player belongs to.
  BlueZDevice? get device {
    var path =
        _object.getObjectPathProperty(_mediaPlayerInterfaceName, 'Device');
    return path == null ? null : _client.getDevice(path);
  }

  /// Path of the playlist object, if the player exposes one.
  DBusObjectPath? get playlist =>
      _object.getObjectPathProperty(_mediaPlayerInterfaceName, 'Playlist');

  /// Get the current status of the media player, as the string BlueZ reports.
  ///
  /// Prefer [playerStatus], which is typed. This is kept because it is the
  /// original accessor and callers already switch on the strings.
  String get status =>
      _object.getStringProperty(_mediaPlayerInterfaceName, 'Status') ?? 'error';

  /// The current status of the media player.
  BlueZMediaPlayerStatus get playerStatus =>
      _statusValues[status] ?? BlueZMediaPlayerStatus.error;

  /// Position in the current track, in milliseconds.
  ///
  /// This reads the property cache, which BlueZ refreshes only on a seek: it
  /// notifies PLAYBACK_POS_CHANGED at the longest interval AVRCP allows and
  /// deliberately re-anchors its own position without emitting it, so after a
  /// play or pause this value is stale. Use [readPosition] when the answer has
  /// to be current.
  int get position =>
      _object.getUint32Property(_mediaPlayerInterfaceName, 'Position') ?? 0;

  /// Reads the position in the current track from the daemon rather than from
  /// the property cache.
  ///
  /// BlueZ computes this property on read, adding the time elapsed since it
  /// last anchored the position, so the value is current and the call does not
  /// go over the air. 0xffffffff means the player does not report a position.
  Future<int> readPosition() async {
    var value = await _object.getProperty(_mediaPlayerInterfaceName, 'Position',
        signature: DBusSignature('u'));
    return value.asUint32();
  }

  /// Whether the player's equalizer is engaged.
  BlueZMediaPlayerEqualizer? get equalizer =>
      _equalizerValues[_setting('Equalizer')];

  /// Engages or disengages the player's equalizer.
  Future<void> setEqualizer(BlueZMediaPlayerEqualizer value) =>
      _setSetting('Equalizer', _equalizerNames[value]!);

  /// The player's repeat mode, or null if it does not support one.
  BlueZMediaPlayerRepeat? get repeat => _repeatValues[_setting('Repeat')];

  /// Sets the player's repeat mode.
  Future<void> setRepeat(BlueZMediaPlayerRepeat value) =>
      _setSetting('Repeat', _repeatNames[value]!);

  /// The player's shuffle mode, or null if it does not support one.
  BlueZMediaPlayerShuffle? get shuffle => _shuffleValues[_setting('Shuffle')];

  /// Sets the player's shuffle mode.
  Future<void> setShuffle(BlueZMediaPlayerShuffle value) =>
      _setSetting('Shuffle', _shuffleNames[value]!);

  /// The player's scan mode, or null if it does not support one.
  BlueZMediaPlayerScan? get scan => _scanValues[_setting('Scan')];

  /// Sets the player's scan mode.
  Future<void> setScan(BlueZMediaPlayerScan value) =>
      _setSetting('Scan', _scanNames[value]!);

  /// Metadata for the track being played.
  BlueZMediaPlayerTrack get trackInfo =>
      BlueZMediaPlayerTrack.fromProperties(_trackProperties);

  /// Get current track information.
  ///
  /// Prefer [trackInfo], which is typed and does not lose values whose
  /// signature it did not expect. Retained because it is the original
  /// accessor; string and uint32 properties come through as `String` and
  /// `int`, anything else as its [DBusValue].
  Map<String, Object> get track => _trackProperties.map((key, value) {
        if (value.signature == DBusSignature('s')) {
          return MapEntry(key, value.asString());
        }
        if (value.signature == DBusSignature('u')) {
          return MapEntry(key, value.asUint32());
        }
        return MapEntry(key, value);
      });

  Map<String, DBusValue> get _trackProperties {
    var value = _object.getCachedProperty(_mediaPlayerInterfaceName, 'Track') ??
        DBusDict(DBusSignature('s'), DBusSignature('v'), {});
    if (value.signature != DBusSignature('a{sv}')) {
      return {};
    }
    return value
        .asDict()
        .map((key, value) => MapEntry(key.asString(), value.asVariant()));
  }

  String? _setting(String name) =>
      _object.getStringProperty(_mediaPlayerInterfaceName, name);

  Future<void> _setSetting(String name, String value) =>
      _object.setProperty(_mediaPlayerInterfaceName, name, DBusString(value));

  // BlueZ spells these settings out as strings on the bus; the names are the
  // ones avrcp.c parses, so they are not free to be prettier.
  static const _statusValues = <String, BlueZMediaPlayerStatus>{
    'playing': BlueZMediaPlayerStatus.playing,
    'stopped': BlueZMediaPlayerStatus.stopped,
    'paused': BlueZMediaPlayerStatus.paused,
    'forward-seek': BlueZMediaPlayerStatus.forwardSeek,
    'reverse-seek': BlueZMediaPlayerStatus.reverseSeek,
    'error': BlueZMediaPlayerStatus.error,
  };

  static const _equalizerNames = <BlueZMediaPlayerEqualizer, String>{
    BlueZMediaPlayerEqualizer.off: 'off',
    BlueZMediaPlayerEqualizer.on: 'on',
  };
  static const _equalizerValues = <String, BlueZMediaPlayerEqualizer>{
    'off': BlueZMediaPlayerEqualizer.off,
    'on': BlueZMediaPlayerEqualizer.on,
  };

  static const _repeatNames = <BlueZMediaPlayerRepeat, String>{
    BlueZMediaPlayerRepeat.off: 'off',
    BlueZMediaPlayerRepeat.singleTrack: 'singletrack',
    BlueZMediaPlayerRepeat.allTracks: 'alltracks',
    BlueZMediaPlayerRepeat.group: 'group',
  };
  static const _repeatValues = <String, BlueZMediaPlayerRepeat>{
    'off': BlueZMediaPlayerRepeat.off,
    'singletrack': BlueZMediaPlayerRepeat.singleTrack,
    'alltracks': BlueZMediaPlayerRepeat.allTracks,
    'group': BlueZMediaPlayerRepeat.group,
  };

  static const _shuffleNames = <BlueZMediaPlayerShuffle, String>{
    BlueZMediaPlayerShuffle.off: 'off',
    BlueZMediaPlayerShuffle.allTracks: 'alltracks',
    BlueZMediaPlayerShuffle.group: 'group',
  };
  static const _shuffleValues = <String, BlueZMediaPlayerShuffle>{
    'off': BlueZMediaPlayerShuffle.off,
    'alltracks': BlueZMediaPlayerShuffle.allTracks,
    'group': BlueZMediaPlayerShuffle.group,
  };

  static const _scanNames = <BlueZMediaPlayerScan, String>{
    BlueZMediaPlayerScan.off: 'off',
    BlueZMediaPlayerScan.allTracks: 'alltracks',
    BlueZMediaPlayerScan.group: 'group',
  };
  static const _scanValues = <String, BlueZMediaPlayerScan>{
    'off': BlueZMediaPlayerScan.off,
    'alltracks': BlueZMediaPlayerScan.allTracks,
    'group': BlueZMediaPlayerScan.group,
  };
}

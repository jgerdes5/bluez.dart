# Changelog

## 0.8.2+headunit.2

* Add `BlueZMediaTransport.path`, matching `BlueZDevice.path`. A caller holding
  a subscription needs to know when the object underneath it has been
  replaced, and `Endpoint` is no substitute: BlueZ marks it experimental, so
  it is usually absent and every transport would compare equal.

## 0.8.2+headunit.1

Fork release. Upstream 0.8.2 plus:

* Complete `org.bluez.MediaPlayer1`: Name, Type, Subtype, Device, Playlist,
  Browsable, Searchable, the writable Equalizer/Repeat/Shuffle/Scan settings
  with typed enums, and FastForward/Rewind/Press/Hold/Release.
* Add `BlueZMediaPlayer.readPosition()`, which reads Position from the daemon
  rather than the property cache. BlueZ signals it only on a seek, so the
  cached value is stale after a play or pause.
* Add `BlueZMediaPlayerTrack` and `BlueZMediaPlayer.trackInfo`, replacing the
  untyped metadata map. Fields are parsed independently, so a value of an
  unexpected signature no longer discards the whole track.
* Add `org.bluez.MediaTransport1` as `BlueZMediaTransport`, with the
  negotiated codec and AVRCP absolute volume, plus
  `BlueZDevice.mediaTransports`.
* Fix `BlueZObject.updateInterfaces` discarding an interface's
  propertiesChanged stream controller when BlueZ re-announces a path it has
  already published, which silently killed every existing listener.
* `BlueZDevice.mediaPlayer` returns null instead of null-asserting when the
  device has exported no player.

## 0.8.2

* Add BlueZGattCharacteristic.mtu.

## 0.8.1

* Update to dbus 0.7.8

## 0.8.0

* Bump version so we can maintain a 0.7 series that has lesser Dart requirement.

## 0.7.8

* Add BlueZGattCharacteristic notification support.
* Add BlueZGattCharacteristic.acquireWrite.
* Add BlueZClient.registerAgent etc that enables devices to be paired.

## 0.7.6

* Update to dbus 0.7

## 0.7.5

* Only list as supporting Linux.
* Fix BlueZUUID hashCode.
* Make BlueZDevice.adapter non-nullable.

## 0.7.4

* Detect BlueZ D-Bus exceptions and provide classes for them.

## 0.7.3

* Report all initial adapters and devices on connect.
* Document where the values of BlueZDevice.appearance are defined.
* Add an example of how to monitor for events.
* Add tests for adapter/device property changes.

## 0.7.2

* Update to dbus 0.6.

## 0.7.1

* Fix detection of removed adapters/devices when they re-appear.
* Update README about supported platforms.

## 0.7.0

* Fix BlueZAdapter.stopDiscovery not working.
* Refactor BlueZAdapter.setDiscoveryFilter.

## 0.6.0

* Reliably detect when an object is removed.
* Update to dbus 0.5.
* Rename test file so can just run 'dart test'.

## 0.5.0

* Replace setters with methods so they can be async.

## 0.4.0

* Update to dbus 0.4.
* Change names of signal streams to match dbus.dart conventions.
* Refactor BlueZUUID.
* Change outputs from Iterable to List so can be easily indexed.
* Drop GATT prefix on variables inside GATT objects.
* Fix properties being removed when a D-Bus object is removed.
* Add regression tests.

## 0.1.4

* Bump dbus dependency to avoid another signal subscription bug.

## 0.1.3

* Bump dbus dependency to avoid a signal subscription bug.

## 0.1.2

* Make the DBusClient parameter optional.
* Add back default example for pub.dev to show.
* Fix examples not correctly closing the BlueZClient.
* Code tidy ups to pass dart analyze in 1.12 final release.

## 0.1.1

* Add initial GATT client support.
* Improve examples.

## 0.1.0

* Initial release

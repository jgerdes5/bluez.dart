# Changelog

## 0.8.2+headunit.5

* **`mediaTransportAdded` / `mediaTransportRemoved`**, the other half of what
  the player streams answer. A transport lives on its own object path below the
  device, so its arrival was neither an adapter nor a device event and was
  absorbed silently - and a phone call tears the A2DP stream down and
  reconfigures it, so a client holding the transport for absolute volume was
  never told the new one existed. After a call, the volume echo was dead.

## 0.8.2+headunit.4

* **A restart of `org.bluez` is no longer absorbed silently.** Everything is
  re-announced on paths already in the cache, so `InterfacesAdded` took the
  update path and notified nobody, and devices the new daemon had never heard
  of were never removed - leaving the client reporting the state from before
  the restart until some unrelated property changed on each object. The client
  now watches `NameOwnerChanged` for the name, announces the removals, closes
  the property streams and reads the world again.
* **`BlueZMediaTransport.uuid` is nullable** instead of throwing
  `FormatException` on a missing or malformed value. It is read while a
  transport is being attached, from inside a stream handler, where a throw
  aborts the pass and is raised with nothing listening.
* **`propertiesChanged` on a device or a transport whose interface has gone
  yields an empty stream** rather than throwing a bare `String`. Same reason:
  these are read while building subscriptions, often from inside another
  handler.

## 0.8.2+headunit.3

* **An `org.bluez.Agent1` handler can no longer fail without answering.** They
  all asserted the device was already cached, with `!`. `InterfacesAdded` is
  delivered asynchronously while an agent call is dispatched synchronously from
  the same socket read, so for a device bluetoothd has just discovered - an
  inbound pairing - the `!` threw. package:dbus writes the reply only after the
  handler completes and swallows the error, so bluetoothd waited for ever and
  the pairing died with nothing logged. `awaitDevice` asks the daemon on a
  cache miss, and the dispatch is guarded so every call gets a reply. The
  cached path stays synchronous, because an agent may hold its response open
  until `Cancel` arrives and a microtask of delay would let a `Cancel` race it.
* **`mediaPlayerAdded` / `mediaPlayerRemoved`.** A player is announced as
  `InterfacesAdded` on a new object path below the device, which is neither an
  adapter nor a device, so its arrival was previously unobservable - and a
  device's `PropertiesChanged` cannot carry it, those streams being per
  interface. AVRCP metadata arrives after `Connected`, so there was nothing to
  attach to at the moment there was something to show.
* **`BlueZDevice.mediaPlayer` finds the player by interface** below the device,
  not by `MediaControl1.Player`. That property's `?? <device>/player0` fallback
  is gone: BlueZ increments the number across AVRCP reconnects, so the guess
  points at a dead object for the rest of the session. `player` is now
  nullable, and `BlueZMediaPlayer.path` is exposed so one player object can be
  told from another. `getMediaPlayer` verifies the interface, as
  `getMediaTransports` already did.
* **Removing an interface closes its property stream.** A subscription to a
  controller that can never fire again, and never completes, is a listener that
  will never re-attach - which is what happened to absolute volume every time
  an A2DP stream was torn down and reconfigured, as a call over HFP does.

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

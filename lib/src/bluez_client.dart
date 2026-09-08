import 'dart:async';

import 'package:bluez/src/bluez_adapter.dart';
import 'package:bluez/src/bluez_agent_object.dart';
import 'package:bluez/src/bluez_characteristic.dart';
import 'package:bluez/src/bluez_device.dart';
import 'package:bluez/src/bluez_enums.dart';
import 'package:bluez/src/bluez_gatt_descriptor.dart';
import 'package:bluez/src/bluez_gatt_service.dart';
import 'package:bluez/src/bluez_media_player.dart';
import 'package:bluez/src/bluez_media_transport.dart';
import 'package:bluez/src/bluez_object.dart';
import 'package:dbus/dbus.dart';
import 'package:bluez/src/bluez_agent.dart';

/// A client that connects to BlueZ.
class BlueZClient {
  /// Stream of adapters as they are added.
  Stream<BlueZAdapter> get adapterAdded => _adapterAddedStreamController.stream;

  /// Stream of adapters as they are removed.
  Stream<BlueZAdapter> get adapterRemoved =>
      _adapterRemovedStreamController.stream;

  /// Stream of devices as they are added.
  Stream<BlueZDevice> get deviceAdded => _deviceAddedStreamController.stream;

  /// Stream of devices as they are removed.
  Stream<BlueZDevice> get deviceRemoved =>
      _deviceRemovedStreamController.stream;

  /// The bus this client is connected to.
  final DBusClient _bus;
  final bool _closeBus;

  /// The root D-Bus BlueZ object.
  late final DBusRemoteObjectManager _root;

  // Objects exported on the bus.
  final _objects = <DBusObjectPath, BlueZObject>{};

  // Subscription to object manager signals.
  StreamSubscription? _objectManagerSubscription;
  StreamSubscription? _nameOwnerSubscription;
  Future<void> _repopulating = Future.value();

  /// Stream of media players as they are added.
  ///
  /// The only way to learn that a device's AVRCP player has appeared. BlueZ
  /// announces it as `InterfacesAdded` on a **new** object path below the
  /// device - `/org/bluez/hci0/dev_XX/playerN` - which is neither an adapter
  /// nor a device, so it used to be absorbed silently: the object was cached
  /// and nothing was told. A client watching the device's own
  /// `PropertiesChanged` never hears it either, because those streams are per
  /// interface and the player is a different object.
  ///
  /// Metadata usually arrives a second or two after `Connected`, so without
  /// this a media UI has nothing to attach to at the moment there is finally
  /// something to show.
  Stream<BlueZMediaPlayer> get mediaPlayerAdded =>
      _mediaPlayerAddedStreamController.stream;

  /// Stream of media players as they are removed.
  Stream<BlueZMediaPlayer> get mediaPlayerRemoved =>
      _mediaPlayerRemovedStreamController.stream;

  final _mediaPlayerAddedStreamController =
      StreamController<BlueZMediaPlayer>.broadcast();
  final _mediaPlayerRemovedStreamController =
      StreamController<BlueZMediaPlayer>.broadcast();

  /// Stream of media transports as they are added.
  ///
  /// The other half of what the player streams answer, and needed for the
  /// same reason: a transport lives on its own object path below the device,
  /// so its arrival is neither an adapter nor a device event and used to be
  /// absorbed silently. A phone call tears the A2DP stream down and
  /// reconfigures it, so a client holding the transport for absolute volume
  /// has to be told when the new one arrives - nothing on the device itself
  /// changes.
  Stream<BlueZMediaTransport> get mediaTransportAdded =>
      _mediaTransportAddedStreamController.stream;

  /// Stream of media transports as they are removed.
  Stream<BlueZMediaTransport> get mediaTransportRemoved =>
      _mediaTransportRemovedStreamController.stream;

  final _mediaTransportAddedStreamController =
      StreamController<BlueZMediaTransport>.broadcast();
  final _mediaTransportRemovedStreamController =
      StreamController<BlueZMediaTransport>.broadcast();

  final _adapterAddedStreamController =
      StreamController<BlueZAdapter>.broadcast();
  final _adapterRemovedStreamController =
      StreamController<BlueZAdapter>.broadcast();
  final _deviceAddedStreamController =
      StreamController<BlueZDevice>.broadcast();
  final _deviceRemovedStreamController =
      StreamController<BlueZDevice>.broadcast();

  /// Registered agent.
  BlueZAgentObject? _agent;

  /// Creates a new BlueZ client. If [bus] is provided connect to the given D-Bus server.
  BlueZClient({DBusClient? bus})
      : _bus = bus ?? DBusClient.system(),
        _closeBus = bus == null {
    _root = DBusRemoteObjectManager(_bus,
        name: 'org.bluez', path: DBusObjectPath('/'));
  }

  /// Connects to the BlueZ daemon.
  /// Must be called before accessing methods and properties.
  Future<void> connect() async {
    // Already connected
    if (_objectManagerSubscription != null) {
      return;
    }

    // Subscribe to changes
    _objectManagerSubscription = _root.signals.listen((signal) {
      if (signal is DBusObjectManagerInterfacesAddedSignal) {
        var object = _objects[signal.changedPath];
        if (object != null) {
          object.updateInterfaces(signal.interfacesAndProperties);
        } else {
          object = BlueZObject(
              _bus, signal.changedPath, signal.interfacesAndProperties);
          _objects[signal.changedPath] = object;
          if (_isAdapter(object)) {
            _adapterAddedStreamController.add(BlueZAdapter(this, object));
          } else if (_isDevice(object)) {
            _deviceAddedStreamController.add(BlueZDevice(this, object));
          }
        }
        // Announced whether the object is new or gained the interface, and
        // separately from the adapter/device branches above: a player arrives
        // on its own path below a device that already exists.
        if (signal.interfacesAndProperties
            .containsKey('org.bluez.MediaPlayer1')) {
          _mediaPlayerAddedStreamController.add(BlueZMediaPlayer(this, object));
        }
        if (signal.interfacesAndProperties
            .containsKey('org.bluez.MediaTransport1')) {
          _mediaTransportAddedStreamController
              .add(BlueZMediaTransport(this, object));
        }
      } else if (signal is DBusObjectManagerInterfacesRemovedSignal) {
        var object = _objects[signal.changedPath];
        if (object != null) {
          // If all the interface are removed, then this object has been removed.
          // Keep the previous values around for the client to use.
          if (object.wouldRemoveAllInterfaces(signal.interfaces)) {
            _objects.remove(signal.changedPath);
          } else {
            object.removeInterfaces(signal.interfaces);
          }

          if (signal.interfaces.contains('org.bluez.Adapter1')) {
            _adapterRemovedStreamController.add(BlueZAdapter(this, object));
          } else if (signal.interfaces.contains('org.bluez.Device1')) {
            _deviceRemovedStreamController.add(BlueZDevice(this, object));
          }
          if (signal.interfaces.contains('org.bluez.MediaPlayer1')) {
            _mediaPlayerRemovedStreamController
                .add(BlueZMediaPlayer(this, object));
          }
          if (signal.interfaces.contains('org.bluez.MediaTransport1')) {
            _mediaTransportRemovedStreamController
                .add(BlueZMediaTransport(this, object));
          }
          // Closed last, so the removal above is emitted while the object can
          // still be read. Without this a listener on a removed interface is
          // left holding a subscription to a controller that can never fire
          // again and never completes - so nothing tells it to re-attach when
          // the interface comes back. An A2DP stream torn down and
          // reconfigured, which is what a call over HFP does, hit this every
          // time.
          object.releaseInterfaces(signal.interfaces);
        }
      } else if (signal is DBusPropertiesChangedSignal) {
        var object = _objects[signal.path];
        if (object != null) {
          object.updateProperties(
              signal.propertiesInterface, signal.changedProperties);
        }
      }
    });

    // bluetoothd restarting, or crashing and being restarted by systemd.
    //
    // Everything is re-announced on paths already in the cache, so
    // `InterfacesAdded` takes the update path and notifies nobody - and
    // devices the new bluetoothd has never heard of are never removed. The
    // client was left reporting the state from before the restart: a phone
    // marked connected that is not, and rows for devices that no longer
    // exist, until some unrelated property changed on each one.
    _nameOwnerSubscription =
        _bus.nameOwnerChanged.where((e) => e.name == 'org.bluez').listen((_) {
      // Serialised: a restart produces two owner changes - the name lost, then
      // acquired - and package:dbus can deliver both from one socket read.
      // Two repopulations interleaving leaves the loser announcing objects
      // that have already been replaced in the cache, so a listener ends up
      // subscribed to an orphaned controller that can never fire.
      _repopulating = _repopulating.then((_) => _repopulate());
    });

    await _populate();
  }

  /// Reads every object bluetoothd exports and announces what is there.
  Future<void> _populate() async {
    var objects = await _root.getManagedObjects();
    objects.forEach((objectPath, interfacesAndProperties) {
      _objects[objectPath] =
          BlueZObject(_bus, objectPath, interfacesAndProperties);
    });

    // Report initial adapters and devices.
    for (var object in _objects.values) {
      if (_isAdapter(object)) {
        _adapterAddedStreamController.add(BlueZAdapter(this, object));
      } else if (_isDevice(object)) {
        _deviceAddedStreamController.add(BlueZDevice(this, object));
      }
    }
  }

  /// Throws the cache away and reads it again, announcing the difference.
  ///
  /// For a new owner of `org.bluez`. Removals are emitted before the objects
  /// go, so a client can see what left; property streams are closed with
  /// them, which is what tells a listener holding a subscription that its
  /// object is gone rather than merely quiet.
  Future<void> _repopulate() async {
    var previous = Map.of(_objects);
    _objects.clear();

    for (var object in previous.values) {
      if (_isAdapter(object)) {
        _adapterRemovedStreamController.add(BlueZAdapter(this, object));
      } else if (_isDevice(object)) {
        _deviceRemovedStreamController.add(BlueZDevice(this, object));
      }
      if (_isMediaPlayer(object)) {
        _mediaPlayerRemovedStreamController.add(BlueZMediaPlayer(this, object));
      }
      if (_isMediaTransport(object)) {
        _mediaTransportRemovedStreamController
            .add(BlueZMediaTransport(this, object));
      }
      object.release();
    }

    try {
      await _populate();
      // The new daemon has never heard of our agent. Re-registering is not
      // optional: without it an inbound pairing falls back to Just Works.
      await _reregisterAgent();
    } on DBusMethodResponseException catch (_) {
      // bluetoothd is on its way out rather than back in - the name changed
      // owner to nobody. The next change brings us back.
    }
  }

  /// The adapters present on this system.
  /// Use [adapterAdded] and [adapterRemoved] to detect when this list changes.
  List<BlueZAdapter> get adapters {
    var adapters = <BlueZAdapter>[];
    for (var object in _objects.values) {
      if (_isAdapter(object)) {
        adapters.add(BlueZAdapter(this, object));
      }
    }
    return adapters;
  }

  /// The devices on this system.
  /// Use [deviceAdded] and [deviceRemoved] to detect when this list changes.
  List<BlueZDevice> get devices {
    var devices = <BlueZDevice>[];
    for (var object in _objects.values) {
      if (_isDevice(object)) {
        devices.add(BlueZDevice(this, object));
      }
    }
    return devices;
  }

  /// Registers an agent handler.
  /// A D-Bus object will be registered on [path], which the user must choose to not collide with any other path on the D-Bus client that was passed in the [BlueZClient] constructor.
  Future<void> registerAgent(BlueZAgent agent,
      {DBusObjectPath? path,
      var capability = BlueZAgentCapability.keyboardDisplay}) async {
    if (_agent != null) {
      throw 'Agent already registered';
    }
    _agentCapability = capability;
    _agentIsDefault = false;

    var object = _objects[DBusObjectPath('/org/bluez')];
    if (object == null) {
      throw 'Missing /org/bluez object required for agent registration';
    }

    var object_ = BlueZAgentObject(
        this, agent, path ?? DBusObjectPath('/org/bluez/Agent'));
    // Assigned before the calls that can fail, so a caller that catches a
    // failure here still has a client whose state matches reality: the D-Bus
    // object is exported and BlueZ may well hold it, so `unregisterAgent`
    // has to be able to take it back.
    _agent = object_;
    await _bus.registerObject(object_);

    var capabilityString = {
          BlueZAgentCapability.displayOnly: 'DisplayOnly',
          BlueZAgentCapability.displayYesNo: 'DisplayYesNo',
          BlueZAgentCapability.keyboardOnly: 'KeyboardOnly',
          BlueZAgentCapability.noInputNoOutput: 'NoInputNoOutput',
          BlueZAgentCapability.keyboardDisplay: 'KeyboardDisplay',
        }[capability] ??
        '';

    await object.callMethod('org.bluez.AgentManager1', 'RegisterAgent',
        [_agent!.path, DBusString(capabilityString)],
        replySignature: DBusSignature(''));
  }

  BlueZAgentCapability? _agentCapability;
  bool _agentIsDefault = false;

  /// Registers the agent again with a daemon that has just come back.
  ///
  /// A new bluetoothd has no record of our agent, and nothing else would ever
  /// tell it: the D-Bus object is still exported on our side and `_agent` is
  /// still set, so a client cannot recover by calling [registerAgent] again -
  /// it would be told the agent is already registered. Without this, an
  /// inbound pairing after `systemctl restart bluetooth` falls back to Just
  /// Works: a device in range pairs with no confirmation and nothing on
  /// screen.
  Future<void> _reregisterAgent() async {
    var agent = _agent;
    var capability = _agentCapability;
    if (agent == null || capability == null) {
      return;
    }
    var object = _objects[DBusObjectPath('/org/bluez')];
    if (object == null) {
      return;
    }
    try {
      await object.callMethod('org.bluez.AgentManager1', 'RegisterAgent',
          [agent.path, DBusString(_capabilityName(capability))],
          replySignature: DBusSignature(''));
      if (_agentIsDefault) {
        await object.callMethod(
            'org.bluez.AgentManager1', 'RequestDefaultAgent', [agent.path],
            replySignature: DBusSignature(''));
      }
    } on DBusMethodResponseException catch (_) {
      // The daemon is not ready for it yet. Nothing else is lost: the next
      // owner change tries again.
    }
  }

  static String _capabilityName(BlueZAgentCapability capability) =>
      {
        BlueZAgentCapability.displayOnly: 'DisplayOnly',
        BlueZAgentCapability.displayYesNo: 'DisplayYesNo',
        BlueZAgentCapability.keyboardOnly: 'KeyboardOnly',
        BlueZAgentCapability.noInputNoOutput: 'NoInputNoOutput',
        BlueZAgentCapability.keyboardDisplay: 'KeyboardDisplay',
      }[capability] ??
      '';

  /// Unregisters the agent handler previouly registered with [registerAgent].
  Future<void> unregisterAgent() async {
    if (_agent == null) {
      throw 'No agent registered';
    }

    var object = _objects[DBusObjectPath('/org/bluez')];
    if (object == null) {
      throw 'Missing /org/bluez object required for agent unregistration';
    }

    await object.callMethod(
        'org.bluez.AgentManager1', 'UnregisterAgent', [_agent!.path],
        replySignature: DBusSignature(''));
    _agent = null;
  }

  /// Requests that the agent set with [registerAgent] is the system default agent.
  Future<void> requestDefaultAgent() async {
    var object = _objects[DBusObjectPath('/org/bluez')];
    if (object == null) {
      throw 'Missing /org/bluez object required for agent unregistration';
    }

    var agent = _agent;
    if (agent == null) {
      throw 'No agent registered';
    }
    await object.callMethod(
        'org.bluez.AgentManager1', 'RequestDefaultAgent', [agent.path],
        replySignature: DBusSignature(''));
    // Remembered, so a daemon restart can ask again - and checked above
    // rather than dereferenced, which is what every other method here does.
    _agentIsDefault = true;
  }

  /// Terminates all active connections. If a client remains unclosed, the Dart process may not terminate.
  Future<void> close() async {
    if (_objectManagerSubscription != null) {
      await _objectManagerSubscription?.cancel();
      _objectManagerSubscription = null;
    }
    await _nameOwnerSubscription?.cancel();
    _nameOwnerSubscription = null;
    // Every per-interface property stream, so a listener that outlives the
    // client is completed rather than left waiting.
    for (var object in _objects.values) {
      object.release();
    }
    if (_closeBus) {
      await _bus.close();
    }
  }

  bool _isDevice(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.Device1');
  }

  bool _isAdapter(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.Adapter1');
  }
}

/// This extension is for internal use within the plugin and is not part of the public API.
extension BluezClientInternalExtension on BlueZClient {
  Future<void> registerObject(DBusObject object) => _bus.registerObject(object);

  Future<void> unregisterObject(DBusObject object) =>
      _bus.unregisterObject(object);

  BlueZDevice? getDevice(DBusObjectPath objectPath) {
    var object = _objects[objectPath];
    return object == null ? null : BlueZDevice(this, object);
  }

  /// Looks a device up, asking the daemon if the object manager has not
  /// caught up yet.
  ///
  /// [getDevice] answers from the cache, and the cache is filled from
  /// `InterfacesAdded`, which is delivered **asynchronously**. An
  /// `org.bluez.Agent1` call about a device is dispatched **synchronously**
  /// from the same socket read. So when bluetoothd announces a device it has
  /// never seen before and asks the agent about it in the same breath - which
  /// is exactly what an inbound pairing looks like - the cache can still be
  /// empty when the agent is called.
  ///
  /// An agent handler must never fail on that: package:dbus writes the reply
  /// only after the handler's future completes, so a throw means bluetoothd
  /// waits for a reply that never comes and the pairing dies with nothing on
  /// screen and nothing in the log.
  ///
  /// Fetching is safe here because the caller is inside a method handler that
  /// bluetoothd is already waiting on.
  Future<BlueZDevice?> awaitDevice(DBusObjectPath objectPath) async {
    var known = getDevice(objectPath);
    if (known != null) {
      return known;
    }
    try {
      var remote = DBusRemoteObject(_bus, name: 'org.bluez', path: objectPath);
      var properties = await remote.getAllProperties('org.bluez.Device1');
      if (properties.isEmpty) {
        return null;
      }
      var object =
          BlueZObject(_bus, objectPath, {'org.bluez.Device1': properties});
      _objects[objectPath] = object;
      // Announced, so a client that keeps its own list still learns about it:
      // the InterfacesAdded that follows will find the path already cached
      // and take the update path, which emits nothing.
      _deviceAddedStreamController.add(BlueZDevice(this, object));
      return BlueZDevice(this, object);
    } on DBusMethodResponseException catch (_) {
      return null;
    }
  }

  BlueZAdapter? getAdapter(DBusObjectPath objectPath) {
    var object = _objects[objectPath];
    return object == null ? null : BlueZAdapter(this, object);
  }

  BlueZMediaPlayer? getMediaPlayer(DBusObjectPath objectPath) {
    var object = _objects[objectPath];
    if (object == null || !_isMediaPlayer(object)) {
      return null;
    }
    return BlueZMediaPlayer(this, object);
  }

  /// The media player below [parentPath], if there is one.
  ///
  /// Found by interface, the way [getMediaTransports] works, rather than by
  /// the path in `org.bluez.MediaControl1.Player`. Two reasons: that interface
  /// is deprecated and often absent, and BlueZ increments the player number
  /// across AVRCP reconnects - so a device's player can be `player1` or
  /// `player2`, and anything that assumes `player0` points at an object that
  /// no longer exists for the rest of the session.
  BlueZMediaPlayer? getMediaPlayerFor(DBusObjectPath parentPath) {
    for (var object in _objects.values) {
      if (object.path.isInNamespace(parentPath) && _isMediaPlayer(object)) {
        return BlueZMediaPlayer(this, object);
      }
    }
    return null;
  }

  bool _isMediaPlayer(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.MediaPlayer1');
  }

  List<BlueZMediaTransport> getMediaTransports(DBusObjectPath parentPath) {
    var transports = <BlueZMediaTransport>[];
    for (var object in _objects.values) {
      if (object.path.isInNamespace(parentPath) && _isMediaTransport(object)) {
        transports.add(BlueZMediaTransport(this, object));
      }
    }
    return transports;
  }

  bool _isMediaTransport(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.MediaTransport1');
  }

  List<BlueZGattService> getGattServices(DBusObjectPath parentPath) {
    var services = <BlueZGattService>[];
    for (var object in _objects.values) {
      if (object.path.isInNamespace(parentPath) && _isGattService(object)) {
        services.add(BlueZGattService(this, object));
      }
    }
    return services;
  }

  bool _isGattService(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.GattService1');
  }

  List<BlueZGattCharacteristic> getGattCharacteristics(
      DBusObjectPath parentPath) {
    var characteristics = <BlueZGattCharacteristic>[];
    for (var object in _objects.values) {
      if (object.path.isInNamespace(parentPath) &&
          _isGattCharacteristic(object)) {
        characteristics.add(BlueZGattCharacteristic(this, object));
      }
    }
    return characteristics;
  }

  bool _isGattCharacteristic(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.GattCharacteristic1');
  }

  List<BlueZGattDescriptor> getGattDescriptors(DBusObjectPath parentPath) {
    var descriptors = <BlueZGattDescriptor>[];
    for (var object in _objects.values) {
      if (object.path.isInNamespace(parentPath) && _isGattDescriptor(object)) {
        descriptors.add(BlueZGattDescriptor(object));
      }
    }
    return descriptors;
  }

  bool _isGattDescriptor(BlueZObject object) {
    return object.interfaces.containsKey('org.bluez.GattDescriptor1');
  }
}
